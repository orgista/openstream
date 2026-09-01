package com.orgista.openstream.data

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.UUID

data class StremioStream(
    val title: String,
    val url: String,
    /** Provider-supplied media filename, used to verify that downloads match the requested title. */
    val filename: String? = null,
)

data class StremioSubtitle(
    val id: String,
    val url: String,
    val language: String,
    val mimeType: String,
)

data class StremioRecommendation(
    val type: String,
    val id: String,
    val title: String,
    val description: String? = null,
)

object StremioRetryPolicy {
    private const val MAX_RETRIES = 3

    fun shouldRetry(httpCode: Int, attempt: Int): Boolean =
        attempt < MAX_RETRIES && (httpCode == 408 || httpCode == 429 || httpCode in 500..599)

    fun shouldRetry(error: Throwable, attempt: Int): Boolean = attempt < MAX_RETRIES && error is IOException

    fun delayMs(attempt: Int): Long = 250L * (1L shl attempt.coerceIn(0, MAX_RETRIES))
}

object StremioUrlPolicy {
    fun safeLabel(value: String): String {
        val uri = runCatching { URI(value) }.getOrNull() ?: return "Configured add-on"
        val host = uri.host?.takeIf(String::isNotBlank) ?: return "Configured add-on"
        val segments = uri.path.orEmpty().trim('/').split('/').filter(String::isNotBlank)
        val configured = segments.any { it != "manifest.json" }
        return if (configured) "$host · private configuration" else host
    }

    fun requireHttps(value: String): String {
        val trimmed = value.trim().removeSuffix("/")
        val uri = runCatching { URI(trimmed) }.getOrNull()
            ?: throw IllegalArgumentException("Enter a valid add-on URL.")
        if (uri.scheme != "https" || uri.host.isNullOrBlank()) {
            throw IllegalArgumentException("Add-on URLs must use HTTPS.")
        }
        return trimmed
    }
}

private class AddonHttpException(val status: Int) : IOException("Add-on responded with HTTP $status.")

data class StremioAddonTestResult(
    val working: Boolean,
    val message: String,
)

object StremioAddonTestPolicy {
    fun catalogToProbe(addon: StremioAddon): StremioCatalog? = addon.catalogs.firstOrNull { !it.requiresInput }

    fun successMessage(catalogTitleCount: Int?): String = if (catalogTitleCount == null) {
        "Connected. Manifest and capabilities are available. Playback services are checked when a title starts."
    } else {
        "Working. Catalog responded with $catalogTitleCount title${if (catalogTitleCount == 1) "" else "s"}."
    }

    fun failureMessage(failure: Throwable): String = when (failure) {
        is AddonHttpException -> "Add-on returned HTTP ${failure.status}. Its server or configuration may be unavailable."
        is IOException -> "Add-on could not be reached. Check this device's connection and try again."
        else -> failure.message?.takeIf(String::isNotBlank) ?: "Add-on test failed."
    }
}

/**
 * Stremio protocol client for manifest, catalog, meta, and directly playable
 * HTTPS stream resources. Torrent locators are intentionally ignored: the app
 * only hands Media3 a URL it can open itself.
 */
object StremioClient {
    private const val MAX_RESPONSE_BYTES = 2_000_000

    private fun getJson(url: String): JSONObject {
        var lastFailure: Throwable? = null
        for (attempt in 0..3) {
            try {
                return getJsonOnce(url)
            } catch (failure: Throwable) {
                lastFailure = failure
                val retry = when (failure) {
                    is AddonHttpException -> StremioRetryPolicy.shouldRetry(failure.status, attempt)
                    else -> StremioRetryPolicy.shouldRetry(failure, attempt)
                }
                if (!retry) throw failure
                Thread.sleep(StremioRetryPolicy.delayMs(attempt))
            }
        }
        throw lastFailure ?: IllegalStateException("The add-on did not respond.")
    }

    private fun getJsonOnce(url: String): JSONObject {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 15_000
        connection.instanceFollowRedirects = true
        connection.setRequestProperty("Accept", "application/json")
        connection.setRequestProperty("User-Agent", UserAgents.product)
        try {
            val code = connection.responseCode
            if (code !in 200..299) throw AddonHttpException(code)
            val bytes = connection.inputStream.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(16_384)
                var total = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    if (total > MAX_RESPONSE_BYTES) throw IllegalStateException("Add-on response is too large.")
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            return JSONObject(String(bytes, StandardCharsets.UTF_8))
        } finally {
            connection.disconnect()
        }
    }

