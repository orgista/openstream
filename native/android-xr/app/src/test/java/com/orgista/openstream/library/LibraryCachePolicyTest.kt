package com.orgista.openstream.library

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LibraryCachePolicyTest {
    @Test
    fun `a valid startup cache avoids a duplicate NAS scan`() {
        assertFalse(LibraryCache.shouldScanAfterStartup(cacheAvailable = true, libraryRevision = 0))
    }

    @Test
    fun `missing cache or an explicit library change requests a scan`() {
        assertTrue(LibraryCache.shouldScanAfterStartup(cacheAvailable = false, libraryRevision = 0))
        assertTrue(LibraryCache.shouldScanAfterStartup(cacheAvailable = true, libraryRevision = 1))
    }
}
