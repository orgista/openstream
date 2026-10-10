package com.orgista.openstream.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalMediaPolicyTest {
    @Test
    fun `accepts local video and audio files only`() {
        assertTrue(LocalMediaPolicy.accepts("content", "video/mp4"))
        assertTrue(LocalMediaPolicy.accepts("content", "audio/mpeg"))
        assertTrue(LocalMediaPolicy.accepts("file", "video/x-matroska"))
        assertTrue(LocalMediaPolicy.accepts("content", null))
        assertFalse(LocalMediaPolicy.accepts("content", "image/png"))
        assertFalse(LocalMediaPolicy.accepts("content", "application/pdf"))
        assertFalse(LocalMediaPolicy.accepts("https", "video/mp4"))
        assertFalse(LocalMediaPolicy.accepts(null, "video/mp4"))
    }

    @Test
    fun `local files play directly with their own resume key`() {
        val uri = "content://com.android.providers.media.documents/document/video%3A42"
        val request = LocalMediaPolicy.request(LocalMedia(uri, "Big Sky.mp4"))
        assertEquals("Big Sky.mp4", request.title)
        assertEquals(uri, request.uri)
        assertEquals("local:$uri", request.mediaId)
        assertFalse(request.isLive)
        // Not a network route: the player falls back to the URI itself.
        assertTrue(playableUris(request).isEmpty())
    }
}
