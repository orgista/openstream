package com.orgista.openstream.ui

import android.content.Context
import android.content.ContextWrapper
import android.view.KeyEvent
import androidx.compose.runtime.State

/**
 * Window features the activity provides to Compose screens: keyboard routing
 * that works whichever view holds focus (PlayerView swallows keys otherwise),
 * picture-in-picture, and desktop full-screen windows.
 */
interface PlaybackWindowHost {
    val inPictureInPicture: State<Boolean>

    /** True on Googlebook/desktop windowing, where windows resize freely. */
    val desktopWindowing: Boolean

    /** True while OpenStream itself has put its desktop window in full screen. */
    val fullscreenWindow: Boolean

    /** A freeform window can go full screen, or OpenStream's own full screen can be left. */
    val canToggleFullscreen: Boolean

    fun setPlayerKeyHandler(handler: ((KeyEvent) -> Boolean)?)

    fun setAppKeyHandler(handler: ((KeyEvent) -> Boolean)?)

    /** Playing video arms auto-enter picture-in-picture when the user leaves. */
    fun updatePlayback(playing: Boolean, videoWidth: Int, videoHeight: Int)

    fun enterPictureInPicture(): Boolean

    fun toggleFullscreenWindow()
}

fun Context.playbackWindowHost(): PlaybackWindowHost? {
    var current: Context? = this
    while (current != null) {
        if (current is PlaybackWindowHost) return current
        current = (current as? ContextWrapper)?.baseContext
    }
    return null
}
