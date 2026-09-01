package com.orgista.openstream.iptv

import com.orgista.openstream.data.UserAgents
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.temporal.ChronoUnit

class PlutoSession(
    val token: String,
    val stitcherUrl: String,
    val stitcherParams: String,
) {
    override fun toString(): String =
        "PlutoSession(token=<redacted>,stitcherUrl=$stitcherUrl,stitcherParams=<redacted>)"
}

/**
 * Opt-in Pluto TV source using its current boot/session and v2 guide APIs.
 * Channels, schedules, and short-lived stream locators are fetched at runtime;
 * no provider lineup or playback token is compiled into OpenStream.
 */
object PlutoIptvClient {
    private const val BOOT_URL = "https://boot.pluto.tv/v4/start"
    private const val CHANNELS_URL = "https://service-channels.clusters.pluto.tv/v2/guide/channels"
    private const val CATEGORIES_URL = "https://service-channels.clusters.pluto.tv/v2/guide/categories"
    private const val TIMELINES_URL = "https://service-channels.clusters.pluto.tv/v2/guide/timelines"
    private const val MAX_RESPONSE_BYTES = 8_000_000
    private const val GUIDE_DURATION_MINUTES = 360
    private val channelIdPattern = Regex("[a-fA-F0-9]{24}")

    fun load(source: IptvSource): IptvSourceCatalog {
        require(source.type == IptvSourceType.PLUTO)
        val session = parseSession(
            getJson(
                "$BOOT_URL?${query(bootParameters(source.username))}",
                authenticated = false,
            ),
        )
        val auth = "Bearer ${session.token}"
        val catalogQuery = query(mapOf("channelIds" to "", "offset" to "0", "limit" to "1000", "sort" to "number:asc"))
        val channelsRaw = getJson("$CHANNELS_URL?$catalogQuery", authorization = auth)
        val categoriesRaw = getJson("$CATEGORIES_URL?$catalogQuery", authorization = auth)
        val channelIds = JSONObject(channelsRaw).optJSONArray("data").jsonObjects()
            .mapNotNull { it.optString("id").takeIf(channelIdPattern::matches) }
        val start = Instant.now().truncatedTo(ChronoUnit.HOURS).toString()
        val timelines = channelIds.chunked(100).map { ids ->
            getJson(
                "$TIMELINES_URL?${query(mapOf(
                    "start" to start,
                    "channelIds" to ids.joinToString(","),
                    "duration" to GUIDE_DURATION_MINUTES.toString(),
                ))}",
                authorization = auth,
            )
        }
        return parseCatalog(source, channelsRaw, categoriesRaw, timelines, session)
    }

    fun parseSession(rawJson: String): PlutoSession {
        val json = JSONObject(rawJson)
        val token = json.optString("sessionToken")
        require(token.isNotBlank() && token.length <= 16_384) { "Pluto TV did not issue a playback session." }
        val stitcher = json.optJSONObject("servers")?.optString("stitcher").orEmpty().trimEnd('/')
        val uri = runCatching { URI(stitcher) }.getOrNull()
        require(uri?.scheme == "https" && uri.host?.endsWith(".pluto.tv") == true) {
            "Pluto TV returned an invalid playback service."
        }
        val params = json.optString("stitcherParams").removePrefix("?").removePrefix("&")
        require(params.length <= 8_192 && '#' !in params) { "Pluto TV returned invalid session parameters." }
        return PlutoSession(token, stitcher, params)
    }

    fun parseCatalog(
        source: IptvSource,
        channelsRaw: String,
        categoriesRaw: String,
        timelineResponses: List<String>,
        session: PlutoSession,
    ): IptvSourceCatalog {
        val categories = categoryNames(categoriesRaw)
        val channels = JSONObject(channelsRaw).optJSONArray("data").jsonObjects().mapNotNull { json ->
            val id = json.optString("id").takeIf(channelIdPattern::matches) ?: return@mapNotNull null
            val name = json.optString("name").trim().takeIf(String::isNotBlank) ?: return@mapNotNull null
            val category = json.optJSONArray("categoryIDs").strings()
                .firstNotNullOfOrNull(categories::get)
                ?: categories[id]
                ?: "Other"
            val logo = json.optJSONArray("images").jsonObjects()
                .firstOrNull { it.optString("type") == "colorLogoPNG" }
                ?.optString("url")
                .orEmpty()
            IptvChannel(
                id = id,
                sourceId = source.id,
                sourceName = source.name,
                name = name,
                group = category,
                logoUrl = logo,
                streamUrl = streamUrl(session, id),
                httpUserAgent = UserAgents.browser,
                httpReferer = "https://pluto.tv/",
                guideId = id,
                channelNumber = json.opt("number")?.toString().orEmpty(),
            )
        }
        val channelIds = channels.mapTo(hashSetOf(), IptvChannel::id)
        val programs = timelineResponses.flatMap { raw ->
            JSONObject(raw).optJSONArray("data").jsonObjects().flatMap { container ->
                val channelId = container.optString("channelId")
                if (channelId !in channelIds) return@flatMap emptyList()
                container.optJSONArray("timelines").jsonObjects().mapNotNull { timeline ->
                    val start = timeline.optString("start").instantMillis() ?: return@mapNotNull null
                    val end = timeline.optString("stop").instantMillis() ?: return@mapNotNull null
                    if (end <= start) return@mapNotNull null
                    val episode = timeline.optJSONObject("episode")
                    IptvGuideProgram(
                        channelKey = "${source.id}:$channelId",
                        title = timeline.optString("title").ifBlank { episode?.optString("series") ?: "Live TV" },
                        subtitle = episode?.optString("name").orEmpty(),
                        description = episode?.optString("description").orEmpty(),
                        category = episode?.optString("genre").orEmpty(),
                        startMillis = start,
                        endMillis = end,
                    )
                }
            }
        }.distinctBy { "${it.channelKey}:${it.startMillis}:${it.title}" }
        return IptvSourceCatalog(source, channels, embeddedGuidePrograms = programs)
    }

    private fun categoryNames(rawJson: String): Map<String, String> {
        val result = HashMap<String, String>()
        JSONObject(rawJson).optJSONArray("data").jsonObjects().forEach { category ->
            val id = category.optString("id", category.optString("_id"))
            val name = category.optString("name")
            if (id.isNotBlank() && name.isNotBlank()) result[id] = name
            category.optJSONArray("channelIDs").strings().forEach { channelId ->
                if (name.isNotBlank()) result[channelId] = name
            }
        }
        return result
    }

    private fun streamUrl(session: PlutoSession, channelId: String): String = buildString {
        append(session.stitcherUrl)
        append("/v2/stitch/hls/channel/")
        append(channelId)
        append("/master.m3u8?jwt=")
        append(encoded(session.token))
        append("&masterJWTPassthrough=true")
        if (session.stitcherParams.isNotBlank()) append('&').append(session.stitcherParams)
    }

    private fun bootParameters(clientId: String): Map<String, String> = linkedMapOf(
        "appName" to "web",
        "appVersion" to "8.0.0",
        "deviceVersion" to "126.0.0",
        "deviceModel" to "web",
        "deviceMake" to "chrome",
        "deviceType" to "web",
        "clientID" to clientId,
        "clientModelNumber" to "1.0.0",
        "serverSideAds" to "false",
        "drmCapabilities" to "widevine:L3",
        "blockingMode" to "",
    )

    private fun getJson(url: String, authenticated: Boolean = true, authorization: String? = null): String {
        val connection = URI(url).toURL().openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 20_000
        connection.instanceFollowRedirects = true
        connection.setRequestProperty("Accept", "*/*")
        connection.setRequestProperty("Origin", "https://pluto.tv")
        connection.setRequestProperty("Referer", "https://pluto.tv/")
        connection.setRequestProperty("User-Agent", UserAgents.browser)
        if (authenticated && !authorization.isNullOrBlank()) {
            connection.setRequestProperty("Authorization", authorization)
        }
        try {
            val status = connection.responseCode
            require(status in 200..299) { "Pluto TV returned HTTP $status." }
            val output = ByteArrayOutputStream()
            connection.inputStream.use { input ->
                val buffer = ByteArray(16_384)
                var total = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    require(total <= MAX_RESPONSE_BYTES) { "Pluto TV response is too large." }
                    output.write(buffer, 0, count)
                }
            }
            return output.toString(StandardCharsets.UTF_8.name())
        } finally {
            connection.disconnect()
        }
    }

    private fun query(values: Map<String, String>): String = values.entries.joinToString("&") {
        "${encoded(it.key)}=${encoded(it.value)}"
    }

    private fun encoded(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")

    private fun JSONArray?.jsonObjects(): List<JSONObject> =
        if (this == null) emptyList() else (0 until length()).mapNotNull(::optJSONObject)

    private fun JSONArray?.strings(): List<String> =
        if (this == null) emptyList() else (0 until length()).mapNotNull { optString(it).takeIf(String::isNotBlank) }

    private fun String.instantMillis(): Long? = runCatching { Instant.parse(this).toEpochMilli() }.getOrNull()
}