    /** Fetches and validates a manifest; returns the add-on ready to store. */
    fun loadAddon(value: String): StremioAddon {
        val trimmed = StremioUrlPolicy.requireHttps(value)
        val manifestUrl = if (trimmed.endsWith("manifest.json")) trimmed else "$trimmed/manifest.json"
        return parseManifest(manifestUrl, getJson(manifestUrl).toString())
    }

    /** Fast explicit diagnostic: validate the manifest and, when possible, one real catalog route. */
    fun testAddon(addon: StremioAddon): StremioAddonTestResult = try {
        val base = StremioUrlPolicy.requireHttps(addon.transportUrl)
        val manifestUrl = if (base.endsWith("manifest.json")) base else "$base/manifest.json"
        val current = parseManifest(manifestUrl, getJsonOnce(manifestUrl).toString())
        require(current.manifestId == addon.manifestId) { "Add-on identity changed. Remove it and add the current manifest again." }
        val catalog = StremioAddonTestPolicy.catalogToProbe(current)
        val titleCount = catalog?.let {
            val type = pathSegment(it.type)
            val id = pathSegment(it.id)
            val payload = getJsonOnce("${current.transportUrl}/catalog/$type/$id.json")
            val metas = payload.optJSONArray("metas")
                ?: throw IllegalStateException("Add-on catalog returned an invalid response.")
            metas.length()
        }
        StremioAddonTestResult(true, StremioAddonTestPolicy.successMessage(titleCount))
    } catch (failure: Throwable) {
        StremioAddonTestResult(false, StremioAddonTestPolicy.failureMessage(failure))
    }

    fun parseManifest(manifestUrl: String, rawJson: String): StremioAddon {
        val safeUrl = StremioUrlPolicy.requireHttps(manifestUrl)
        val manifest = JSONObject(rawJson)
        val manifestId = manifest.optString("id")
        val name = manifest.optString("name")
        if (manifestId.isBlank() || name.isBlank()) {
            throw IllegalStateException("The manifest is missing its id or name.")
        }
        val resources = parseResources(manifest.optJSONArray("resources"))
        val catalogs = parseCatalogDescriptors(manifest.optJSONArray("catalogs"))
        return StremioAddon(
            id = UUID.randomUUID().toString(),
            manifestId = manifestId,
            name = name.take(100),
            transportUrl = safeUrl.removeSuffix("/manifest.json"),
            version = manifest.optString("version").take(40),
            resources = resources,
            catalogs = catalogs,
        )
    }

    private fun parseResources(values: JSONArray?): Set<String> {
        if (values == null) return emptySet()
        return (0 until values.length()).mapNotNull { index ->
            when (val value = values.opt(index)) {
                is String -> value
                is JSONObject -> value.optString("name")
                else -> null
            }?.trim()?.takeIf(String::isNotBlank)
        }.toSet()
    }

    private fun parseCatalogDescriptors(values: JSONArray?): List<StremioCatalog> {
        if (values == null) return emptyList()
        return (0 until values.length()).mapNotNull { index ->
            val value = values.optJSONObject(index) ?: return@mapNotNull null
            val type = value.optString("type")
            val id = value.optString("id")
            if (type.isBlank() || id.isBlank() || !StremioMediaTypePolicy.isSupported(type)) return@mapNotNull null
            val extra = value.optJSONArray("extra")
            val requiresInput = extra != null && (0 until extra.length()).any { extraIndex ->
                extra.optJSONObject(extraIndex)?.optBoolean("isRequired") == true
            }
            val supportsSearch = extra != null && (0 until extra.length()).any { extraIndex ->
                extra.optJSONObject(extraIndex)?.optString("name") == "search"
            }
            StremioCatalog(
                type = type,
                id = id,
                name = value.optString("name", id).take(100),
                requiresInput = requiresInput,
                supportsSearch = supportsSearch,
            )
        }
    }

    /** Queries only catalog routes whose manifest explicitly advertises the search extra. */
    fun search(addon: StremioAddon, query: String, maximumResults: Int = 50): List<MediaItem> {
        val safeQuery = query.trim().take(120)
        if (safeQuery.length < 2) return emptyList()
        val results = StremioSearchPolicy.catalogsFor(addon).flatMap { catalog ->
            searchCatalog(addon, catalog, safeQuery)
        }
        return results.distinctBy { it.imdbId ?: it.id }.take(maximumResults.coerceIn(1, 100))
    }

