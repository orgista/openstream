package com.orgista.openstream.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class NasConnection(
    val id: String,
    val name: String,
    val host: String,
    val share: String,
    val username: String,
    val password: String,
)

data class StremioAddon(
    val id: String,
    val name: String,
    val transportUrl: String,
    val version: String,
    val manifestId: String = id,
    val resources: Set<String> = setOf("stream"),
    val catalogs: List<StremioCatalog> = emptyList(),
    val enabled: Boolean = true,
)

data class StremioCatalog(
    val type: String,
    val id: String,
    val name: String,
    val requiresInput: Boolean = false,
    val supportsSearch: Boolean = false,
)

object StremioAddonPresentation {
    fun isRecommendationProvider(addon: StremioAddon): Boolean =
        addon.manifestId == "community.watch.next" || addon.name.equals("Watch Next", ignoreCase = true)

    /**
     * A `stream` resource is not automatically a video source. Recommendation
     * add-ons such as Watch Next use that resource for external Stremio links,
     * which OpenStream intentionally does not hand to Media3.
     */
    fun isPlaybackProvider(addon: StremioAddon): Boolean =
        addon.enabled && "stream" in addon.resources && !isRecommendationProvider(addon)

    fun usage(addon: StremioAddon): String = if (isRecommendationProvider(addon)) {
        "Adds recommendations to Discover"
    } else {
        usage(addon.resources)
    }

    fun usage(resources: Set<String>): String = buildList {
        if ("catalog" in resources) add("Adds rows to Discover")
        if ("meta" in resources) add("Adds title details")
        if ("stream" in resources) add("Finds playback streams")
        if ("subtitles" in resources) add("Adds captions during playback")
    }.joinToString(" · ").ifBlank { "Connected add-on" }
}

object StremioAddonRemovalPolicy {
    fun visible(configured: List<StremioAddon>): List<StremioAddon> = configured
        .distinctBy { it.manifestId to it.transportUrl }
}

/**
 * Connection storage in app-private preferences. Credentials never leave the
 * app sandbox and disappear with app data — the same lifecycle as the kids
 * lock, so a reset wipes both together.
 */
class ConnectionStore(context: Context) {
    private val prefs = context.getSharedPreferences("openstream.connections", Context.MODE_PRIVATE)

    // SharedPreferences stays the source of truth; these caches only avoid
    // re-parsing the same JSON on every read. Each is dropped on the matching
    // write so the next read re-decodes the canonical stored form. Access is
    // predominantly main-thread (Compose effects); @Volatile covers the rare
    // off-main read.
    @Volatile private var nasCache: List<NasConnection>? = null
    @Volatile private var stremioCache: List<StremioAddon>? = null
    @Volatile private var youtubeCache: List<YoutubeChannelSource>? = null

