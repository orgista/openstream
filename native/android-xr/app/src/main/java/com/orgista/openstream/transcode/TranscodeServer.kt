package com.orgista.openstream.transcode

import android.content.Context
import androidx.core.content.edit
import com.orgista.openstream.offline.OfflineDeviceProfile
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URI
import java.net.URL

data class TranscodeServerConfig(
    val baseUrl: String,
    val sessionToken: String,
    val enabled: Boolean = true,
)

data class TranscodeServerCapabilities(
    val available: Boolean,
    val version: String?,
    val hardwareAccelerated: Boolean,
)

object TranscodeServerEndpointPolicy {
    fun normalize(value: String): String = value.trim().trimEnd('/')

    fun isAllowed(value: String): Boolean = runCatching {
        val uri = URI(normalize(value))
        if (uri.userInfo != null || uri.host.isNullOrBlank() || uri.query != null || uri.fragment != null) return false
        when (uri.scheme?.lowercase()) {
            "https" -> true
            "http" -> isPrivateLiteral(uri.host)
            else -> false
        }
    }.getOrDefault(false)

    private fun isPrivateLiteral(host: String): Boolean {
        if (host.equals("localhost", ignoreCase = true)) return true
        if (!host.matches(Regex("(?:\\d{1,3}\\.){3}\\d{1,3}"))) return false
        val address = runCatching { InetAddress.getByName(host) }.getOrNull() ?: return false
        return address.isAnyLocalAddress || address.isLoopbackAddress || address.isSiteLocalAddress
    }
}

class TranscodeServerStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("openstream.transcode.v1", Context.MODE_PRIVATE)

    fun load(): TranscodeServerConfig? {
        val raw = prefs.getString(KEY_CONFIG, null) ?: return null
        return runCatching {
            val json = JSONObject(raw)
            TranscodeServerConfig(
                baseUrl = json.getString("baseUrl"),
                sessionToken = json.getString("sessionToken"),
                enabled = json.optBoolean("enabled", true),
            )
        }.getOrNull()
    }

    fun save(config: TranscodeServerConfig) {
        require(TranscodeServerEndpointPolicy.isAllowed(config.baseUrl)) {
            "Use HTTPS, or a private local IP address for HTTP."
        }
        require(config.sessionToken.length >= 32) { "Gateway token must be at least 32 characters." }
        val json = JSONObject()
            .put("baseUrl", TranscodeServerEndpointPolicy.normalize(config.baseUrl))
            .put("sessionToken", config.sessionToken)
            .put("enabled", config.enabled)
        prefs.edit { putString(KEY_CONFIG, json.toString()) }
    }

    fun remove() {
        prefs.edit { remove(KEY_CONFIG) }
    }

    companion object {
        private const val KEY_CONFIG = "config"
    }
}

object TranscodeServerClient {
    fun capabilities(config: TranscodeServerConfig): TranscodeServerCapabilities {
        val json = requestJson(config, "GET", "/api/transcode/capabilities")
        return TranscodeServerCapabilities(
            available = json.optBoolean("available", false),
            version = json.optString("version").takeIf(String::isNotBlank),
            hardwareAccelerated = json.optBoolean("hardwareAccelerated", false),
        )
    }

    fun startSmbSession(
        config: TranscodeServerConfig,
        smbUri: String,
        profile: OfflineDeviceProfile,
    ): String {
        val payload = JSONObject()
            .put("smbUri", smbUri)
            .put(
                "profile",
                JSONObject()
                    .put("maxWidth", profile.maxWidth)
                    .put("maxHeight", profile.maxHeight)
                    .put("videoCodec", "h264"),
            )
        val json = requestJson(config, "POST", "/api/transcode/smb-sessions", payload.toString())
        val route = json.getString("transcodeUrl")
            .replaceFirst("/gateway/", "/api/")
        return if (route.startsWith("http://") || route.startsWith("https://")) {
            route
        } else {
            "${config.baseUrl.trimEnd('/')}/${route.trimStart('/')}"
        }
    }

    private fun requestJson(
        config: TranscodeServerConfig,
        method: String,
        path: String,
        body: String? = null,
    ): JSONObject {
        val connection = URL("${config.baseUrl.trimEnd('/')}$path").openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.connectTimeout = 8_000
        connection.readTimeout = 15_000
        connection.instanceFollowRedirects = false
        connection.setRequestProperty("Accept", "application/json")
        connection.setRequestProperty("X-OpenStream-Session", config.sessionToken)
        connection.setRequestProperty("X-OpenStream-Client", "android")
        if (body != null) {
            val bytes = body.toByteArray(Charsets.UTF_8)
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Content-Length", bytes.size.toString())
            connection.outputStream.use { it.write(bytes) }
        }
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        if (status !in 200..299) {
            val message = runCatching { JSONObject(text).optString("error") }.getOrNull()
                ?.takeIf(String::isNotBlank)
                ?: "Gateway request failed with HTTP $status."
            throw IOException(message)
        }
        return JSONObject(text)
    }
}