    fun searchCatalog(
        addon: StremioAddon,
        catalog: StremioCatalog,
        query: String,
        maximumResults: Int = 50,
    ): List<MediaItem> {
        val safeQuery = query.trim().take(120)
        if (safeQuery.length < 2 || catalog !in StremioSearchPolicy.catalogsFor(addon)) return emptyList()
        return runCatching {
            val path = StremioSearchPolicy.requestPath(catalog, safeQuery)
            parseCatalog(addon, getJson("${addon.transportUrl}/$path").toString())
        }.getOrDefault(emptyList()).take(maximumResults.coerceIn(1, 100))
    }

    fun catalogSectionsFor(addon: StremioAddon, maximumCatalogs: Int = 8): List<AddonCatalogSection> {
        if (!addon.enabled || "catalog" !in addon.resources) return emptyList()
        return addon.catalogs
            .filterNot { it.requiresInput }
            .take(maximumCatalogs.coerceIn(0, 12))
            .mapNotNull { catalog ->
                runCatching {
                    val type = pathSegment(catalog.type)
                    val id = pathSegment(catalog.id)
                    val items = parseCatalog(addon, getJson("${addon.transportUrl}/catalog/$type/$id.json").toString())
                    AddonCatalogSection(
                        addonId = addon.manifestId,
                        addonName = addon.name,
                        catalogId = "${catalog.type}:${catalog.id}",
                        catalogName = catalog.name,
                        items = items.distinctBy { it.imdbId ?: it.id },
                    ).takeIf { it.items.isNotEmpty() }
                }.getOrNull()
            }
    }

    fun catalogsFor(addon: StremioAddon, maximumCatalogs: Int = 8): List<MediaItem> =
        catalogSectionsFor(addon, maximumCatalogs)
            .flatMap(AddonCatalogSection::items)
            .distinctBy { it.imdbId ?: it.id }

    fun parseCatalog(addon: StremioAddon, rawJson: String): List<MediaItem> {
        val metas = JSONObject(rawJson).optJSONArray("metas") ?: return emptyList()
        return (0 until metas.length()).mapNotNull { index ->
            metas.optJSONObject(index)?.let { parseMetaObject(addon, it) }
        }.take(100)
    }

    fun metaFor(addon: StremioAddon, type: String, id: String): MediaItem? {
        if (!addon.enabled || "meta" !in addon.resources) return null
        val payload = getJson("${addon.transportUrl}/meta/${pathSegment(type)}/${pathSegment(id)}.json")
        return payload.optJSONObject("meta")?.let { parseMetaObject(addon, it) }
    }

    private fun parseMetaObject(addon: StremioAddon, meta: JSONObject): MediaItem? {
        val rawId = meta.optString("id")
        val title = meta.optString("name", meta.optString("title"))
        if (rawId.isBlank() || title.isBlank()) return null
        val type = meta.optString("type", "movie")
        val year = Regex("(?:19|20)\\d{2}").find(meta.optString("releaseInfo", meta.optString("released")))
            ?.value?.toIntOrNull() ?: meta.optInt("year", 0)
        val genres = meta.optJSONArray("genres")?.let { values ->
            (0 until values.length()).mapNotNull { values.optString(it).trim().takeIf(String::isNotBlank) }
        }.orEmpty()
        val imdbId = listOf(meta.optString("imdbId"), meta.optString("imdb_id"), rawId)
            .firstOrNull { it.matches(Regex("tt\\d{5,12}")) }
        val imdbRating = meta.opt("imdbRating")?.toString()
            ?.takeIf { it.isNotBlank() && it != "null" && it != "N/A" }
            ?.let { if ('/' in it) it else "$it/10" }
        val kind = StremioMediaTypePolicy.kind(type) ?: return null
        val episodes = if (kind == MediaKind.SERIES) {
            parseEpisodes(
                values = meta.optJSONArray("videos"),
                seriesTitle = title,
                seriesImdbId = imdbId,
                fallbackYear = year,
                rating = meta.optString("contentRating", meta.optString("certification")),
            )
        } else {
            emptyList()
        }
        return MediaItem(
            id = imdbId ?: "stremio:${addon.manifestId}:$rawId",
            kind = kind,
            title = title.take(180),
            subtitle = if (episodes.isEmpty()) addon.name else {
                val seasons = episodes.mapNotNull(::episodeSeason).distinct().size
                "${episodes.size} episode${if (episodes.size == 1) "" else "s"} · " +
                    "$seasons season${if (seasons == 1) "" else "s"}"
            },
            synopsis = meta.optString("description").take(4_000),
            year = year,
            rating = meta.optString("contentRating", meta.optString("certification")),
            runtimeMinutes = parseRuntime(meta.optString("runtime")),
            posterUrl = safeImage(meta.optString("poster")),
            backdropUrl = safeImage(meta.optString("background", meta.optString("backdrop"))),
            imdbId = imdbId,
            genres = genres.take(8),
            cast = jsonStrings(meta.optJSONArray("cast")).take(12),
            director = firstPerson(meta.opt("director")),
            ratings = imdbRating?.let { TitleRatings(imdb = it) },
            episodes = episodes,
        )
    }

