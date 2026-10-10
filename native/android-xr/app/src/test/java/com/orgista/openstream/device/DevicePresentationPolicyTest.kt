package com.orgista.openstream.device

import org.junit.Assert.assertEquals
import org.junit.Test

class DevicePresentationPolicyTest {
    @Test
    fun `phones use the system orientation so portrait is the natural default and rotation still works`() {
        assertEquals(
            OrientationPreference.SYSTEM,
            DevicePresentationPolicy.orientation(smallestWidthDp = 411, immersiveRuntime = false),
        )
    }

    @Test
    fun `tablets prefer user landscape`() {
        assertEquals(
            OrientationPreference.USER_LANDSCAPE,
            DevicePresentationPolicy.orientation(smallestWidthDp = 800, immersiveRuntime = false),
        )
    }

    @Test
    fun `headsets leave orientation to the spatial runtime`() {
        assertEquals(
            OrientationPreference.SYSTEM,
            DevicePresentationPolicy.orientation(smallestWidthDp = 900, immersiveRuntime = true),
        )
    }

    @Test
    fun `desktops and freeform windows never lock orientation`() {
        assertEquals(
            OrientationPreference.SYSTEM,
            DevicePresentationPolicy.orientation(smallestWidthDp = 1080, immersiveRuntime = false, desktopWindowing = true),
        )
    }
}
