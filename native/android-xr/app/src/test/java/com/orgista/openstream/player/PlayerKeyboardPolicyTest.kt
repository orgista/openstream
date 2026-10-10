package com.orgista.openstream.player

import android.view.KeyEvent
import org.junit.Assert.assertEquals
import org.junit.Test

class PlayerKeyboardPolicyTest {
    private fun action(keyCode: Int, fullKeyboard: Boolean = true, modified: Boolean = false, fullscreen: Boolean = false) =
        PlayerKeyboardPolicy.action(keyCode, fullKeyboard, modified, fullscreen)

    @Test
    fun `space and k toggle playback on a desktop keyboard`() {
        assertEquals(PlayerKeyAction.TOGGLE_PLAY, action(KeyEvent.KEYCODE_SPACE))
        assertEquals(PlayerKeyAction.TOGGLE_PLAY, action(KeyEvent.KEYCODE_K))
    }

    @Test
    fun `arrows seek only on a full keyboard so TV remotes keep the controller`() {
        assertEquals(PlayerKeyAction.SEEK_BACK, action(KeyEvent.KEYCODE_DPAD_LEFT))
        assertEquals(PlayerKeyAction.SEEK_FORWARD, action(KeyEvent.KEYCODE_DPAD_RIGHT))
        assertEquals(PlayerKeyAction.NONE, action(KeyEvent.KEYCODE_DPAD_LEFT, fullKeyboard = false))
        assertEquals(PlayerKeyAction.NONE, action(KeyEvent.KEYCODE_DPAD_CENTER))
    }

    @Test
    fun `media keys work from any input device`() {
        assertEquals(PlayerKeyAction.TOGGLE_PLAY, action(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, fullKeyboard = false))
        assertEquals(PlayerKeyAction.PAUSE, action(KeyEvent.KEYCODE_MEDIA_PAUSE, fullKeyboard = false))
        assertEquals(PlayerKeyAction.SEEK_FORWARD, action(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD, fullKeyboard = false))
    }

    @Test
    fun `modified letters are left for app shortcuts`() {
        assertEquals(PlayerKeyAction.NONE, action(KeyEvent.KEYCODE_F, modified = true))
        assertEquals(PlayerKeyAction.TOGGLE_FULLSCREEN, action(KeyEvent.KEYCODE_F))
        assertEquals(PlayerKeyAction.TOGGLE_MUTE, action(KeyEvent.KEYCODE_M))
    }

    @Test
    fun `escape exits full screen first and otherwise falls through to back`() {
        assertEquals(PlayerKeyAction.EXIT_FULLSCREEN, action(KeyEvent.KEYCODE_ESCAPE, fullscreen = true))
        assertEquals(PlayerKeyAction.NONE, action(KeyEvent.KEYCODE_ESCAPE, fullscreen = false))
    }

    @Test
    fun `seek targets clamp to the media bounds`() {
        assertEquals(0L, PlayerKeyboardPolicy.seekTarget(4_000L, 60_000L, forward = false))
        assertEquals(60_000L, PlayerKeyboardPolicy.seekTarget(55_000L, 60_000L, forward = true))
        assertEquals(25_000L, PlayerKeyboardPolicy.seekTarget(15_000L, -1L, forward = true))
    }
}
