package com.orgista.openstream.iptv

enum class IptvSourceType { M3U, XTREAM, PLUTO }

class IptvSource(
    val id: String,
    val name: String,
    val type: IptvSourceType,
    val endpoint: String,
    val username: String = "",
    val password: String = "",
) {
    override fun toString(): String =
        "IptvSource(id=$id,name=$name,type=$type,endpoint=$endpoint,username=<redacted>,password=<redacted>)"

    companion object {
        fun m3u(id: String, name: String, playlistUrl: String): IptvSource =
            IptvSource(id, name, IptvSourceType.M3U, playlistUrl)

        fun xtream(
            id: String,
            name: String,
            baseUrl: String,
            username: String,
            password: String,
        ): IptvSource = IptvSource(id, name, IptvSourceType.XTREAM, baseUrl, username, password)

        /** Runtime API integration; the private app-scoped device id is carried in the redacted username slot. */
        fun pluto(clientId: String): IptvSource = IptvSource(
            id = "pluto",
            name = "Pluto TV",
            type = IptvSourceType.PLUTO,
            endpoint = "https://boot.pluto.tv/v4/start",
            username = clientId,
        )
    }
}

data class IptvChannel(
    val id: String,
    val sourceId: String,
    val sourceName: String,
    val name: String,
    val group: String,
    val logoUrl: String,
    val streamUrl: String,
    val fallbackStreamUrls: List<String> = emptyList(),
    val httpUserAgent: String? = null,
    val httpReferer: String? = null,
    val guideId: String = "",
    val channelNumber: String = "",
) {
    override fun toString(): String =
        "IptvChannel(id=$id,sourceId=$sourceId,name=$name,group=$group,streamUrl=<redacted>)"
}

data class IptvPlaylist(
    val channels: List<IptvChannel>,
    val guideUrls: List<String> = emptyList(),
)

data class IptvSourceCatalog(
    val source: IptvSource,
    val channels: List<IptvChannel>,
    val guideUrls: List<String> = emptyList(),
    val embeddedGuidePrograms: List<IptvGuideProgram> = emptyList(),
)

data class IptvGuideProgram(
    val channelKey: String,
    val title: String,
    val subtitle: String = "",
    val description: String = "",
    val category: String = "",
    val startMillis: Long,
    val endMillis: Long,
)
