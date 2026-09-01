package com.orgista.openstream.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class LiveTvEmptyStatePolicyTest {
    @Test
    fun `empty lineup uses a terse state`() {
        val message = LiveTvEmptyStatePolicy.message(online = true)

        assertEquals("No channels", message)
        assertFalse(message.contains("could not load", ignoreCase = true))
        assertFalse(message.contains("No channels are enabled", ignoreCase = true))
    }

    @Test
    fun `offline state does not repeat an explanation`() {
        assertEquals("No channels", LiveTvEmptyStatePolicy.message(online = false))
    }

    @Test
    fun `provider failure is not presented as an unconfigured lineup`() {
        assertEquals(
            "Channels unavailable",
            LiveTvEmptyStatePolicy.message(
                online = true,
                sourceLoadFailed = true,
            ),
        )
    }
}
