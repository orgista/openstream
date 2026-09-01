package com.orgista.openstream.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StremioAddonPresentationTest {
    @Test
    fun `capabilities explain where each addon is used`() {
        assertEquals(
            "Adds rows to Discover · Adds title details · Finds playback streams · Adds captions during playback",
            StremioAddonPresentation.usage(setOf("catalog", "meta", "stream", "subtitles")),
        )
        assertEquals("Adds captions during playback", StremioAddonPresentation.usage(setOf("subtitles")))
        assertEquals("Finds playback streams", StremioAddonPresentation.usage(setOf("stream")))
        assertEquals(
            "Adds recommendations to Discover",
            StremioAddonPresentation.usage(
                StremioAddon(
                    id = "watch-next",
                    manifestId = "community.watch.next",
                    name = "Watch Next",
                    transportUrl = "https://watch-next.example",
                    version = "1.0.0",
                    resources = setOf("stream"),
                ),
            ),
        )
    }

    @Test
    fun `only enabled direct stream providers advertise playback availability`() {
        val direct = StremioAddon(
            id = "torrentio",
            manifestId = "com.stremio.torrentio.addon",
            name = "Torrentio",
            transportUrl = "https://stream.example",
            version = "1.0.0",
            resources = setOf("stream"),
        )
        val recommendation = direct.copy(
            id = "watch-next",
            manifestId = "community.watch.next",
            name = "Watch Next",
        )

        assertTrue(StremioAddonPresentation.isPlaybackProvider(direct))
        assertFalse(StremioAddonPresentation.isPlaybackProvider(direct.copy(enabled = false)))
        assertFalse(StremioAddonPresentation.isPlaybackProvider(direct.copy(resources = setOf("subtitles"))))
        assertFalse(StremioAddonPresentation.isPlaybackProvider(recommendation))
    }
}