    private fun parseEpisodes(
        values: JSONArray?,
        seriesTitle: String,
        seriesImdbId: String?,
        fallbackYear: Int,
        rating: String,
    ): List<MediaItem> {
        if (values == null) return emptyList()
        return (0 until values.length()).mapNotNull { index ->
            val value = values.optJSONObject(index) ?: return@mapNotNull null
            val season = value.optInt("season", -1)
            val episode = value.optInt("episode", value.optInt("number", -1))
            if (season < 0 || episode < 1) return@mapNotNull null
            val episodeTitle = value.optString("title", value.optString("name", "Episode $episode"))
                .trim()
                .ifBlank { "Episode $episode" }
                .take(180)
            val rawEpisodeId = value.optString("id").trim()
            val episodeId = rawEpisodeId.ifBlank {
                seriesImdbId?.let { "$it:$season:$episode" } ?: return@mapNotNull null
            }
            val released = value.optString("released", value.optString("releaseInfo"))
            val episodeYear = Regex("(?:19|20)\\d{2}").find(released)?.value?.toIntOrNull() ?: fallbackYear
            val thumbnail = safeImage(
                value.optString("thumbnail", value.optString("background", value.optString("poster"))),
            )
            MediaItem(
                id = episodeId.take(220),
                kind = MediaKind.SERIES,
                title = seriesTitle.take(180),
                subtitle = "S$season E$episode · $episodeTitle",
                synopsis = value.optString("overview", value.optString("description")).take(4_000),
                year = episodeYear,
                rating = rating,
                runtimeMinutes = parseRuntime(value.optString("runtime")),
                posterUrl = thumbnail,
                backdropUrl = thumbnail,
                imdbId = seriesImdbId,
            )
        }.distinctBy(MediaItem::id).sortedWith(
            compareBy<MediaItem>({ episodeSeason(it) ?: Int.MAX_VALUE }, { episodeNumber(it) ?: Int.MAX_VALUE }),
        )
    }

    private fun episodeSeason(item: MediaItem): Int? = item.subtitle
        ?.let { Regex("(?i)^S(\\d{1,3})\\s*E\\d{1,4}").find(it) }
        ?.groupValues?.get(1)?.toIntOrNull()

    private fun episodeNumber(item: MediaItem): Int? = item.subtitle
        ?.let { Regex("(?i)^S\\d{1,3}\\s*E(\\d{1,4})").find(it) }
        ?.groupValues?.get(1)?.toIntOrNull()

    /** Resolves directly playable streams for an IMDb title id. */
    fun streamsFor(addon: StremioAddon, type: String, imdbId: String): List<StremioStream> {
        if (!addon.enabled || "stream" !in addon.resources) return emptyList()
        val payload = getJson("${addon.transportUrl}/stream/${pathSegment(type)}/${pathSegment(imdbId)}.json")
        return parseStreams(payload.toString())
    }

    fun parseStreams(rawJson: String): List<StremioStream> {
        val streams = JSONObject(rawJson).optJSONArray("streams") ?: return emptyList()
        return (0 until streams.length()).mapNotNull { index ->
            val stream = streams.optJSONObject(index) ?: return@mapNotNull null
            val url = stream.optString("url")
            if (!url.startsWith("https://") && !url.startsWith("http://")) return@mapNotNull null
            StremioStream(
                title = stream.optString("title", stream.optString("name", "Stream ${index + 1}"))
                    .replace(Regex("[\\r\\n\\t]+"), " ")
                    .take(120),
                url = url,
                filename = stream.optJSONObject("behaviorHints")
                    ?.optString("filename")
                    ?.replace(Regex("[\\r\\n\\t]+"), " ")
                    ?.trim()
                    ?.takeIf(String::isNotBlank)
                    ?.take(240),
            )
        }.distinctBy { it.url }.take(200)
    }

