package com.orgista.openstream.offline

import android.content.Context
import com.orgista.openstream.Logs
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * App-private cache for exact media probes. Keys are route hashes, not raw
 * NAS/SMB paths, so library folder names and filenames are not duplicated in
 * plaintext outside the normal library cache.
 */
class OfflineMediaProbeCache(context: Context) {
    private val cacheFile = File(context.applicationContext.filesDir, "media-probe-cache.json")
    private val lock = Any()
    @Volatile private var entries: MutableMap<String, OfflineMediaProbe>? = null

    fun get(uri: String): OfflineMediaProbe? = synchronized(lock) {
        loadLocked()[key(uri)]
    }

    fun put(uri: String, probe: OfflineMediaProbe) = synchronized(lock) {
        val loaded = loadLocked()
        loaded[key(uri)] = probe
        saveLocked(loaded)
    }

    fun remove(uri: String) = synchronized(lock) {
        val loaded = loadLocked()
        if (loaded.remove(key(uri)) != null) saveLocked(loaded)
    }

    fun clear() = synchronized(lock) {
        entries = mutableMapOf()
        runCatching { cacheFile.delete() }
    }

    fun estimatedBytes(): Long = runCatching { cacheFile.length() }.getOrDefault(0L)

    private fun loadLocked(): MutableMap<String, OfflineMediaProbe> {
        entries?.let { return it }
        val loaded = mutableMapOf<String, OfflineMediaProbe>()
        if (!cacheFile.exists()) {
            entries = loaded
            return loaded
        }
        runCatching {
            val root = JSONObject(cacheFile.readText())
            val values = root.optJSONObject("entries") ?: JSONObject()
            values.keys().forEach { key ->
                values.optJSONObject(key)?.decodeProbe()?.let { loaded[key] = it }
            }
        }.onFailure { error ->
            Logs.warn("media probe cache load failed", error)
        }
        entries = loaded
        return loaded
    }

    private fun saveLocked(values: Map<String, OfflineMediaProbe>) {
        runCatching {
            val json = JSONObject()
            val encoded = JSONObject()
            values.forEach { (key, probe) -> encoded.put(key, probe.encode()) }
            json.put("version", 1)
            json.put("entries", encoded)
            cacheFile.writeText(json.toString())
        }.onFailure { error ->
            Logs.warn("media probe cache save failed", error)
        }
    }

    private fun OfflineMediaProbe.encode(): JSONObject = JSONObject()
        .putOpt("videoMimeType", videoMimeType)
        .putOpt("videoCodecString", videoCodecString)
        .put("videoCodec", videoCodec.name)
        .putOpt("videoProfile", videoProfile)
        .putOpt("width", width)
        .putOpt("height", height)
        .putOpt("frameRate", frameRate)
        .putOpt("bitrate", bitrate)
        .putOpt("bitDepth", bitDepth)
        .putOpt("dynamicRange", dynamicRange?.name)
        .putOpt("dolbyVisionProfile", dolbyVisionProfile)
        .putOpt("audioMimeType", audioMimeType)
        .putOpt("audioCodecString", audioCodecString)
        .putOpt("audioChannels", audioChannels)
        .putOpt("audioBitrate", audioBitrate)
        .put("dolbyAtmos", dolbyAtmos)
        .putOpt("durationMs", durationMs)
        .putOpt("sizeBytes", sizeBytes)
        .putOpt("hardwareDecodeSupported", hardwareDecodeSupported)
        .put("probedAtEpochMillis", probedAtEpochMillis)

    private fun JSONObject.decodeProbe(): OfflineMediaProbe? = runCatching {
        OfflineMediaProbe(
            videoMimeType = optString("videoMimeType").takeIf(String::isNotBlank),
            videoCodecString = optString("videoCodecString").takeIf(String::isNotBlank),
            videoCodec = runCatching {
                OfflineVideoCodec.valueOf(optString("videoCodec"))
            }.getOrDefault(OfflineVideoCodec.UNKNOWN),
            videoProfile = optString("videoProfile").takeIf(String::isNotBlank),
            width = optNullableInt("width"),
            height = optNullableInt("height"),
            frameRate = optNullableDouble("frameRate")?.toFloat(),
            bitrate = optNullableInt("bitrate"),
            bitDepth = optNullableInt("bitDepth"),
            dynamicRange = optString("dynamicRange").takeIf(String::isNotBlank)?.let {
                runCatching { OfflineDynamicRange.valueOf(it) }.getOrNull()
            },
            dolbyVisionProfile = optNullableInt("dolbyVisionProfile"),
            audioMimeType = optString("audioMimeType").takeIf(String::isNotBlank),
            audioCodecString = optString("audioCodecString").takeIf(String::isNotBlank),
            audioChannels = optNullableInt("audioChannels"),
            audioBitrate = optNullableInt("audioBitrate"),
            dolbyAtmos = optBoolean("dolbyAtmos", false),
            durationMs = optNullableLong("durationMs"),
            sizeBytes = optNullableLong("sizeBytes"),
            hardwareDecodeSupported = optNullableBoolean("hardwareDecodeSupported"),
            probedAtEpochMillis = optLong("probedAtEpochMillis", System.currentTimeMillis()),
        )
    }.getOrNull()

    private fun JSONObject.optNullableInt(name: String): Int? =
        if (has(name) && !isNull(name)) optInt(name).takeIf { it > 0 } else null

    private fun JSONObject.optNullableLong(name: String): Long? =
        if (has(name) && !isNull(name)) optLong(name).takeIf { it > 0L } else null

    private fun JSONObject.optNullableDouble(name: String): Double? =
        if (has(name) && !isNull(name)) optDouble(name).takeIf { it > 0.0 } else null

    private fun JSONObject.optNullableBoolean(name: String): Boolean? =
        if (has(name) && !isNull(name)) optBoolean(name) else null

    companion object {
        fun key(uri: String): String = MessageDigest.getInstance("SHA-256")
            .digest(uri.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }
}
