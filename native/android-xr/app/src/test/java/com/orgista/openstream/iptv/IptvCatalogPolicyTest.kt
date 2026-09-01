package com.orgista.openstream.iptv

import org.junit.Assert.assertEquals
import org.junit.Test

class IptvCatalogPolicyTest {
    private fun channel(id: String) = IptvChannel(
        id = id,
        sourceId = "custom",
        sourceName = "My TV",
        name = id,
        group = "Entertainment",
        logoUrl = "",
        streamUrl = "https://media.example/$id.m3u8",
    )

    @Test
    fun `fresh installs have no compiled live tv sources`() {
        assertEquals(emptyList<IptvSource>(), IptvSourceSelection.configured(null))
        val configured = IptvSource.m3u("custom", "My TV", "https://provider.example/list.m3u")
        val pluto = IptvSource.pluto("private-device-id")
        assertEquals(listOf(configured), IptvSourceSelection.configured(configured))
        assertEquals(listOf(pluto, configured), IptvSourceSelection.configured(configured, pluto))
    }

    @Test
    fun `matching configured channels become one card with an automatic fallback route`() {
        val primary = channel("news-main").copy(name = "Example News")
        val fallback = channel("news-alt").copy(
            name = "Example News 24/7 (720p)",
            streamUrl = "https://backup.example/news.m3u8",
        )

        val merged = IptvCatalogPolicy.mergeRoutes(listOf(primary, fallback))

        assertEquals(1, merged.size)
        assertEquals(primary.streamUrl, merged.single().streamUrl)
        assertEquals(listOf(fallback.streamUrl), merged.single().fallbackStreamUrls)
    }

    @Test
    fun `configured source order determines the primary playback route`() {
        val primary = channel("primary").copy(
            sourceId = "custom",
            name = "Example Channel HD",
            streamUrl = "https://provider.example/channel.m3u8",
        )
        val alternate = channel("alternate").copy(
            sourceId = ManualLiveChannelPolicy.SOURCE_ID,
            name = "Example Channel",
            streamUrl = "https://manual.example/channel.m3u8",
        )

        val merged = IptvCatalogPolicy.mergeForPlayback(listOf(primary, alternate))

        assertEquals(primary.streamUrl, merged.single().streamUrl)
        assertEquals(listOf(alternate.streamUrl), merged.single().fallbackStreamUrls)
    }

    @Test
    fun `short station call signs merge within configured routes`() {
        val primary = channel("short-main").copy(
            name = "NEWS",
            streamUrl = "https://provider.example/short.m3u8",
        )
        val alternate = channel("short-alt").copy(
            sourceId = ManualLiveChannelPolicy.SOURCE_ID,
            name = "NEWS SD",
            streamUrl = "https://manual.example/short.m3u8",
        )

        val merged = IptvCatalogPolicy.mergeForPlayback(listOf(primary, alternate))

        assertEquals(1, merged.size)
        assertEquals(primary.streamUrl, merged.single().streamUrl)
        assertEquals(listOf(alternate.streamUrl), merged.single().fallbackStreamUrls)
    }

    @Test
    fun `quality and coast labels merge into alternate playback routes`() {
        val hd = channel("comedy-hd").copy(name = "Example Comedy HD")
        val fhdWest = channel("comedy-fhd").copy(
            name = "Example Comedy FHD West",
            streamUrl = "https://provider.example/comedy.m3u8",
        )

        val merged = IptvCatalogPolicy.mergeForPlayback(listOf(hd, fhdWest))

        assertEquals(1, merged.size)
        assertEquals(hd.streamUrl, merged.single().streamUrl)
        assertEquals(listOf(fhdWest.streamUrl), merged.single().fallbackStreamUrls)
    }

    @Test
    fun `two letter names remain separate because they are too ambiguous`() {
        val first = channel("ax-one").copy(name = "AX", streamUrl = "https://one.example/ax.m3u8")
        val second = channel("ax-two").copy(
            sourceId = ManualLiveChannelPolicy.SOURCE_ID,
            name = "AX HD",
            streamUrl = "https://two.example/ax.m3u8",
        )

        assertEquals(2, IptvCatalogPolicy.mergeForPlayback(listOf(first, second)).size)
    }
}
