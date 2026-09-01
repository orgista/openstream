package com.orgista.openstream.ui

import com.orgista.openstream.data.MediaCandidate
import com.orgista.openstream.data.MediaItem
import com.orgista.openstream.data.MediaKind
import com.orgista.openstream.data.SourceKind
import com.orgista.openstream.data.StremioStream
import com.orgista.openstream.data.StremioAddon
import com.orgista.openstream.offline.OfflineDecodeSize
import com.orgista.openstream.offline.OfflineDeviceProfile
import com.orgista.openstream.offline.OfflineDynamicRange
import com.orgista.openstream.offline.OfflineMediaProbe
import com.orgista.openstream.offline.OfflineVideoCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlaybackRoutingTest {
    private fun item(candidates: List<MediaCandidate>) = MediaItem(
        id = "northstar",
        kind = MediaKind.MOVIE,
        title = "Northstar",
        synopsis = "",
        year = 2026,
        rating = "PG-13",
        runtimeMinutes = 127,
        candidates = candidates,
    )

    @Test
    fun `preferred request uses the first playable route`() {
        val request = preferredPlaybackRequest(
            item(
                listOf(
                    MediaCandidate(
                        id = "nas-1",
                        sourceName = "ServerPlus",
                        sourceKind = SourceKind.NAS,
                        uri = "smb://server/media/Northstar.mkv",
                        formatLabel = "MKV",
                    ),
                ),
            ),
        )

        assertEquals("Northstar", request?.title)
        assertEquals("ServerPlus", request?.subtitle)
        assertEquals("smb://server/media/Northstar.mkv", request?.uri)
    }

    @Test
    fun `item without a route cannot create a direct request`() {
        assertNull(preferredPlaybackRequest(item(emptyList())))
    }

    @Test
    fun `play availability requires a local route or a real playback addon`() {
        val title = item(emptyList()).copy(imdbId = "tt0133093")
        val watchNext = StremioAddon(
            id = "watch-next",
            manifestId = "community.watch.next",
            name = "Watch Next",
            transportUrl = "https://watch-next.example",
            version = "1.0.0",
            resources = setOf("stream"),
        )
        val torrentio = watchNext.copy(
            id = "torrentio",
            manifestId = "com.stremio.torrentio.addon",
            name = "Torrentio",
        )

        assertEquals(false, hasPotentialPlaybackRoute(title, listOf(watchNext)))
        assertEquals(true, hasPotentialPlaybackRoute(title, listOf(torrentio)))
        assertEquals(true, hasPotentialPlaybackRoute(item(listOf(MediaCandidate(
            "local", "On this device", SourceKind.OFFLINE, "https://stream.test/movie", "1080p",
        ))), emptyList()))
    }

    @Test
    fun `single play action prefers a completed device download over network routes`() {
        val request = bestPlaybackRequest(
            item(
                listOf(
                    MediaCandidate("nas", "Home server", SourceKind.NAS, "smb://server/movie.mkv", "4K"),
                    MediaCandidate(
                        "offline",
                        "On this device",
                        SourceKind.OFFLINE,
                        "https://stream.test/movie.m3u8",
                        "1080p",
                        offlineDownloadId = "download-1",
                    ),
                ),
            ),
        )

        assertEquals("On this device", request?.subtitle)
        assertEquals("download-1", request?.offlineDownloadId)
    }

    @Test
    fun `legacy unverified offline route is quarantined`() {
        val request = bestPlaybackRequest(
            item(
                listOf(
                    MediaCandidate(
                        "offline",
                        "On this device",
                        SourceKind.OFFLINE,
                        "https://stream.test/wrong.m3u8",
                        "1080p",
                        offlineDownloadId = "legacy-download",
                        offlineIdentityVerified = false,
                    ),
                    MediaCandidate("nas", "Home server", SourceKind.NAS, "smb://server/correct.mkv", "4K"),
                ),
            ),
        )

        assertEquals("Home server", request?.subtitle)
    }

    @Test
    fun `single play action chooses the best compatible addon stream for the device`() {
        val profile = OfflineDeviceProfile(
            maxWidth = 1920,
            maxHeight = 1080,
            codecs = setOf(OfflineVideoCodec.AVC),
            dynamicRanges = setOf(OfflineDynamicRange.SDR),
            dolbyAtmos = false,
        )
        val request = bestPlaybackRequest(
            item(emptyList()),
            streams = listOf(
                StremioStream("4K HEVC Dolby Vision", "https://stream.test/4k"),
                StremioStream("1080p H.264", "https://stream.test/1080"),
                StremioStream("720p H.264", "https://stream.test/720"),
            ),
            deviceProfile = profile,
        )

        assertEquals("https://stream.test/1080", request?.uri)
        assertEquals("1080p H.264", request?.subtitle)
    }

    @Test
    fun `single play action skips local route above codec decode capability`() {
        val profile = OfflineDeviceProfile(
            maxWidth = 1920,
            maxHeight = 1080,
            codecs = setOf(OfflineVideoCodec.AVC, OfflineVideoCodec.HEVC),
            dynamicRanges = setOf(OfflineDynamicRange.SDR),
            dolbyAtmos = false,
            maxDecodeWidth = 3840,
            maxDecodeHeight = 2160,
            codecDecodeSizes = mapOf(
                OfflineVideoCodec.AVC to OfflineDecodeSize(3840, 2160),
                OfflineVideoCodec.HEVC to OfflineDecodeSize(1920, 1080),
            ),
        )
        val request = bestPlaybackRequest(
            item(
                listOf(
                    MediaCandidate(
                        "nas-4k",
                        "Home server",
                        SourceKind.NAS,
                        "smb://server/show/Georgie.S01E01.3840x2160.HEVC.mkv",
                        "MKV · 2.5 GB",
                    ),
                    MediaCandidate(
                        "nas-1080",
                        "Home server",
                        SourceKind.NAS,
                        "smb://server/show/Georgie.S01E01.1080p.x264.mkv",
                        "MKV · 650 MB",
                    ),
                ),
            ),
            deviceProfile = profile,
        )

        assertEquals("smb://server/show/Georgie.S01E01.1080p.x264.mkv", request?.uri)
    }

    @Test
    fun `single play action rejects a probed local route when MediaCodec rejects exact format`() {
        val profile = OfflineDeviceProfile(
            maxWidth = 1920,
            maxHeight = 1080,
            codecs = setOf(OfflineVideoCodec.AVC, OfflineVideoCodec.HEVC),
            dynamicRanges = setOf(OfflineDynamicRange.SDR),
            dolbyAtmos = false,
            maxDecodeWidth = 3840,
            maxDecodeHeight = 2160,
            codecDecodeSizes = mapOf(
                OfflineVideoCodec.HEVC to OfflineDecodeSize(3840, 2160),
            ),
        )
        val rejected = MediaCandidate(
            "nas-unknown",
            "Home server",
            SourceKind.NAS,
            "smb://server/show/episode.mkv",
            "MKV",
        )
        val compatible = MediaCandidate(
            "nas-1080",
            "Home server",
            SourceKind.NAS,
            "smb://server/show/episode-1080.mkv",
            "1080p H.264",
        )
        val request = bestPlaybackRequest(
            item(listOf(rejected, compatible)),
            deviceProfile = profile,
            mediaProbe = { candidate ->
                if (candidate.id == rejected.id) {
                    OfflineMediaProbe(
                        videoMimeType = "video/hevc",
                        videoCodecString = "hvc1.1.6.L150.90",
                        videoCodec = OfflineVideoCodec.HEVC,
                        width = 3840,
                        height = 2160,
                        frameRate = null,
                        bitrate = null,
                        bitDepth = 10,
                        dynamicRange = OfflineDynamicRange.SDR,
                        hardwareDecodeSupported = false,
                    )
                } else {
                    null
                }
            },
        )

        assertEquals(compatible.uri, request?.uri)
    }

    @Test
    fun `configured stream routes are deduplicated and bounded for failover`() {
        val request = PlaybackRequest(
            title = "Film",
            subtitle = "Primary",
            uri = "https://stream.test/one",
            fallbackUris = listOf(
                "https://stream.test/one",
                "https://stream.test/two",
                "javascript:bad",
            ) + (3..30).map { "https://stream.test/$it" },
        )

        val routes = playableUris(request)

        assertEquals("https://stream.test/one", routes.first())
        assertEquals("https://stream.test/two", routes[1])
        assertEquals(12, routes.size)
    }

    @Test
    fun `server transcode playback request carries gateway token as headers`() {
        val request = serverTranscodePlaybackRequest(
            item(emptyList()),
            "http://192.168.1.87:8787/api/transcode/media?transcodeId=abc",
            "test-session-token-that-is-long-enough",
        )

        assertEquals("HD Transcode", request.subtitle)
        assertEquals("test-session-token-that-is-long-enough", request.httpRequestHeaders["X-OpenStream-Session"])
        assertEquals(false, request.uri.contains("test-session-token"))
    }

    @Test
    fun `playback request retains episode identity for subtitle addons`() {
        val episode = MediaItem(
            id = "tt7654321:2:4",
            kind = MediaKind.SERIES,
            title = "Episode 4",
            synopsis = "",
            year = 2026,
            rating = "TV-14",
            runtimeMinutes = 52,
            imdbId = "tt7654321",
            candidates = listOf(
                MediaCandidate(
                    id = "episode-route",
                    sourceName = "Home server",
                    sourceKind = SourceKind.NAS,
                    uri = "smb://server/show/S02E04.mkv",
                    formatLabel = "MKV",
                ),
            ),
        )

        val request = bestPlaybackRequest(episode)

        assertEquals("series", request?.stremioType)
        assertEquals("tt7654321:2:4", request?.stremioId)
    }
}
