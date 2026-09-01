package com.cyberbanksy.openstream.xr

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Challenger2IntentSecurityTest {

    @Test
    fun `empirical scheme allowlist stress verification`() {
        // Allowed schemes
        assertTrue(MainActivity.isAllowedScheme("content"))
        assertTrue(MainActivity.isAllowedScheme("file"))
        assertTrue(MainActivity.isAllowedScheme("http"))
        assertTrue(MainActivity.isAllowedScheme("https"))

        // Case insensitivity
        assertTrue(MainActivity.isAllowedScheme("CONTENT"))
        assertTrue(MainActivity.isAllowedScheme("FILE"))
        assertTrue(MainActivity.isAllowedScheme("HTTP"))
        assertTrue(MainActivity.isAllowedScheme("HTTPS"))
        assertTrue(MainActivity.isAllowedScheme("Http"))
        assertTrue(MainActivity.isAllowedScheme("Https"))
        assertTrue(MainActivity.isAllowedScheme("Content"))

        // Malicious & dangerous schemes that must be strictly rejected
        assertFalse("javascript scheme must be blocked", MainActivity.isAllowedScheme("javascript"))
        assertFalse("smb scheme must be blocked in SceneCore view intents", MainActivity.isAllowedScheme("smb"))
        assertFalse("data scheme must be blocked", MainActivity.isAllowedScheme("data"))
        assertFalse("intent scheme must be blocked", MainActivity.isAllowedScheme("intent"))
        assertFalse("android.resource scheme must be blocked", MainActivity.isAllowedScheme("android.resource"))
        assertFalse("ftp scheme must be blocked", MainActivity.isAllowedScheme("ftp"))
        assertFalse("rtsp scheme must be blocked", MainActivity.isAllowedScheme("rtsp"))
        assertFalse("ws scheme must be blocked", MainActivity.isAllowedScheme("ws"))
        assertFalse("wss scheme must be blocked", MainActivity.isAllowedScheme("wss"))
        assertFalse("blob scheme must be blocked", MainActivity.isAllowedScheme("blob"))
        assertFalse("about scheme must be blocked", MainActivity.isAllowedScheme("about"))
        assertFalse("chrome scheme must be blocked", MainActivity.isAllowedScheme("chrome"))

        // Malformed / empty / null
        assertFalse(MainActivity.isAllowedScheme(null))
        assertFalse(MainActivity.isAllowedScheme(""))
        assertFalse(MainActivity.isAllowedScheme("   "))
        assertFalse(MainActivity.isAllowedScheme("javascript:alert(1)"))
    }
}