    /** Resolves external captions for a movie or episode identity. */
    fun subtitlesFor(addon: StremioAddon, type: String, mediaId: String): List<StremioSubtitle> {
        if (!addon.enabled || "subtitles" !in addon.resources) return emptyList()
        val payload = getJson("${addon.transportUrl}/subtitles/${pathSegment(type)}/${pathSegment(mediaId)}.json")
        return parseSubtitles(payload.toString())
    }

    fun parseSubtitles(rawJson: String): List<StremioSubtitle> {
        val subtitles = JSONObject(rawJson).optJSONArray("subtitles") ?: return emptyList()
        return (0 until subtitles.length()).mapNotNull { index ->
            val subtitle = subtitles.optJSONObject(index) ?: return@mapNotNull null
            val url = subtitle.optString("url").trim()
            if (!url.startsWith("https://") && !url.startsWith("http://")) return@mapNotNull null
            val language = subtitle.optString("lang", "und")
                .replace(Regex("[\\r\\n\\t]+"), " ")
                .trim()
                .ifBlank { "und" }
                .take(24)
            StremioSubtitle(
                id = subtitle.optString("id", "subtitle-${index + 1}")
                    .replace(Regex("[\\r\\n\\t]+"), " ")
                    .trim()
                    .ifBlank { "subtitle-${index + 1}" }
                    .take(100),
                url = url,
                language = language,
                mimeType = subtitleMimeType(url),
            )
        }.distinctBy { it.url }.take(100)
    }

    /** Reads Stremio detail links exposed by recommendation-style stream add-ons. */
    fun recommendationsFor(addon: StremioAddon, type: String, mediaId: String): List<StremioRecommendation> {
        if (!addon.enabled || "stream" !in addon.resources) return emptyList()
        val payload = getJson("${addon.transportUrl}/stream/${pathSegment(type)}/${pathSegment(mediaId)}.json")
        return parseRecommendations(payload.toString())
    }

    fun parseRecommendations(rawJson: String): List<StremioRecommendation> {
        val streams = JSONObject(rawJson).optJSONArray("streams") ?: return emptyList()
        return (0 until streams.length()).mapNotNull { index ->
            val stream = streams.optJSONObject(index) ?: return@mapNotNull null
            val destination = recommendationDestination(stream.optString("externalUrl")) ?: return@mapNotNull null
            val title = stream.optString("name", stream.optString("title", destination.second))
                .replace(Regex("[\\r\\n\\t]+"), " ")
                .trim()
                .ifBlank { destination.second }
                .take(120)
            StremioRecommendation(
                type = destination.first,
                id = destination.second,
                title = title,
                description = stream.optString("description")
                    .trim()
                    .takeIf(String::isNotBlank)
                    ?.take(1_000),
            )
        }.distinctBy { "${it.type}:${it.id}" }.take(40)
    }

    private fun recommendationDestination(value: String): Pair<String, String>? {
        val uri = runCatching { URI(value.trim()) }.getOrNull() ?: return null
        if (!uri.scheme.equals("stremio", ignoreCase = true)) return null
        val path = uri.path.orEmpty().trim('/').split('/').filter(String::isNotBlank)
        val segments = if (uri.host.equals("detail", ignoreCase = true)) listOf("detail") + path else path
        if (segments.size < 3 || !segments[0].equals("detail", ignoreCase = true)) return null
        val type = segments[1].lowercase()
        val id = segments[2].trim()
        if (type !in setOf("movie", "series") || id.isBlank()) return null
        return type to id.take(160)
    }

    private fun subtitleMimeType(url: String): String {
        val path = runCatching { URI(url.trim()).path }.getOrNull()?.lowercase()
            ?: url.trim().substringBefore('?').substringBefore('#').lowercase()
        return when {
            path.endsWith(".vtt") -> "text/vtt"
            path.endsWith(".ass") || path.endsWith(".ssa") -> "text/x-ssa"
            path.endsWith(".ttml") -> "application/ttml+xml"
            else -> "application/x-subrip"
        }
    }

