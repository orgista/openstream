package com.orgista.openstream.library

import com.orgista.openstream.data.MediaItem

/** Selects a small high-value metadata working set instead of refetching every catalog row. */
object MetadataPrefetchPolicy {
    private val likelyKidsGenres = setOf("animation", "family", "kids", "children", "preschool")

    fun select(items: List<MediaItem>, limit: Int = 24, prioritizeKids: Boolean = false): List<MediaItem> {
        val sparse = items
            .distinctBy { it.imdbId ?: it.id }
            .filter(::metadataMissing)
        val ordered = if (prioritizeKids) {
            sparse.sortedByDescending { item ->
                item.genres.count { it.trim().lowercase() in likelyKidsGenres }
            }
        } else {
            sparse
        }
        return ordered.take(limit.coerceAtLeast(0))
    }

    private fun metadataMissing(item: MediaItem): Boolean =
        item.synopsis.isBlank() || item.posterUrl == null || item.backdropUrl == null ||
            item.runtimeMinutes <= 0 || item.rating.isBlank() || item.genres.isEmpty()
}
