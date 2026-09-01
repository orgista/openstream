package com.orgista.openstream.library

import com.orgista.openstream.data.MediaItem
import com.orgista.openstream.data.MediaKind
import org.junit.Assert.assertEquals
import org.junit.Test

class MetadataPrefetchPolicyTest {
    private fun item(id: String, complete: Boolean = false, genres: List<String> = emptyList()) = MediaItem(
        id = id,
        kind = MediaKind.MOVIE,
        title = id,
        synopsis = if (complete) "A complete overview" else "",
        year = 2025,
        rating = if (complete) "PG-13" else "",
        runtimeMinutes = if (complete) 120 else 0,
        posterUrl = if (complete) "https://image.example/$id.jpg" else null,
        backdropUrl = if (complete) "https://image.example/$id-wide.jpg" else null,
        imdbId = "tt000000$id",
        genres = if (complete) listOf("Drama") else genres,
    )

    @Test
    fun `prefetch prioritizes sparse titles and respects limit`() {
        val selected = MetadataPrefetchPolicy.select(
            listOf(item("1", complete = true), item("2"), item("3"), item("4", complete = true)),
            limit = 2,
        )

        assertEquals(listOf("2", "3"), selected.map { it.id })
    }

    @Test
    fun `kids prefetch checks likely family titles before general catalog titles`() {
        val selected = MetadataPrefetchPolicy.select(
            listOf(
                item("drama", genres = listOf("Drama")),
                item("family", genres = listOf("Family")),
                item("animation", genres = listOf("Animation", "Adventure")),
                item("thriller", genres = listOf("Thriller")),
            ),
            limit = 3,
            prioritizeKids = true,
        )

        assertEquals(listOf("family", "animation", "drama"), selected.map { it.id })
    }
}
