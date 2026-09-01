package com.orgista.openstream.ui

import com.orgista.openstream.data.MediaKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TopNavModelTest {
    @Test
    fun `phone widths use the compact two row navigation`() {
        assertTrue(TopNavLayoutPolicy.isCompact(widthDp = 384, heightDp = 640))
        assertTrue(TopNavLayoutPolicy.isCompact(widthDp = 640, heightDp = 384))
        assertFalse(TopNavLayoutPolicy.isCompact(widthDp = 1280, heightDp = 800))
    }

    @Test
    fun `wide brand receives baseline compensation beside navigation tabs`() {
        assertEquals(7, TopNavLayoutPolicy.brandBottomPaddingDp(compact = false))
        assertEquals(0, TopNavLayoutPolicy.brandBottomPaddingDp(compact = true))
    }

    @Test
    fun `app chrome omits duplicate system connectivity telemetry`() {
        assertFalse(TopNavLayoutPolicy.showConnectivityTelemetry)
        assertEquals("Offline", TopNavLayoutPolicy.offlineStatusLabel)
        assertEquals(TopDestination.DISCOVER, TopNavLayoutPolicy.brandDestination)
    }

    @Test
    fun `content begins below controls but underneath the navigation fade`() {
        assertEquals(72, TopNavBlendPolicy.contentTopInsetPx(navHeightPx = 100, fadeOverlapPx = 28))
        assertEquals(0, TopNavBlendPolicy.contentTopInsetPx(navHeightPx = 20, fadeOverlapPx = 28))
    }

    @Test
    fun `primary navigation stays focused on browsing`() {
        assertEquals(
            listOf(TopDestination.DISCOVER, TopDestination.LIBRARY, TopDestination.LIVE),
            primaryTopDestinations(),
        )
    }

    @Test
    fun `overflow exposes sources and settings outside kids mode`() {
        assertEquals(
            listOf(TopDestination.SOURCES, TopDestination.SETTINGS),
            overflowTopDestinations(kidsMode = false),
        )
        assertEquals(
            listOf(TopDestination.SETTINGS),
            overflowTopDestinations(kidsMode = true),
        )
    }

    @Test
    fun `library status prioritizes active scan and explains missing artwork setup`() {
        assertEquals(
            "Scanning library…",
            libraryHeaderStatus(indexing = true, hasLibraries = true, titleCount = 389, metadataEnabled = false),
        )
        assertEquals(
            "389 titles · artwork needs TMDB",
            libraryHeaderStatus(indexing = false, hasLibraries = true, titleCount = 389, metadataEnabled = false),
        )
        assertEquals(
            "389 titles",
            libraryHeaderStatus(indexing = false, hasLibraries = true, titleCount = 389, metadataEnabled = true),
        )
        assertEquals(
            "Add a source",
            libraryHeaderStatus(indexing = false, hasLibraries = false, titleCount = 0, metadataEnabled = false),
        )
    }

    @Test
    fun `library empty states stay terse and specific`() {
        assertEquals("No titles", libraryEmptyTitle(hasCatalog = false, filter = null, missingSources = 0))
        assertEquals("Source unavailable", libraryEmptyTitle(hasCatalog = false, filter = null, missingSources = 1))
        assertEquals("Sources unavailable", libraryEmptyTitle(hasCatalog = false, filter = null, missingSources = 2))
        assertEquals("No movies", libraryEmptyTitle(hasCatalog = true, filter = MediaKind.MOVIE, missingSources = 0))
        assertEquals("No series", libraryEmptyTitle(hasCatalog = true, filter = MediaKind.SERIES, missingSources = 0))
    }

    @Test
    fun `a configured library that indexes nothing names the missing share instead of reading empty`() {
        assertEquals(
            "Reconnect the NAS share in Settings → Sources",
            libraryHeaderStatus(
                indexing = false,
                hasLibraries = true,
                titleCount = 0,
                metadataEnabled = true,
                missingSources = 1,
            ),
        )
        assertEquals(
            "Reconnect 2 NAS shares in Settings → Sources",
            libraryHeaderStatus(
                indexing = false,
                hasLibraries = true,
                titleCount = 0,
                metadataEnabled = true,
                missingSources = 2,
            ),
        )
        // A partially indexed library still reports its count first.
        assertEquals(
            "120 titles · 1 source needs reconnecting",
            libraryHeaderStatus(
                indexing = false,
                hasLibraries = true,
                titleCount = 120,
                metadataEnabled = true,
                missingSources = 1,
            ),
        )
        // An active scan still wins, and a healthy library is unchanged.
        assertEquals(
            "Scanning library…",
            libraryHeaderStatus(
                indexing = true,
                hasLibraries = true,
                titleCount = 0,
                metadataEnabled = true,
                missingSources = 1,
            ),
        )
        assertEquals(
            "389 titles",
            libraryHeaderStatus(
                indexing = false,
                hasLibraries = true,
                titleCount = 389,
                metadataEnabled = true,
                missingSources = 0,
            ),
        )
    }
}
