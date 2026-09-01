package com.orgista.openstream.iptv

import com.orgista.openstream.data.UserAgents
import java.net.HttpURLConnection
import java.net.URI

object IptvClient {
    fun load(source: IptvSource): List<IptvChannel> = loadCatalog(source).channels

    fun loadCatalog(source: IptvSource): IptvSourceCatalog = when (source.type) {
        IptvSourceType.M3U -> loadM3u(source)
        IptvSourceType.XTREAM -> IptvSourceCatalog(
            source = source,
            channels = XtreamClient.load(source),
            guideUrls = listOf(XtreamClient.xmlTvUrl(source)),
        )
        IptvSourceType.PLUTO -> PlutoIptvClient.load(source)
    }

    private fun loadM3u(source: IptvSource): IptvSourceCatalog {
        require(IptvEndpointPolicy.isAllowed(source.endpoint)) { "Enter an HTTP or HTTPS IPTV server address." }
        val connection = (URI(source.endpoint).toURL().openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 8_000
            readTimeout = 15_000
            instanceFollowRedirects = false
            setRequestProperty("Accept", "application/vnd.apple.mpegurl, audio/x-mpegurl, text/plain")
            setRequestProperty("User-Agent", UserAgents.product)
        }
        try {
            val status = connection.responseCode
            require(status in 200..299) { "IPTV playlist returned HTTP $status." }
            val body = connection.inputStream.bufferedReader().use { reader ->
                val text = reader.readText()
                require(text.length <= 12_000_000) { "IPTV playlist is too large." }
                text
            }
            val playlist = M3uParser.parsePlaylist(source.id, source.endpoint, body, source.name)
            return IptvSourceCatalog(
                source = source,
                channels = playlist.channels,
                guideUrls = IptvGuideSourcePolicy.select(playlist.guideUrls, source.name),
            )
        } finally {
            connection.disconnect()
        }
    }
}
