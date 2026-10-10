package com.orgista.openstream.player

import android.view.KeyEvent

enum class PlayerKeyAction {
    TOGGLE_PLAY,
    PLAY,
    PAUSE,
    SEEK_BACK,
    SEEK_FORWARD,
    TOGGLE_MUTE,
    TOGGLE_FULLSCREEN,
    PICTURE_IN_PICTURE,
    EXIT_FULLSCREEN,
    NONE,
}

/**
 * Desktop keyboard map for the player (YouTube/VLC conventions). Remote and
 * D-pad arrows stay with Media3's controller: arrow seeking applies only to a
 * full alphabetic keyboard, so TV remotes keep their existing behavior.
 */
object PlayerKeyboardPolicy {
    const val SEEK_STEP_MS = 10_000L

    fun action(
        keyCode: Int,
        fullKeyboard: Boolean,
        modified: Boolean,
        fullscreen: Boolean,
    ): PlayerKeyAction {
        when (keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_HEADSETHOOK -> return PlayerKeyAction.TOGGLE_PLAY
            KeyEvent.KEYCODE_MEDIA_PLAY -> return PlayerKeyAction.PLAY
            KeyEvent.KEYCODE_MEDIA_PAUSE -> return PlayerKeyAction.PAUSE
            KeyEvent.KEYCODE_MEDIA_REWIND -> return PlayerKeyAction.SEEK_BACK
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> return PlayerKeyAction.SEEK_FORWARD
        }
        if (!fullKeyboard || modified) return PlayerKeyAction.NONE
        return when (keyCode) {
            KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_K -> PlayerKeyAction.TOGGLE_PLAY
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_J -> PlayerKeyAction.SEEK_BACK
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_L -> PlayerKeyAction.SEEK_FORWARD
            KeyEvent.KEYCODE_M -> PlayerKeyAction.TOGGLE_MUTE
            KeyEvent.KEYCODE_F -> PlayerKeyAction.TOGGLE_FULLSCREEN
            KeyEvent.KEYCODE_P -> PlayerKeyAction.PICTURE_IN_PICTURE
            // Esc leaves full screen first; otherwise it falls through to the
            // system's Esc→Back fallback, which closes the player.
            KeyEvent.KEYCODE_ESCAPE -> if (fullscreen) PlayerKeyAction.EXIT_FULLSCREEN else PlayerKeyAction.NONE
            else -> PlayerKeyAction.NONE
        }
    }

    fun seekTarget(positionMs: Long, durationMs: Long, forward: Boolean): Long {
        val target = positionMs + if (forward) SEEK_STEP_MS else -SEEK_STEP_MS
        val upper = if (durationMs > 0L) durationMs else Long.MAX_VALUE
        return target.coerceIn(0L, upper)
    }
}
