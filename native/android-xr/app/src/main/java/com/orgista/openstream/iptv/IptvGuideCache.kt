package com.orgista.openstream.iptv

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

object IptvGuideRefreshPolicy {
    const val MAX_AGE_MILLIS = 6 * 60 * 60_000L
    const val EMPTY_RETRY_MILLIS = 60 * 60_000L

    fun isFresh(lastModifiedMillis: Long, nowMillis: Long, hasPrograms: Boolean): Boolean {
        val maxAgeMillis = if (hasPrograms) MAX_AGE_MILLIS else EMPTY_RETRY_MILLIS
        return lastModifiedMillis > 0L && nowMillis - lastModifiedMillis in 0..maxAgeMillis
    }
}

object IptvGuideCodec {
    // v3 invalidates guide caches that could merge two XMLTV aliases onto one
    // app channel and render overlapping schedules.
    private const val VERSION = 3
    private const val MAX_CACHE_CHARS = 8_000_000
    private const val MAX_PROGRAMS = 24_000

    fun encode(sourceId: String, programs: List<IptvGuideProgram>): String = JSONObject()
        .put("version", VERSION)
        .put("sourceId", sourceId)
        .put(
            "programs",
            JSONArray().apply {
                programs.take(MAX_PROGRAMS).forEach { program ->
                    put(
                        JSONObject()
                            .put("channelKey", program.channelKey)
                            .put("title", program.title)
                            .put("subtitle", program.subtitle)
                            .put("description", program.description)
                            .put("category", program.category)
                            .put("startMillis", program.startMillis)
                            .put("endMillis", program.endMillis),
                    )
                }
            },
        ).toString()

    fun decode(sourceId: String, raw: String, nowMillis: Long): List<IptvGuideProgram> {
        if (raw.length > MAX_CACHE_CHARS) return emptyList()
        val root = runCatching { JSONObject(raw) }.getOrNull() ?: return emptyList()
        if (root.optInt("version") != VERSION || root.optString("sourceId") != sourceId) return emptyList()
        val programs = root.optJSONArray("programs") ?: return emptyList()
        val earliest = nowMillis - 2 * LiveGuidePolicy.HALF_HOUR_MILLIS
        val latest = nowMillis + 96 * LiveGuidePolicy.HALF_HOUR_MILLIS
        return (0 until minOf(programs.length(), MAX_PROGRAMS)).mapNotNull { index ->
            val value = programs.optJSONObject(index) ?: return@mapNotNull null
            val start = value.optLong("startMillis", -1L)
            val end = value.optLong("endMillis", -1L)
            if (start < 0 || end <= start || end <= earliest || start >= latest) return@mapNotNull null
            IptvGuideProgram(
                channelKey = value.optString("channelKey").take(360).ifBlank { return@mapNotNull null },
                title = value.optString("title").take(300).ifBlank { return@mapNotNull null },
                subtitle = value.optString("subtitle").take(300),
                description = value.optString("description").take(1_500),
                category = value.optString("category").take(120),
                startMillis = start,
                endMillis = end,
            )
        }
    }
}

class IptvGuideCache(context: Context) {
    private val directory = context.applicationContext.cacheDir

    fun load(sourceId: String, nowMillis: Long): List<IptvGuideProgram> = runCatching {
        val sourceFile = file(sourceId)
        if (!sourceFile.isFile) emptyList() else IptvGuideCodec.decode(sourceId, sourceFile.readText(), nowMillis)
    }.getOrDefault(emptyList())

    fun save(sourceId: String, programs: List<IptvGuideProgram>) {
        if (programs.isEmpty()) return
        runCatching {
            val sourceFile = file(sourceId)
            val temporary = File(sourceFile.parentFile, "${sourceFile.name}.tmp")
            temporary.writeText(IptvGuideCodec.encode(sourceId, programs))
            if (!temporary.renameTo(sourceFile)) {
                sourceFile.writeText(temporary.readText())
                temporary.delete()
            }
        }
    }

    fun markRefreshAttempt(sourceId: String) {
        runCatching {
            val marker = attemptFile(sourceId)
            if (!marker.exists()) marker.writeText("") else marker.setLastModified(System.currentTimeMillis())
        }
    }

    fun isFresh(sourceId: String, nowMillis: Long, hasPrograms: Boolean): Boolean {
        val lastModifiedMillis = if (hasPrograms) file(sourceId).lastModified() else attemptFile(sourceId).lastModified()
        return IptvGuideRefreshPolicy.isFresh(lastModifiedMillis, nowMillis, hasPrograms)
    }

    fun remove(sourceId: String) {
        runCatching { file(sourceId).delete() }
        runCatching { attemptFile(sourceId).delete() }
    }

    private fun file(sourceId: String): File {
        val safeId = sourceId.lowercase().replace(Regex("[^a-z0-9-]"), "-").take(80)
        return File(directory, "iptv-guide-$safeId-v3.json")
    }

    private fun attemptFile(sourceId: String): File {
        val safeId = sourceId.lowercase().replace(Regex("[^a-z0-9-]"), "-").take(80)
        return File(directory, "iptv-guide-$safeId-v3.attempt")
    }
}
