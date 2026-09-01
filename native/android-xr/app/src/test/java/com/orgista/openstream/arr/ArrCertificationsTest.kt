package com.orgista.openstream.arr

import com.orgista.openstream.data.MediaItem
import com.orgista.openstream.data.MediaKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ArrCertificationsTest {
    private fun item(title: String, rating: String = "") = MediaItem(
        id = title.lowercase(),
        kind = MediaKind.MOVIE,
        title = title,
        synopsis = "",
        year = 2020,
        rating = rating,
        runtimeMinutes = 90,
    )

    @Test
    fun `titles normalize case punctuation and release years`() {
        assertEquals("paddington 2", ArrCertifications.normalizeTitle("Paddington 2"))
        assertEquals("paddington 2", ArrCertifications.normalizeTitle("PADDINGTON 2 (2017)"))
        assertEquals("e t the extra terrestrial", ArrCertifications.normalizeTitle("E.T. the Extra-Terrestrial"))
    }

    @Test
    fun `blank ratings fill from the certification map`() {
        val certifications = mapOf("paddington 2" to "PG", "up" to "G")
        val rated = ArrCertifications.applyTo(
            listOf(item("Paddington 2"), item("Up"), item("Unknown Film")),
            certifications,
        )
        assertEquals(listOf("PG", "G", ""), rated.map { it.rating })
    }

    @Test
    fun `an existing audience certification is never overridden`() {
        val certifications = mapOf("up" to "PG-13")
        val rated = ArrCertifications.applyTo(listOf(item("Up", rating = "G")), certifications)
        assertEquals("G", rated.single().rating)
    }

    @Test
    fun `a popularity score is replaced by the audience certification`() {
        val certifications = mapOf("paddington 2" to "PG")
        val rated = ArrCertifications.applyTo(
            listOf(item("Paddington 2", rating = "★ 7.8")),
            certifications,
        )
        assertEquals("PG", rated.single().rating)
    }

    @Test
    fun `an empty map returns the same items`() {
        val items = listOf(item("Up"))
        assertEquals(items, ArrCertifications.applyTo(items, emptyMap()))
    }

    @Test
    fun `arr catalog responses allow a full movie library`() {
        assertTrue(
            ArrClient.responseLimitBytes("/api/v3/movie") >
                ArrClient.responseLimitBytes("/api/v3/system/status"),
        )
        assertTrue(ArrClient.responseLimitBytes("/api/v3/movie") >= 4 * 1024 * 1024)
        assertEquals(
            ArrClient.responseLimitBytes("/api/v3/movie"),
            ArrClient.responseLimitBytes("/api/v3/series"),
        )
    }
}
