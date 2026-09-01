package com.orgista.openstream.iptv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.time.Instant

class XmlTvParserTest {
    private val channel = IptvChannel(
        id = "pbs",
        sourceId = "provider",
        sourceName = "Provider",
        name = "PBS Metro",
        group = "Local",
        logoUrl = "",
        streamUrl = "https://media.example/pbs.m3u8",
        guideId = "pbs.metro.us",
    )

    @Test
    fun `parses only matching programmes in the requested window`() {
        val xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE tv SYSTEM "xmltv.dtd">
            <tv>
              <channel id="pbs.metro.us"><display-name>PBS Metro</display-name></channel>
              <channel id="other.us"><display-name>Other Channel</display-name></channel>
              <programme start="20260812200000 -0500" stop="20260812210000 -0500" channel="pbs.metro.us">
                <title>Nature Now</title><sub-title>River Cities</sub-title>
                <desc>A journey through urban waterways.</desc><category>Documentary</category>
              </programme>
              <programme start="20260812210000 -0500" stop="20260812213000 -0500" channel="other.us">
                <title>Ignore Me</title>
              </programme>
              <programme start="20260813020000 -0500" stop="20260813023000 -0500" channel="pbs.metro.us">
                <title>Outside Window</title>
              </programme>
            </tv>
        """.trimIndent()

        val programs = XmlTvParser.parse(
            input = ByteArrayInputStream(xml.toByteArray()),
            channels = listOf(channel),
            windowStartMillis = Instant.parse("2026-08-13T00:30:00Z").toEpochMilli(),
            windowEndMillis = Instant.parse("2026-08-13T02:00:00Z").toEpochMilli(),
        )

        assertEquals(1, programs.size)
        assertEquals(LiveChannelPackagePolicy.channelKey(channel), programs.single().channelKey)
        assertEquals("Nature Now", programs.single().title)
        assertEquals("River Cities", programs.single().subtitle)
        assertEquals("A journey through urban waterways.", programs.single().description)
        assertEquals("Documentary", programs.single().category)
        assertEquals(Instant.parse("2026-08-13T01:00:00Z").toEpochMilli(), programs.single().startMillis)
        assertEquals(Instant.parse("2026-08-13T02:00:00Z").toEpochMilli(), programs.single().endMillis)
    }

    @Test
    fun `matches provider guide channel by display name when ids differ`() {
        val xml = """
            <tv>
              <channel id="PBS.Metro.HD.us2"><display-name>PBS Metro HD</display-name></channel>
              <programme start="20260812200000 -0500" stop="20260812210000 -0500" channel="PBS.Metro.HD.us2">
                <title>Public Square</title>
              </programme>
            </tv>
        """.trimIndent()

        val programs = XmlTvParser.parse(
            ByteArrayInputStream(xml.toByteArray()),
            listOf(channel.copy(guideId = "unrelated.id")),
            Instant.parse("2026-08-13T00:00:00Z").toEpochMilli(),
            Instant.parse("2026-08-13T03:00:00Z").toEpochMilli(),
        )

        assertEquals("Public Square", programs.single().title)
        assertTrue(programs.single().endMillis > programs.single().startMillis)
    }

    @Test
    fun `one app channel claims only one matching xmltv schedule`() {
        val xml = """
            <tv>
              <channel id="PBS.KIDS.HD.us2"><display-name>PBS Kids HD</display-name></channel>
              <channel id="PBS.Kids.Stream.us2"><display-name>PBS Kids Stream</display-name></channel>
              <programme start="20260812200000 -0500" stop="20260812203000 -0500" channel="PBS.KIDS.HD.us2">
                <title>Correct Schedule</title>
              </programme>
              <programme start="20260812200500 -0500" stop="20260812210000 -0500" channel="PBS.Kids.Stream.us2">
                <title>Duplicate Schedule</title>
              </programme>
            </tv>
        """.trimIndent()
        val kids = channel.copy(id = "kids", name = "PBS Kids", guideId = "")

        val programs = XmlTvParser.parse(
            ByteArrayInputStream(xml.toByteArray()),
            listOf(kids),
            Instant.parse("2026-08-13T00:00:00Z").toEpochMilli(),
            Instant.parse("2026-08-13T03:00:00Z").toEpochMilli(),
        )

        assertEquals(listOf("Correct Schedule"), programs.map(IptvGuideProgram::title))
    }

    @Test(expected = Exception::class)
    fun `rejects doctypes with internal entity subsets`() {
        val xml = """
            <?xml version="1.0"?>
            <!DOCTYPE tv [<!ENTITY unsafe "expanded">]>
            <tv><channel id="pbs.metro.us"><display-name>&unsafe;</display-name></channel></tv>
        """.trimIndent()

        XmlTvParser.parse(
            ByteArrayInputStream(xml.toByteArray()),
            listOf(channel),
            Instant.parse("2026-08-13T00:00:00Z").toEpochMilli(),
            Instant.parse("2026-08-13T03:00:00Z").toEpochMilli(),
        )
    }
}
