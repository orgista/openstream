package com.orgista.openstream.device

enum class OrientationPreference {
    SYSTEM,
    USER_LANDSCAPE,
}

/**
 * Keeps phones naturally portrait-first, tablets landscape-first, and XR under
 * runtime control. Desktops (Googlebook, freeform windows) never get a lock:
 * the window is whatever shape the user drags it to.
 */
object DevicePresentationPolicy {
    const val TABLET_SMALLEST_WIDTH_DP = 600

    fun orientation(
        smallestWidthDp: Int,
        immersiveRuntime: Boolean,
        desktopWindowing: Boolean = false,
    ): OrientationPreference = when {
        immersiveRuntime || desktopWindowing -> OrientationPreference.SYSTEM
        smallestWidthDp >= TABLET_SMALLEST_WIDTH_DP -> OrientationPreference.USER_LANDSCAPE
        else -> OrientationPreference.SYSTEM
    }
}
