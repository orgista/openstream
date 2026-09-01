package com.orgista.openstream.arr

import com.orgista.openstream.data.UserAgents
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URI
import java.net.URL
import java.nio.charset.StandardCharsets
import javax.net.ssl.HttpsURLConnection

object ArrClient {
    private const val STANDARD_RESPONSE_LIMIT = 512 * 1024
    private const val CATALOG_RESPONSE_LIMIT = 8 * 1024 * 1024
    private const val MAX_HEADER_BYTES = 64 * 1024

    fun test(connection: ArrConnection): ArrStatus {
        return parseStatus(request(connection, "GET", "/api/v3/system/status"))
    }

    fun parseStatus(body: String): ArrStatus {
        val json = JSONObject(body)
        return ArrStatus(
            appName = json.optString("appName").ifBlank { "ARR" }.take(80),
            version = json.optString("version").take(40),
            instanceName = json.optString("instanceName").take(80),
        )
    }

    internal fun request(
        connection: ArrConnection,
        method: String,
        path: String,
        body: String? = null,
    ): String {
        require(ArrEndpointPolicy.isAllowed(connection.baseUrl)) { "Use HTTPS, or a private local IP address for HTTP." }
        require(connection.apiKey.isNotBlank()) { "API key is required." }
        require(method in setOf("GET", "POST", "PUT")) { "Unsupported ARR request." }
        require(path.startsWith("/api/v3/")) { "Unsupported ARR path." }
        val endpoint = "${ArrEndpointPolicy.normalize(connection.baseUrl)}$path"
        val responseLimit = responseLimitBytes(path)
        return if (endpoint.startsWith("https://")) {
            httpsRequest(endpoint, connection.apiKey, method, body, responseLimit)
        } else {
            privateHttpRequest(endpoint, connection.apiKey, method, body, responseLimit)
        }
    }

    fun responseLimitBytes(path: String): Int = when (path) {
        "/api/v3/movie", "/api/v3/series" -> CATALOG_RESPONSE_LIMIT
        else -> STANDARD_RESPONSE_LIMIT
    }

    private fun httpsRequest(
        endpoint: String,
        apiKey: String,
        method: String,
        body: String?,
        responseLimit: Int,
    ): String {
        val connection = URL(endpoint).openConnection() as HttpsURLConnection
        connection.connectTimeout = 6_000
        connection.readTimeout = 15_000
        connection.instanceFollowRedirects = false
        connection.requestMethod = method
        connection.setRequestProperty("Accept", "application/json")
        connection.setRequestProperty("X-Api-Key", apiKey)
        connection.setRequestProperty("User-Agent", UserAgents.arr)
        if (body != null) {
            val bytes = body.toByteArray(StandardCharsets.UTF_8)
            connection.doOutput = true
            connection.setFixedLengthStreamingMode(bytes.size)
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            connection.outputStream.use { it.write(bytes) }
        }
        return try {
            val status = connection.responseCode
            if (status !in 200..299) throw IOException("${method.lowercase().replaceFirstChar(Char::uppercase)} request returned HTTP $status.")
            connection.inputStream.use { input ->
                String(readLimited(input, responseLimit), StandardCharsets.UTF_8)
            }
        } finally {
            connection.disconnect()
        }
    }