    private fun pathSegment(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")

    private fun parseRuntime(value: String): Int = Regex("\\d+").find(value)?.value?.toIntOrNull() ?: 0

    private fun safeImage(value: String): String? = value.takeIf {
        it.startsWith("https://") || it.startsWith("http://")
    }

    private fun jsonStrings(values: JSONArray?): List<String> =
        if (values == null) emptyList()
        else (0 until values.length()).mapNotNull { values.optString(it).trim().takeIf(String::isNotBlank) }

    private fun firstPerson(value: Any?): String? = when (value) {
        is JSONArray -> jsonStrings(value).firstOrNull()
        is String -> {
            val trimmed = value.trim()
            when {
                trimmed.isBlank() || trimmed == "[]" || trimmed.equals("null", ignoreCase = true) -> null
                trimmed.startsWith("[") -> runCatching { jsonStrings(JSONArray(trimmed)).firstOrNull() }.getOrNull()
                else -> trimmed.substringBefore(',').trim().takeIf(String::isNotBlank)
            }
        }
        else -> null
    }
}

object StremioSearchPolicy {
    fun catalogsFor(addon: StremioAddon): List<StremioCatalog> {
        if (!addon.enabled || "catalog" !in addon.resources) return emptyList()
        return addon.catalogs
            .filter(StremioCatalog::supportsSearch)
            .distinctBy(StremioCatalog::type)
            .take(4)
    }

    fun requestPath(catalog: StremioCatalog, query: String): String =
        "catalog/${pathSegment(catalog.type)}/${pathSegment(catalog.id)}/search=${pathSegment(query.trim())}.json"

    private fun pathSegment(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")
}

/** Merges remote discovery metadata without replacing a local playable route. */
object StremioCatalogMerger {
    fun retainCachedMetadata(fresh: List<MediaItem>, cached: List<MediaItem>): List<MediaItem> {
        val cachedByIdentity = cached.associateBy { it.imdbId ?: it.id }
        return fresh.map { item ->
            cachedByIdentity[item.imdbId ?: item.id]?.let { mergeItem(item, it) } ?: item
        }
    }

    fun merge(local: List<MediaItem>, remote: List<MediaItem>): List<MediaItem> {
        val result = LinkedHashMap<String, MediaItem>()
        (local + remote).forEach { incoming ->
            val key = incoming.imdbId ?: incoming.id
            val existing = result[key]
            result[key] = if (existing == null) incoming else mergeItem(existing, incoming)
        }
        return result.values.toList()
    }

    fun mergeItem(preferred: MediaItem, extra: MediaItem): MediaItem {
        val ratings = TitleRatings(
            imdb = preferred.ratings?.imdb ?: extra.ratings?.imdb,
            rottenTomatoes = preferred.ratings?.rottenTomatoes ?: extra.ratings?.rottenTomatoes,
            metacritic = preferred.ratings?.metacritic ?: extra.ratings?.metacritic,
        ).takeIf { it.imdb != null || it.rottenTomatoes != null || it.metacritic != null }
        return preferred.copy(
            synopsis = preferred.synopsis.ifBlank { extra.synopsis },
            year = preferred.year.takeIf { it > 0 } ?: extra.year,
            rating = preferred.rating.ifBlank { extra.rating },
            runtimeMinutes = preferred.runtimeMinutes.takeIf { it > 0 } ?: extra.runtimeMinutes,
            posterUrl = preferred.posterUrl ?: extra.posterUrl,
            backdropUrl = preferred.backdropUrl ?: extra.backdropUrl,
            trailerYoutubeKey = preferred.trailerYoutubeKey ?: extra.trailerYoutubeKey,
            imdbId = preferred.imdbId ?: extra.imdbId,
            tmdbId = preferred.tmdbId ?: extra.tmdbId,
            genres = (preferred.genres + extra.genres).distinctBy(String::lowercase),
            cast = (preferred.cast + extra.cast).distinct().take(12),
            director = preferred.director.validPerson() ?: extra.director.validPerson(),
            tagline = preferred.tagline ?: extra.tagline,
            ratings = ratings,
            candidates = (preferred.candidates + extra.candidates)
                .distinctBy { candidate -> candidate.id to candidate.uri },
            episodes = mergeEpisodes(preferred.episodes, extra.episodes),
        )
    }

    private fun mergeEpisodes(preferred: List<MediaItem>, extra: List<MediaItem>): List<MediaItem> {
        val result = LinkedHashMap<String, MediaItem>()
        (preferred + extra).forEach { episode ->
            val key = episode.subtitle?.substringBefore('·')?.trim()?.lowercase() ?: episode.id
            val existing = result[key]
            result[key] = if (existing == null) episode else mergeItem(existing, episode)
        }
        return result.values.toList()
    }

    private fun String?.validPerson(): String? = this
        ?.trim()
        ?.takeIf { it.isNotBlank() && it != "[]" && !it.equals("null", ignoreCase = true) }
}
