package com.orgista.openstream.lan

import com.orgista.openstream.player.SmbHostPolicy
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.Socket
import java.net.URI
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Challenger2SecurityStressTest {

    // ==========================================
    // 1. LanSetupServer CSRF & Origin Protections
    // ==========================================

    @Test
    fun `empirical CSRF challenge - cross origin attacker com is rejected with 403`() {
        val added = CopyOnWriteArrayList<String>()
        val server = LanSetupServer(
            addManifest = { manifest -> added += manifest; "Added" },
            onAdded = {},
        )
        val session = server.start()
        try {
            val uri = URI.create(session.url)
            val manifest = "https://addon.example/manifest.json"
            val body = "manifest=" + URLEncoder.encode(manifest, StandardCharsets.UTF_8.name()) +
                "&token=" + URLEncoder.encode(session.token, StandardCharsets.UTF_8.name())

            Socket(uri.host, uri.port).use { socket ->
                val request = "POST ${uri.rawPath} HTTP/1.1\r\n" +
                    "Host: ${uri.host}:${uri.port}\r\n" +
                    "Origin: http://attacker.com\r\n" +
                    "Content-Type: application/x-www-form-urlencoded\r\n" +
                    "Content-Length: ${body.toByteArray(StandardCharsets.UTF_8).size}\r\n" +
                    "Connection: close\r\n\r\n" +
                    body
                socket.getOutputStream().write(request.toByteArray(StandardCharsets.UTF_8))
                socket.getOutputStream().flush()
                val responseLine = socket.getInputStream().bufferedReader(StandardCharsets.UTF_8).readLine().orEmpty()
                assertTrue("Expected 403 Forbidden for http://attacker.com, got: $responseLine", responseLine.startsWith("HTTP/1.1 403"))
            }
            assertTrue("CSRF attack should not add manifest", added.isEmpty())
        } finally {
            server.close()
        }
    }

    @Test
    fun `empirical CSRF challenge - null origin from sandboxed iframe is rejected with 403`() {
        val added = CopyOnWriteArrayList<String>()
        val server = LanSetupServer(
            addManifest = { manifest -> added += manifest; "Added" },
            onAdded = {},
        )
        val session = server.start()
        try {
            val uri = URI.create(session.url)
            val manifest = "https://addon.example/manifest.json"
            val body = "manifest=" + URLEncoder.encode(manifest, StandardCharsets.UTF_8.name()) +
                "&token=" + URLEncoder.encode(session.token, StandardCharsets.UTF_8.name())

            Socket(uri.host, uri.port).use { socket ->
                val request = "POST ${uri.rawPath} HTTP/1.1\r\n" +
                    "Host: ${uri.host}:${uri.port}\r\n" +
                    "Origin: null\r\n" +
                    "Content-Type: application/x-www-form-urlencoded\r\n" +
                    "Content-Length: ${body.toByteArray(StandardCharsets.UTF_8).size}\r\n" +
                    "Connection: close\r\n\r\n" +
                    body
                socket.getOutputStream().write(request.toByteArray(StandardCharsets.UTF_8))
                socket.getOutputStream().flush()
                val responseLine = socket.getInputStream().bufferedReader(StandardCharsets.UTF_8).readLine().orEmpty()
                assertTrue("Expected 403 Forbidden for null origin, got: $responseLine", responseLine.startsWith("HTTP/1.1 403"))
            }
            assertTrue(added.isEmpty())
        } finally {
            server.close()
        }
    }

    @Test
    fun `empirical CSRF challenge - missing or wrong tokens are rejected with 403`() {
        val added = CopyOnWriteArrayList<String>()
        val server = LanSetupServer(
            addManifest = { manifest -> added += manifest; "Added" },
            onAdded = {},
        )
        val session = server.start()
        try {
            val uri = URI.create(session.url)
            val manifest = "https://addon.example/manifest.json"

            // 1. Missing token completely
            val bodyMissing = "manifest=" + URLEncoder.encode(manifest, StandardCharsets.UTF_8.name())
            Socket(uri.host, uri.port).use { socket ->
                val request = "POST ${uri.rawPath} HTTP/1.1\r\n" +
                    "Host: ${uri.host}:${uri.port}\r\n" +
                    "Origin: http://${uri.host}:${uri.port}\r\n" +
                    "Content-Type: application/x-www-form-urlencoded\r\n" +
                    "Content-Length: ${bodyMissing.toByteArray(StandardCharsets.UTF_8).size}\r\n" +
                    "Connection: close\r\n\r\n" +
                    bodyMissing
                socket.getOutputStream().write(request.toByteArray(StandardCharsets.UTF_8))
                socket.getOutputStream().flush()
                val responseLine = socket.getInputStream().bufferedReader(StandardCharsets.UTF_8).readLine().orEmpty()
                assertTrue("Expected 403 Forbidden for missing token, got: $responseLine", responseLine.startsWith("HTTP/1.1 403"))
            }

            // 2. Wrong / forged token
            val bodyWrong = "manifest=" + URLEncoder.encode(manifest, StandardCharsets.UTF_8.name()) +
                "&token=deadbeef00000000deadbeef00000000"
            Socket(uri.host, uri.port).use { socket ->
                val request = "POST ${uri.rawPath} HTTP/1.1\r\n" +
                    "Host: ${uri.host}:${uri.port}\r\n" +
                    "Origin: http://${uri.host}:${uri.port}\r\n" +
                    "Content-Type: application/x-www-form-urlencoded\r\n" +
                    "Content-Length: ${bodyWrong.toByteArray(StandardCharsets.UTF_8).size}\r\n" +
                    "Connection: close\r\n\r\n" +
                    bodyWrong
                socket.getOutputStream().write(request.toByteArray(StandardCharsets.UTF_8))
                socket.getOutputStream().flush()
                val responseLine = socket.getInputStream().bufferedReader(StandardCharsets.UTF_8).readLine().orEmpty()
                assertTrue("Expected 403 Forbidden for wrong token, got: $responseLine", responseLine.startsWith("HTTP/1.1 403"))
            }

            assertTrue(added.isEmpty())
        } finally {
            server.close()
        }
    }

    @Test
    fun `empirical CSRF challenge - valid local origins with valid tokens succeed`() {
        val added = CopyOnWriteArrayList<String>()
        val server = LanSetupServer(
            addManifest = { manifest -> added += manifest; "Added $manifest" },
            onAdded = {},
        )
        val session = server.start()
        try {
            val uri = URI.create(session.url)
            val manifest = "https://addon.example/manifest.json"
            val body = "manifest=" + URLEncoder.encode(manifest, StandardCharsets.UTF_8.name()) +
                "&token=" + URLEncoder.encode(session.token, StandardCharsets.UTF_8.name())

            // Test form token + origin http://${uri.host}:${uri.port}
            Socket(uri.host, uri.port).use { socket ->
                val request = "POST ${uri.rawPath} HTTP/1.1\r\n" +
                    "Host: ${uri.host}:${uri.port}\r\n" +
                    "Origin: http://${uri.host}:${uri.port}\r\n" +
                    "Content-Type: application/x-www-form-urlencoded\r\n" +
                    "Content-Length: ${body.toByteArray(StandardCharsets.UTF_8).size}\r\n" +
                    "Connection: close\r\n\r\n" +
                    body
                socket.getOutputStream().write(request.toByteArray(StandardCharsets.UTF_8))
                socket.getOutputStream().flush()
                val responseLine = socket.getInputStream().bufferedReader(StandardCharsets.UTF_8).readLine().orEmpty()
                assertTrue("Expected 200 OK for valid request, got: $responseLine", responseLine.startsWith("HTTP/1.1 200"))
            }
            assertEquals(listOf(manifest), added)
        } finally {
            server.close()
        }
    }

    @Test
    fun `empirical origin validation matrix`() {
        val serverHost = "192.168.1.50"
        val serverPort = 11470

        // Permitted
        assertTrue(LanSetupProtocol.isValidOrigin("http://localhost:11470", serverHost, serverPort))
        assertTrue(LanSetupProtocol.isValidOrigin("http://127.0.0.1:11470", serverHost, serverPort))
        assertTrue(LanSetupProtocol.isValidOrigin("http://openstream.local:11470", serverHost, serverPort))
        assertTrue(LanSetupProtocol.isValidOrigin("http://192.168.1.50:11470", serverHost, serverPort))
        assertTrue(LanSetupProtocol.isValidOrigin("http://192.168.1.120:11470", serverHost, serverPort)) // LAN IP
        assertTrue(LanSetupProtocol.isValidOrigin(null, serverHost, serverPort)) // Non-browser / CLI client

        // Forbidden
        assertFalse(LanSetupProtocol.isValidOrigin("http://attacker.com", serverHost, serverPort))
        assertFalse(LanSetupProtocol.isValidOrigin("http://attacker.com:11470", serverHost, serverPort))
        assertFalse(LanSetupProtocol.isValidOrigin("https://evil.org:11470", serverHost, serverPort))
        assertFalse(LanSetupProtocol.isValidOrigin("http://192.168.1.50:8080", serverHost, serverPort)) // Wrong port
        assertFalse(LanSetupProtocol.isValidOrigin("null", serverHost, serverPort)) // Sandboxed origin
        assertFalse(LanSetupProtocol.isValidOrigin("javascript:void(0)", serverHost, serverPort))
        assertFalse(LanSetupProtocol.isValidOrigin("file:///etc/passwd", serverHost, serverPort))
        assertFalse(LanSetupProtocol.isValidOrigin("http://8.8.8.8:11470", serverHost, serverPort)) // Public IP
    }

    // ==========================================
    // 2. SmbDataSource Host Validation & Relay Prevention
    // ==========================================

    @Test
    fun `empirical SmbHostPolicy stress matrix`() {
        val expectedHost = "192.168.1.100"

        // 1. Matching host
        assertTrue(SmbHostPolicy.isHostAllowed("smb://192.168.1.100/media/movie.mkv", expectedHost))
        assertTrue(SmbHostPolicy.isHostAllowed("SMB://192.168.1.100/media/movie.mkv", expectedHost))
        assertTrue(SmbHostPolicy.isHostAllowed("smb://192.168.1.100:445/media/movie.mkv", expectedHost))
        assertTrue(SmbHostPolicy.isHostAllowed("smb://user:pass@192.168.1.100/media/movie.mkv", expectedHost))

        // 2. Hostname case insensitivity
        assertTrue(SmbHostPolicy.isHostAllowed("smb://MY-NAS.LOCAL/share/file.mkv", "my-nas.local"))
        assertTrue(SmbHostPolicy.isHostAllowed("smb://my-nas.local/share/file.mkv", "MY-NAS.LOCAL"))

        // 3. Mismatched host / Rogue external IPs / Relay targets
        assertFalse(SmbHostPolicy.isHostAllowed("smb://attacker.evil.com/share/file.mkv", expectedHost))
        assertFalse(SmbHostPolicy.isHostAllowed("smb://192.168.1.101/media/movie.mkv", expectedHost))
        assertFalse(SmbHostPolicy.isHostAllowed("smb://10.0.0.1/share/file.mkv", expectedHost))
        assertFalse(SmbHostPolicy.isHostAllowed("smb://198.51.100.23/share/file.mkv", expectedHost))

        // 4. Userinfo injection / credential theft tricks
        // smb://192.168.1.100@attacker.com/ -> host is attacker.com
        assertFalse(SmbHostPolicy.isHostAllowed("smb://192.168.1.100@attacker.com/share/file.mkv", expectedHost))

        // 5. Domain suffix / prefix tricks
        assertFalse(SmbHostPolicy.isHostAllowed("smb://192.168.1.100.attacker.com/share/file.mkv", expectedHost))
        assertFalse(SmbHostPolicy.isHostAllowed("smb://attacker-192.168.1.100/share/file.mkv", expectedHost))

        // 6. Scheme bypasses
        assertFalse(SmbHostPolicy.isHostAllowed("http://192.168.1.100/share/file.mkv", expectedHost))
        assertFalse(SmbHostPolicy.isHostAllowed("https://192.168.1.100/share/file.mkv", expectedHost))
        assertFalse(SmbHostPolicy.isHostAllowed("ftp://192.168.1.100/share/file.mkv", expectedHost))
        assertFalse(SmbHostPolicy.isHostAllowed("file:///192.168.1.100/share/file.mkv", expectedHost))
        assertFalse(SmbHostPolicy.isHostAllowed("javascript://192.168.1.100/alert(1)", expectedHost))
        assertFalse(SmbHostPolicy.isHostAllowed("data://192.168.1.100", expectedHost))

        // 7. Malformed URIs
        assertFalse(SmbHostPolicy.isHostAllowed("smb:///share/file.mkv", expectedHost))
        assertFalse(SmbHostPolicy.isHostAllowed("", expectedHost))
        assertFalse(SmbHostPolicy.isHostAllowed("not a uri", expectedHost))
    }
}
