package com.orgista.openstream.library

import com.orgista.openstream.data.MediaItem
import com.orgista.openstream.data.MediaKind
import com.orgista.openstream.data.TitleRatings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MetadataMergePolicyTest {
    private val existing = MediaItem(
        id = "tt1234567",
        kind = MediaKind.MOVIE,
        title = "Existing Film",
        synopsis = "Existing synopsis",
        year = 2025,
        rating = "PG-13",
        runtimeMinutes = 121,
        imdbId = "tt1234567",
        genres = listOf("Drama"),
        cast = listOf("Existing Actor"),
        director = "Existing Director",
        tagline = "Existing tagline",
        ratings = TitleRatings(imdb = "8.0/10"),
    )

    @Test
    fun `failed providers preserve existing metadata`() {
        assertEquals(existing, MetadataMergePolicy.merge(existing, null, null, null))
    }

    @Test
    fun `new provider fields augment instead of erasing existing values`() {
        val result = MetadataMergePolicy.merge(
            existing,
            tmdbId = 42,
            details = TmdbDetails(
                imdbId = "tt1234567",
                runtimeMinutes = 0,
                genres = emptyList(),
                cast = listOf("New Actor"),
                director = null,
                tagline = null,
                certification = null,
            ),
            omdb = OmdbResult(
                ratings = TitleRatings(rottenTomatoes = "95%"),
                rated = null,
                director = null,
                actors = emptyList(),
                genres = emptyList(),
                runtimeMinutes = 0,
            ),
        )

        assertEquals(42, result.tmdbId)
        assertEquals(listOf("Drama"), result.genres)
        assertEquals(listOf("Existing Actor", "New Actor"), result.cast)
        assertEquals("Existing Director", result.director)
        assertEquals("8.0/10", result.ratings?.imdb)
        assertEquals("95%", result.ratings?.rottenTomatoes)
    }

    @Test
    fun `tmdb details fill missing artwork overview and release year`() {
        val sparse = existing.copy(
            synopsis = "",
            year = 0,
            posterUrl = null,
            backdropUrl = null,
        )

        val result = MetadataMergePolicy.merge(
            sparse,
            tmdbId = 99,
            details = TmdbDetails(
                imdbId = "tt1234567",
                runtimeMinutes = 121,
                genres = listOf("Drama"),
                cast = emptyList(),
                director = null,
                tagline = null,
                certification = "PG-13",
                overview = "Metadata overview",
                releaseYear = 2025,
                posterPath = "/poster.jpg",
                backdropPath = "/backdrop.jpg",
            ),
            omdb = null,
        )

        assertEquals("Metadata overview", result.synopsis)
        assertEquals(2025, result.year)
        assertTrue(result.posterUrl!!.endsWith("/poster.jpg"))
        assertTrue(result.backdropUrl!!.endsWith("/backdrop.jpg"))
    }

    @Test
    fun `audience certification replaces a search popularity score`() {
        val result = MetadataMergePolicy.merge(
            existing.copy(rating = "★ 7.1"),
            tmdbId = 42,
            details = TmdbDetails(
                imdbId = "tt1234567",
                runtimeMinutes = 121,
                genres = emptyList(),
                cast = emptyList(),
                director = null,
                tagline = null,
                certification = "PG",
            ),
            omdb = null,
        )

        assertEquals("PG", result.rating)
    }
}