    /**
     * Android intentionally blocks broad cleartext traffic. This bounded client
     * supports the common private-IP ARR setup without enabling HTTP for the
     * rest of the app. Redirects and public hosts are never followed.
     */
    private fun privateHttpRequest(
        endpoint: String,
        apiKey: String,
        method: String,
        body: String?,
        responseLimit: Int,
    ): String {
        val uri = URI(endpoint)
        if (!ArrEndpointPolicy.isPrivateLiteral(uri.host)) throw IOException("Local HTTP requires a private IP address.")
        val port = if (uri.port > 0) uri.port else 80
        val path = buildString {
            append(uri.rawPath.ifBlank { "/" })
            uri.rawQuery?.let { append('?').append(it) }
        }
        // Socket(host, port) blocks on the OS connect timeout (~2 min on an
        // unroutable IP); connect() with an explicit deadline matches the HTTPS
        // path's 6s budget. soTimeout still bounds each subsequent read.
        return Socket().use { socket ->
            socket.connect(InetSocketAddress(uri.host, port), 6_000)
            socket.soTimeout = 15_000
            val bodyBytes = body?.toByteArray(StandardCharsets.UTF_8)
            val headers = buildString {
                append("$method $path HTTP/1.1\r\n")
                append("Host: ${uri.host}:$port\r\n")
                append("Accept: application/json\r\n")
                append("X-Api-Key: $apiKey\r\n")
                append("User-Agent: ${UserAgents.arr}\r\n")
                if (bodyBytes != null) {
                    append("Content-Type: application/json; charset=utf-8\r\n")
                    append("Content-Length: ${bodyBytes.size}\r\n")
                }
                append("Connection: close\r\n\r\n")
            }.toByteArray(StandardCharsets.US_ASCII)
            socket.getOutputStream().apply {
                write(headers)
                if (bodyBytes != null) write(bodyBytes)
                flush()
            }

            val responseBytes = readLimited(socket.getInputStream(), responseLimit + MAX_HEADER_BYTES)
            // Keep the response as raw bytes: the header line is ASCII, but the
            // body may contain multi-byte UTF-8, and chunk sizes count BYTES.
            // Decoding to String before de-framing would misalign every chunk
            // boundary that follows a non-ASCII byte and corrupt the JSON.
            val headEnd = indexOfCrlfCrlf(responseBytes)
            if (headEnd < 0) throw IOException("ARR returned an invalid response.")
            val headerText = String(responseBytes, 0, headEnd, StandardCharsets.US_ASCII)
            val status = headerText.lineSequence().firstOrNull()?.split(' ')?.getOrNull(1)?.toIntOrNull()
                ?: throw IOException("ARR returned an invalid status.")
            if (status !in 200..299) throw IOException("${method.lowercase().replaceFirstChar(Char::uppercase)} request returned HTTP $status.")
            val decoded = decodeHttpBody(headerText, responseBytes, headEnd + 4)
            if (decoded.toByteArray(StandardCharsets.UTF_8).size > responseLimit) {
                throw IOException("ARR response is too large.")
            }
            decoded
        }
    }

    private fun readLimited(input: InputStream, limit: Int): ByteArray {
        val output = ByteArrayOutputStream(minOf(limit, 64 * 1024))
        val buffer = ByteArray(8_192)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            if (output.size() + count > limit) throw IOException("ARR response is too large.")
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    /**
     * De-frames the response body on the raw byte array using byte offsets,
     * then charset-decodes the assembled bytes. Chunk sizes are byte counts, so
     * all framing arithmetic must happen before UTF-8 decoding.
     */
    private fun decodeHttpBody(headers: String, response: ByteArray, bodyStart: Int): String {
        if (!headers.contains("transfer-encoding: chunked", ignoreCase = true)) {
            return String(response, bodyStart, response.size - bodyStart, StandardCharsets.UTF_8)
        }
        val assembled = ByteArrayOutputStream()
        var cursor = bodyStart
        while (cursor < response.size) {
            val lineEnd = indexOfCrlf(response, cursor)
            if (lineEnd < 0) break
            val sizeText = String(response, cursor, lineEnd - cursor, StandardCharsets.US_ASCII)
                .substringBefore(';').trim()
            val size = sizeText.toIntOrNull(16) ?: break
            if (size == 0) break
            val chunkStart = lineEnd + 2
            val chunkEnd = (chunkStart + size).coerceAtMost(response.size)
            assembled.write(response, chunkStart, chunkEnd - chunkStart)
            cursor = chunkEnd + 2
        }
        return assembled.toString(StandardCharsets.UTF_8.name())
    }

    /** Index of the CRLFCRLF header/body separator, or -1 if absent. */
    private fun indexOfCrlfCrlf(bytes: ByteArray): Int {
        val cr = '\r'.code.toByte()
        val lf = '\n'.code.toByte()
        var i = 0
        while (i <= bytes.size - 4) {
            if (bytes[i] == cr && bytes[i + 1] == lf && bytes[i + 2] == cr && bytes[i + 3] == lf) return i
            i++
        }
        return -1
    }

    /** Index of the next CRLF at or after [from], or -1 if absent. */
    private fun indexOfCrlf(bytes: ByteArray, from: Int): Int {
        val cr = '\r'.code.toByte()
        val lf = '\n'.code.toByte()
        var i = from
        while (i < bytes.size - 1) {
            if (bytes[i] == cr && bytes[i + 1] == lf) return i
            i++
        }
        return -1
    }
}