    fun nasConnections(): List<NasConnection> = nasCache ?: run {
        val raw = prefs.getString(KEY_NAS, "[]") ?: "[]"
        val parsed = try {
            val array = JSONArray(raw)
            (0 until array.length()).map { index ->
                val json = array.getJSONObject(index)
                NasConnection(
                    id = json.getString("id"),
                    name = json.getString("name"),
                    host = json.getString("host"),
                    share = json.getString("share"),
                    username = json.optString("username"),
                    password = json.optString("password"),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
        nasCache = parsed
        parsed
    }

    fun addNas(name: String, host: String, share: String, username: String, password: String): NasConnection {
        val connection = NasConnection(UUID.randomUUID().toString(), name.ifBlank { share }, host, share, username, password)
        writeNas(nasConnections() + connection)
        return connection
    }

    fun removeNas(id: String) {
        writeNas(nasConnections().filter { it.id != id })
    }

    private fun writeNas(entries: List<NasConnection>) {
        prefs.edit().putString(KEY_NAS, encodeNas(entries)).apply()
        nasCache = null
    }

    private fun encodeNas(entries: List<NasConnection>): String = JSONArray().apply {
        entries.forEach { entry ->
            put(
                JSONObject()
                    .put("id", entry.id)
                    .put("name", entry.name)
                    .put("host", entry.host)
                    .put("share", entry.share)
                    .put("username", entry.username)
                    .put("password", entry.password),
            )
        }
    }.toString()

    fun stremioAddons(): List<StremioAddon> {
        val custom = stremioCache ?: run {
            val raw = prefs.getString(KEY_STREMIO, "[]") ?: "[]"
            val parsed = try {
                val array = JSONArray(raw)
                (0 until array.length()).map { index ->
                    val json = array.getJSONObject(index)
                val resources = json.optJSONArray("resources")?.let { values ->
                    (0 until values.length()).mapNotNull { values.optString(it).takeIf(String::isNotBlank) }.toSet()
                }.orEmpty().ifEmpty { setOf("stream") }
                val catalogs = json.optJSONArray("catalogs")?.let { values ->
                    (0 until values.length()).mapNotNull { catalogIndex ->
                        val catalog = values.optJSONObject(catalogIndex) ?: return@mapNotNull null
                        val type = catalog.optString("type")
                        val id = catalog.optString("id")
                        if (type.isBlank() || id.isBlank() || !StremioMediaTypePolicy.isSupported(type)) {
                            return@mapNotNull null
                        }
                        StremioCatalog(
                            type = type,
                            id = id,
                            name = catalog.optString("name", id),
                            requiresInput = catalog.optBoolean("requiresInput"),
                            supportsSearch = catalog.optBoolean("supportsSearch"),
                        )
                    }
                }.orEmpty()
                StremioAddon(
                    id = json.getString("id"),
                    name = json.getString("name"),
                    transportUrl = json.getString("transportUrl"),
                    version = json.optString("version"),
                    manifestId = json.optString("manifestId", json.getString("id")),
                    resources = resources,
                    catalogs = catalogs,
                )
            }
            } catch (_: Exception) {
                emptyList()
            }
            stremioCache = parsed
            parsed
        }
        // The stored JSON never carries the enabled flag; it is derived from the
        // separate disabled set on every read, so this overlay is recomputed
        // even when `custom` is served from cache.
        val disabled = prefs.getStringSet(KEY_STREMIO_DISABLED, emptySet()).orEmpty()
        return StremioAddonRemovalPolicy.visible(custom)
            .map { addon -> addon.copy(enabled = addon.id !in disabled) }
    }

    fun addStremio(addon: StremioAddon) {
        writeStremio(stremioAddons().filter { it.manifestId != addon.manifestId } + addon)
    }

    fun removeStremio(id: String) {
        writeStremio(stremioAddons().filter { it.id != id })
    }

    private fun writeStremio(entries: List<StremioAddon>) {
        prefs.edit().putString(KEY_STREMIO, encodeStremio(entries)).apply()
        stremioCache = null
    }

    private fun encodeStremio(entries: List<StremioAddon>): String = JSONArray().apply {
        entries.forEach { entry ->
            put(
                JSONObject()
                    .put("id", entry.id)
                    .put("name", entry.name)
                    .put("transportUrl", entry.transportUrl)
                    .put("version", entry.version)
                    .put("manifestId", entry.manifestId)
                    .put("resources", JSONArray(entry.resources.toList()))
                    .put(
                        "catalogs",
                        JSONArray().apply {
                            entry.catalogs.forEach { catalog ->
                                put(
                                    JSONObject()
                                        .put("type", catalog.type)
                                        .put("id", catalog.id)
                                        .put("name", catalog.name)
                                        .put("requiresInput", catalog.requiresInput)
                                        .put("supportsSearch", catalog.supportsSearch),
                                )
                            }
                        },
                    ),
            )
        }
    }.toString()

    fun setStremioEnabled(id: String, enabled: Boolean) {
        val disabled = prefs.getStringSet(KEY_STREMIO_DISABLED, emptySet()).orEmpty().toMutableSet()
        if (enabled) disabled.remove(id) else disabled.add(id)
        prefs.edit().putStringSet(KEY_STREMIO_DISABLED, disabled).apply()
    }

    fun youtubeChannels(): List<YoutubeChannelSource> = youtubeCache
        ?: YoutubeChannelSourceCodec.decode(prefs.getString(KEY_YOUTUBE_CHANNELS, "[]") ?: "[]")
            .also { youtubeCache = it }

    fun addYoutubeChannel(channel: YoutubeChannelSource) {
        val current = youtubeChannels()
        val existing = current.firstOrNull { it.channelId == channel.channelId }
        val saved = if (existing == null) channel else channel.copy(id = existing.id, enabled = existing.enabled)
        val updated = current.filterNot { it.channelId == channel.channelId } + saved
        writeYoutubeChannels(updated)
    }

    fun removeYoutubeChannel(id: String) {
        writeYoutubeChannels(youtubeChannels().filterNot { it.id == id })
    }

    private fun writeYoutubeChannels(entries: List<YoutubeChannelSource>) {
        prefs.edit().putString(KEY_YOUTUBE_CHANNELS, YoutubeChannelSourceCodec.encode(entries)).apply()
        youtubeCache = null
    }

    fun setYoutubeChannelEnabled(id: String, enabled: Boolean) {
        val updated = youtubeChannels().map { source ->
            if (source.id == id) source.copy(enabled = enabled) else source
        }
        writeYoutubeChannels(updated)
    }

    fun discoverFeedPreferences(): DiscoverFeedPreferences = DiscoverFeedPreferencesCodec.decode(
        prefs.getString(KEY_DISCOVER_FEED, "") ?: "",
    )

    fun saveDiscoverFeedPreferences(preferences: DiscoverFeedPreferences) {
        prefs.edit().putString(KEY_DISCOVER_FEED, DiscoverFeedPreferencesCodec.encode(preferences)).apply()
    }

    companion object {
        private const val KEY_NAS = "nas.v1"
        private const val KEY_STREMIO = "stremio.v1"
        private const val KEY_STREMIO_DISABLED = "stremio.disabled.v1"
        private const val KEY_YOUTUBE_CHANNELS = "youtube.channels.v1"
        private const val KEY_DISCOVER_FEED = "discover.feed.v1"
    }
}
