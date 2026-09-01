package com.orgista.openstream.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LaunchPresentationPolicyTest {
    @Test
    fun `motion launch follows the tightened two and a half second scene timing`() {
        assertEquals(450, LaunchPresentationPolicy.signalMillis)
        assertEquals(650, LaunchPresentationPolicy.confluenceMillis)
        assertEquals(550, LaunchPresentationPolicy.lockupMillis)
        assertEquals(850, LaunchPresentationPolicy.discoverMillis)
        assertEquals(2_500L, LaunchPresentationPolicy.durationMillis(animatorsEnabled = true))
    }

    @Test
    fun `reduced motion avoids the five second flourish`() {
        assertEquals(220L, LaunchPresentationPolicy.durationMillis(animatorsEnabled = false))
    }

    @Test
    fun `scene progress is clamped and discover begins after lockup`() {
        assertEquals(1_650, LaunchPresentationPolicy.discoverStartMillis)
        assertEquals(0f, LaunchPresentationPolicy.progress(1_649, 1_650, 800))
        assertEquals(0.5f, LaunchPresentationPolicy.progress(2_050, 1_650, 800))
        assertEquals(1f, LaunchPresentationPolicy.progress(2_450, 1_650, 800))
    }

    @Test
    fun `brand geometry preserves the supplied stream proportions`() {
        assertEquals(96f, OpenStreamBrandGeometry.viewBox)
        assertEquals(22f, OpenStreamBrandGeometry.startX)
        assertEquals(12.5f, OpenStreamBrandGeometry.strokeWidth)
        assertEquals(listOf(31f, 48.5f, 66f), OpenStreamBrandGeometry.bars.map { it.y })
        assertEquals(listOf(40f, 56f, 40f), OpenStreamBrandGeometry.bars.map { it.length })
    }

    @Test
    fun `launch bars keep a restrained crisp halo`() {
        assertEquals(0.04f, LaunchBarEffectPolicy.haloAlpha(bloom = 0f), 0.001f)
        assertEquals(0.09f, LaunchBarEffectPolicy.haloAlpha(bloom = 1f), 0.001f)
        assertEquals(1.12f, LaunchBarEffectPolicy.haloStrokeMultiplier(bloom = 0f), 0.001f)
        assertEquals(1.28f, LaunchBarEffectPolicy.haloStrokeMultiplier(bloom = 1f), 0.001f)
        assertEquals(0.07f, LaunchBarEffectPolicy.ambientAlpha(reveal = 0f), 0.001f)
        assertEquals(0f, LaunchBarEffectPolicy.ambientAlpha(reveal = 1f), 0.001f)
        assertEquals(0.24f, LaunchBarEffectPolicy.ambientRadiusFraction, 0.001f)
    }

    @Test
    fun `launch handoff lands on the resident top bar brand metrics`() {
        // Compact: 16dp start, 7dp bar padding + 7dp brand row padding, 24dp mark.
        assertEquals(16, TopNavLayoutPolicy.brandStartPaddingDp(compact = true))
        assertEquals(14, TopNavLayoutPolicy.brandTopOffsetDp(compact = true))
        assertEquals(24, TopNavLayoutPolicy.brandMarkSizeDp(compact = true))
        assertEquals(4, TopNavLayoutPolicy.brandGapDp(compact = true))
        assertEquals(17, TopNavLayoutPolicy.brandWordSp(compact = true))
        // Regular: 26dp start, 10dp bar padding + 7dp brand row padding, 27dp mark.
        assertEquals(26, TopNavLayoutPolicy.brandStartPaddingDp(compact = false))
        assertEquals(17, TopNavLayoutPolicy.brandTopOffsetDp(compact = false))
        assertEquals(27, TopNavLayoutPolicy.brandMarkSizeDp(compact = false))
        assertEquals(5, TopNavLayoutPolicy.brandGapDp(compact = false))
        assertEquals(18, TopNavLayoutPolicy.brandWordSp(compact = false))
    }

    @Test
    fun `launcher mark sits on the Material square keyline inside the safe circle`() {
        assertEquals(23f, LauncherIconPresentationPolicy.foregroundInsetDp)
        val width = LauncherIconPresentationPolicy.renderedMarkWidthDp()
        val height = LauncherIconPresentationPolicy.renderedMarkHeightDp()
        // Within a dp of the 44dp square keyline: readable, not edge-to-edge.
        assertTrue(width >= 40f)
        assertTrue(width <= LauncherIconPresentationPolicy.squareKeylineDp + 1f)
        assertTrue(height >= 28f)
        // Every corner inside the 66dp adaptive-icon safe circle.
        val cornerRadius = kotlin.math.sqrt(
            (width / 2f) * (width / 2f) + (height / 2f) * (height / 2f),
        )
        assertTrue(cornerRadius <= LauncherIconPresentationPolicy.safeZoneDiameterDp / 2f)
    }
}
