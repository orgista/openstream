package com.orgista.openstream.iptv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlutoIptvClientTest {
    private val sessionJson = """
        {
          "sessionToken":"private-token",
          "stitcherParams":"deviceType=web&serverSideAds=false",
          "servers":{"stitcher":"https://stitcher.example.pluto.tv"}
        }
    """.trimIndent()

    @Test
    fun `session parser keeps credentials out of diagnostics`() {
        val session = PlutoIptvClient.parseSession(sessionJson)

        assertEquals("https://stitcher.example.pluto.tv", session.stitcherUrl)
        assertEquals("private-token", session.token)
        assertFalse(session.toString().contains("private-token"))
    }

    @Test
    fun `catalog parser creates authenticated channels and current guide rows`() {
        val channels = """
            {"data":[{"id":"5ca6748a37b88b269472dad9","name":"Nick Jr. Pluto TV","number":3700,
              "categoryIDs":["kids"],"images":[{"type":"colorLogoPNG","url":"https://images.pluto.tv/nick.png"}]}]}
        """.trimIndent()
        val categories = """
            {"data":[{"id":"kids","name":"Kids & Family","channelIDs":["5ca6748a37b88b269472dad9"]}]}
        """.trimIndent()
        val timelines = listOf(
            """
                {"data":[{"channelId":"5ca6748a37b88b269472dad9","timelines":[{
                  "title":"PAW Patrol","start":"2026-08-21T21:41:00.000Z","stop":"2026-08-21T22:07:00.000Z",
                  "episode":{"name":"Air Pups","description":"The pups help their friends.","genre":"Children & Family"}
                }]}]}
            """.trimIndent(),
        )

        val catalog = PlutoIptvClient.parseCatalog(
            IptvSource.pluto("device-id"),
            channels,
            categories,
            timelines,
            PlutoIptvClient.parseSession(sessionJson),
        )

        val channel = catalog.channels.single()
        assertEquals("Nick Jr. Pluto TV", channel.name)
        assertEquals("Kids & Family", channel.group)
        assertTrue(channel.streamUrl.startsWith("https://stitcher.example.pluto.tv/v2/stitch/hls/channel/"))
        assertFalse(channel.toString().contains("private-token"))
        assertEquals("PAW Patrol", catalog.embeddedGuidePrograms.single().title)
        assertEquals("Air Pups", catalog.embeddedGuidePrograms.single().subtitle)
    }
}
