package com.orgista.openstream.arr

import com.orgista.openstream.data.MediaItem
import com.orgista.openstream.domain.normalizedRatingAge
import org.json.JSONArray

/**
 * Local ratings from the owner's own servers: Radarr and Sonarr store an
 * MPAA/TV certification for every title they manage, so one bulk request per
 * configured server yields a title → certification map. Library items that
 * metadata matching left unrated pick up their certification here, which is
 * what lets owned files pass the Kids Mode filter instead of being blocked as
 * unrated.
 */
object ArrCertifications {
    fun fetch(connection: ArrConnection): Map<String, String> {
        val path = when (connection.kind) {
            ArrKind.RADARR -> "/api/v3/movie"
            ArrKind.SONARR -> "/api/v3/series"
        }
        val array = JSONArray(ArrClient.request(connection, "GET", path))
        val certifications = HashMap<String, String>()
        for (index in 0 until array.length()) {
            val entry = array.optJSONObject(index) ?: continue
            val certification = entry.optString("certification").trim()
            if (certification.isEmpty()) continue
            val title = normalizeTitle(entry.optString("title"))
            if (title.isNotEmpty()) certifications[title] = certification
        }
        return certifications
    }

    fun normalizeTitle(title: String): String = title.lowercase()
        .replace(Regex("\\(\\d{4}\\)"), " ")
        .replace(Regex("[^a-z0-9]+"), " ")
        .trim()

    /**
     * Applies an ARR audience certification when the current value is not an
     * audience certification. TMDB search results can temporarily put a vote
     * score such as "★ 7.1" in [MediaItem.rating]; preserving that value would
     * make an owned title look unrated to Kids Mode even when Radarr/Sonarr has
     * its real PG/TV-PG label.
     */
    fun applyTo(items: List<MediaItem>, certifications: Map<String, String>): List<MediaItem> {
        if (certifications.isEmpty()) return items
        return items.map { item ->
            if (normalizedRatingAge(item.rating) != null) {
                item
            } else {
                certifications[normalizeTitle(item.title)]?.let { item.copy(rating = it) } ?: item
            }
        }
    }
}
