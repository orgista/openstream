package com.orgista.openstream.iptv

import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.helpers.DefaultHandler
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.io.SequenceInputStream
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import javax.xml.parsers.SAXParserFactory

object XmlTvParser {
    private const val MAX_PROGRAMS = 24_000

    fun parse(
        input: InputStream,
        channels: List<IptvChannel>,
        windowStartMillis: Long,
        windowEndMillis: Long,
    ): List<IptvGuideProgram> {
        if (channels.isEmpty() || windowEndMillis <= windowStartMillis) return emptyList()
        val factory = SAXParserFactory.newInstance().apply {
            isNamespaceAware = false
            isValidating = false
        }
        listOf(
            "http://apache.org/xml/features/disallow-doctype-decl" to true,
            "http://xml.org/sax/features/external-general-entities" to false,
            "http://xml.org/sax/features/external-parameter-entities" to false,
            "http://apache.org/xml/features/nonvalidating/load-external-dtd" to false,
        ).forEach { (feature, value) -> runCatching { factory.setFeature(feature, value) } }
        val handler = GuideHandler(channels, windowStartMillis, windowEndMillis)
        factory.newSAXParser().parse(InputSource(XmlTvDoctypePolicy.sanitize(input)), handler)
        return handler.programs.sortedWith(compareBy(IptvGuideProgram::channelKey, IptvGuideProgram::startMillis))
    }

    private class GuideHandler(
        private val channels: List<IptvChannel>,
        private val windowStartMillis: Long,
        private val windowEndMillis: Long,
    ) : DefaultHandler() {
        val programs = ArrayList<IptvGuideProgram>()
        private val channelKeys = mutableMapOf<String, String>()
        private val claimedChannelKeys = mutableSetOf<String>()
        private val guideMatcher = IptvGuideMatchPolicy.matcher(channels)
        private var channelId: String? = null
        private val displayNames = mutableListOf<String>()
        private var activeProgram: MutableProgram? = null
        private var textElement: String? = null
        private val text = StringBuilder()

        init {
            channels.filter { it.guideId.isNotBlank() }.forEach { channel ->
                val key = LiveChannelPackagePolicy.channelKey(channel)
                channelKeys[channel.guideId] = key
                channelKeys[channel.guideId.substringBefore('@')] = key
            }
        }

        override fun startElement(uri: String?, localName: String?, qName: String, attributes: Attributes) {
            when (qName.lowercase()) {
                "channel" -> {
                    channelId = attributes.getValue("id")?.take(300)
                    displayNames.clear()
                }
                "programme" -> {
                    if (programs.size >= MAX_PROGRAMS) return
                    val rawChannelId = attributes.getValue("channel").orEmpty()
                    val key = channelKeys[rawChannelId] ?: channelKeys[rawChannelId.substringBefore('@')]
                    val start = parseTime(attributes.getValue("start"))
                    val end = parseTime(attributes.getValue("stop"))
                    activeProgram = if (
                        key != null && start != null && end != null && end > start &&
                        end > windowStartMillis && start < windowEndMillis
                    ) MutableProgram(key, start, end) else null
                }
                "display-name", "title", "sub-title", "desc", "category" -> {
                    textElement = qName.lowercase()
                    text.setLength(0)
                }
            }
        }

        override fun characters(ch: CharArray, start: Int, length: Int) {
            if (textElement != null && text.length < 4_096) text.append(ch, start, minOf(length, 4_096 - text.length))
        }

        override fun endElement(uri: String?, localName: String?, qName: String) {
            val element = qName.lowercase()
            val value = text.toString().trim()
            when (element) {
                "display-name" -> if (channelId != null && value.isNotBlank()) displayNames += value.take(240)
                "channel" -> {
                    channelId?.let { id ->
                        val explicitKey = channelKeys[id] ?: channelKeys[id.substringBefore('@')]
                        if (explicitKey != null) {
                            claimedChannelKeys += explicitKey
                        } else {
                            guideMatcher.channelKey(id, displayNames)
                                ?.takeIf { it !in claimedChannelKeys }
                                ?.let { key ->
                                    channelKeys[id] = key
                                    claimedChannelKeys += key
                                }
                        }
                    }
                    channelId = null
                    displayNames.clear()
                }
                "title" -> activeProgram?.title = value.take(300)
                "sub-title" -> activeProgram?.subtitle = value.take(300)
                "desc" -> activeProgram?.description = value.take(1_500)
                "category" -> if (activeProgram?.category.isNullOrBlank()) activeProgram?.category = value.take(120)
                "programme" -> {
                    activeProgram?.let { program ->
                        if (program.title.isNotBlank() && programs.size < MAX_PROGRAMS) {
                            programs += IptvGuideProgram(
                                channelKey = program.channelKey,
                                title = program.title,
                                subtitle = program.subtitle,
                                description = program.description,
                                category = program.category,
                                startMillis = program.startMillis,
                                endMillis = program.endMillis,
                            )
                        }
                    }
                    activeProgram = null
                }
            }
            if (element == textElement) {
                textElement = null
                text.setLength(0)
            }
        }
    }

    private class MutableProgram(val channelKey: String, val startMillis: Long, val endMillis: Long) {
        var title: String = ""
        var subtitle: String = ""
        var description: String = ""
        var category: String = ""
    }

    private fun parseTime(value: String?): Long? {
        val raw = value?.trim().orEmpty()
        val match = Regex("^(\\d{14})(?:\\s*([+-]\\d{4}|Z))?").find(raw) ?: return null
        return runCatching {
            val local = LocalDateTime.parse(match.groupValues[1], DateTimeFormatter.ofPattern("yyyyMMddHHmmss"))
            val offsetValue = match.groupValues.getOrNull(2).orEmpty()
            if (offsetValue.isBlank()) {
                local.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
            } else {
                val offset = if (offsetValue == "Z") ZoneOffset.UTC else ZoneOffset.of(
                    "${offsetValue.substring(0, 3)}:${offsetValue.substring(3, 5)}",
                )
                OffsetDateTime.of(local, offset).toInstant().toEpochMilli()
            }
        }.getOrNull()
    }
}

/** Removes only XMLTV's inert external DTD declaration; internal subsets remain rejected by SAX. */
object XmlTvDoctypePolicy {
    private const val PREFIX_BYTES = 4_096
    private val safeDeclaration = Regex(
        "(?i)<!DOCTYPE\\s+tv\\s+SYSTEM\\s+(?:\"[^\"]{1,300}\"|'[^']{1,300}')\\s*>",
    )

    fun sanitize(input: InputStream): InputStream {
        val prefix = ByteArray(PREFIX_BYTES)
        val count = input.read(prefix)
        if (count <= 0) return input
        val rawPrefix = prefix.copyOf(count).toString(Charsets.ISO_8859_1)
        val sanitized = safeDeclaration.replace(rawPrefix, "").toByteArray(Charsets.ISO_8859_1)
        return SequenceInputStream(ByteArrayInputStream(sanitized), input)
    }
}
