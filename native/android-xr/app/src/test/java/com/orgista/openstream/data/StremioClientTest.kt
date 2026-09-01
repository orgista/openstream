package com.orgista.openstream.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException

class StremioClientTest {
    private val manifest = """
        {
          "id":"test.catalog",
          "name":"Test Catalog",
          "version":"1.2.3",
          "resources":["catalog", {"name":"meta", "types":["movie"]}, "stream"],
          "catalogs":[
            {"type":"movie","id":"popular","name":"Popular"},
            {"type":"series","id":"search","name":"Search","extra":[{"name":"search","isRequired":true}]}
          ]
        }
    """.trimIndent()

    @Test
    fun `manifest capabilities and usable catalogs are parsed`() {
        val addon = StremioClient.parseManifest("https://addon.example/config/manifest.json", manifest)

        assertEquals("test.catalog", addon.manifestId)
        assertEquals(setOf("catalog", "meta", "stream"), addon.resources)
        assertEquals(listOf("popular", "search"), addon.catalogs.map { it.id })
        assertFalse(addon.catalogs.first().requiresInput)
        assertFalse(addon.catalogs.first().supportsSearch)
        assertTrue(addon.catalogs.last().requiresInput)
        assertTrue(addon.catalogs.last().supportsSearch)
    }

    @Test
    fun `book and other non video catalogs never enter discovery`() {
        val addon = StremioClient.parseManifest(
            "https://addon.example/manifest.json",
            """{
              "id":"mixed.catalog",
              "name":"Mixed Catalog",
              "resources":["catalog"],
              "catalogs":[
                {"type":"book","id":"books","name":"Books"},
                {"type":"other","id":"other","name":"Other"},
                {"type":"movie","id":"movies","name":"Movies"},
                {"type":"series","id":"shows","name":"Shows"}
              ]
            }""".trimIndent(),
        )

        assertEquals(listOf("movie:movies", "series:shows"), addon.catalogs.map { "${it.type}:${it.id}" })
        assertEquals(
            emptyList<MediaItem>(),
            StremioClient.parseCatalog(
                addon,
                """{"metas":[{"id":"book-1","type":"book","name":"A Book"}]}""",
            ),
        )
    }

    @Test
    fun `search selects only declared searchable catalogs`() {
        val addon = StremioClient.parseManifest("https://addon.example/manifest.json", manifest)

        val catalogs = StremioSearchPolicy.catalogsFor(addon)

        assertEquals(listOf("series:search"), catalogs.map { "${it.type}:${it.id}" })
        assertEquals(
            "catalog/series/search/search=Band%20of%20Brothers.json",
            StremioSearchPolicy.requestPath(catalogs.single(), "Band of Brothers"),
        )
    }

    @Test
    fun `configured addon address is reduced to a safe host label`() {
        val label = StremioUrlPolicy.safeLabel("https://addon.example/private-token/config/manifest.json")

        assertEquals("addon.example · private configuration", label)
        assertFalse(label.contains("private-token"))
    }

    @Test
    fun `catalog metas map to browsable media and malformed entries are skipped`() {
        val addon = StremioClient.parseManifest("https://addon.example/manifest.json", manifest)
        val payload = """
            {"metas":[
              {"id":"tt1234567","type":"movie","name":"A Film","description":"Plot","releaseInfo":"2025","poster":"https://img.example/p.jpg","background":"https://img.example/b.jpg","genres":["Drama"],"director":"[]","imdbRating":"7.8"},
              {"id":"missing-name","type":"movie"}
            ]}
        """.trimIndent()

        val items = StremioClient.parseCatalog(addon, payload)

        assertEquals(1, items.size)
        assertEquals("A Film", items.single().title)
        assertEquals("tt1234567", items.single().imdbId)
        assertEquals(listOf("Drama"), items.single().genres)
        assertEquals(null, items.single().director)
        assertEquals("7.8/10", items.single().ratings?.imdb)
    }

    @Test
    fun `series metadata populates ordered playable episode identities`() {
        val addon = StremioClient.parseManifest("https://addon.example/manifest.json", manifest)
        val payload = """
            {"metas":[{
              "id":"tt7654321",
              "type":"series",
              "name":"A Series",
              "releaseInfo":"2024–",
              "videos":[
                {"id":"tt7654321:2:1","title":"Second Season","season":2,"episode":1,"released":"2025-03-02","overview":"Season premiere","thumbnail":"https://img.example/s2e1.jpg"},
                {"id":"tt7654321:1:2","title":"The Follow-up","season":1,"episode":2,"released":"2024-02-01","overview":"Episode two","thumbnail":"https://img.example/s1e2.jpg","runtime":"49 min"},
                {"id":"tt7654321:1:1","title":"The Beginning","season":1,"episode":1,"released":"2024-01-25","overview":"Episode one","thumbnail":"https://img.example/s1e1.jpg"}
              ]
            }]}
        """.trimIndent()

        val series = StremioClient.parseCatalog(addon, payload).single()

        assertEquals(listOf("tt7654321:1:1", "tt7654321:1:2", "tt7654321:2:1"), series.episodes.map { it.id })
        assertEquals("S1 E1 · The Beginning", series.episodes.first().subtitle)
        assertEquals("tt7654321", series.episodes.first().imdbId)
        assertEquals("https://img.example/s1e1.jpg", series.episodes.first().backdropUrl)
        assertEquals(49, series.episodes[1].runtimeMinutes)
        assertEquals("Episode two", series.episodes[1].synopsis)
    }

    @Test
    fun `metadata merge carries remote episodes into an existing series`() {
        val base = MediaItem(
            id = "library-show",
            kind = MediaKind.SERIES,
            title = "A Series",
            synopsis = "Local description",
            year = 2024,
            rating = "TV-14",
            runtimeMinutes = 0,
            imdbId = "tt7654321",
        )
        val remoteEpisode = base.copy(
            id = "tt7654321:1:1",
            subtitle = "S1 E1 · The Beginning",
            synopsis = "Episode one",
            episodes = emptyList(),
        )

        val merged = StremioCatalogMerger.mergeItem(base, base.copy(episodes = listOf(remoteEpisode)))

        assertEquals(listOf("tt7654321:1:1"), merged.episodes.map { it.id })
    }

    @Test
    fun `retry policy covers transient server failures only`() {
        assertTrue(StremioRetryPolicy.shouldRetry(httpCode = 500, attempt = 0))
        assertTrue(StremioRetryPolicy.shouldRetry(httpCode = 429, attempt = 1))
        assertFalse(StremioRetryPolicy.shouldRetry(httpCode = 404, attempt = 0))
        assertFalse(StremioRetryPolicy.shouldRetry(httpCode = 500, attempt = 3))
        assertEquals(250L, StremioRetryPolicy.delayMs(0))
        assertEquals(1_000L, StremioRetryPolicy.delayMs(2))
    }

    @Test
    fun `add-on test probes a usable catalog after validating the manifest`() {
        val addon = StremioClient.parseManifest("https://addon.example/manifest.json", manifest)

        assertEquals("popular", StremioAddonTestPolicy.catalogToProbe(addon)?.id)
        assertTrue(StremioAddonTestPolicy.successMessage(12).contains("12 titles"))
    }

    @Test
    fun `add-on test turns transport failures into actionable copy`() {
        assertEquals(
            "Add-on could not be reached. Check this device's connection and try again.",
            StremioAddonTestPolicy.failureMessage(IOException("raw socket detail")),
        )
    }

    @Test
    fun `stream behavior filename is retained for media identity checks`() {
        val streams = StremioClient.parseStreams(
            """{"streams":[{"title":"1080p HEVC","url":"https://stream.example/file.mkv","behaviorHints":{"filename":"Film.2026.1080p.mkv"}}]}""",
        )

        assertEquals("Film.2026.1080p.mkv", streams.single().filename)
    }

    @Test
    fun `stream parsing keeps late quality alternatives for device selection`() {
        val values = JSONArray()
        repeat(75) { index ->
            values.put(
                JSONObject()
                    .put("title", if (index == 70) "2160p DV P8 HEVC 5 GB" else "1080p H.264 ${index + 1} GB")
                    .put("url", "https://stream.example/${index + 1}.mkv"),
            )
        }

        val streams = StremioClient.parseStreams(JSONObject().put("streams", values).toString())

        assertEquals(75, streams.size)
        assertTrue(streams.any { "DV P8" in it.title })
    }

    @Test
    fun `subtitle responses retain playable tracks and ignore unsafe urls`() {
        val subtitles = StremioClient.parseSubtitles(
            """{
                "subtitles":[
                    {"id":"english-1","url":"https://subs.example/film.srt","lang":"eng"},
                    {"id":"spanish-1","url":"http://subs.example/film.vtt","lang":"spa"},
                    {"id":"unsafe","url":"file:///private/subtitle.srt","lang":"eng"}
                ]
            }""".trimIndent(),
        )

        assertEquals(listOf("english-1", "spanish-1"), subtitles.map { it.id })
        assertEquals(listOf("eng", "spa"), subtitles.map { it.language })
        assertEquals(listOf("application/x-subrip", "text/vtt"), subtitles.map { it.mimeType })
    }

    @Test
    fun `external stream links become typed watch next recommendations`() {
        val recommendations = StremioClient.parseRecommendations(
            """{
                "streams":[
                    {
                        "name":"The Dark Tower",
                        "description":"A related movie",
                        "externalUrl":"stremio:///detail/movie/tt1648190"
                    },
                    {
                        "name":"A Series",
                        "externalUrl":"stremio://detail/series/tt7654321"
                    },
                    {"name":"Playable stream","url":"https://stream.example/movie.mkv"}
                ]
            }""".trimIndent(),
        )

        assertEquals(listOf("tt1648190", "tt7654321"), recommendations.map { it.id })
        assertEquals(listOf("movie", "series"), recommendations.map { it.type })
        assertEquals("A related movie", recommendations.first().description)
    }

    @Test
    fun `merging also removes malformed cached person placeholders`() {
        val malformed = com.orgista.openstream.data.MediaItem(
            id = "tt1",
            kind = MediaKind.MOVIE,
            title = "Film",
            synopsis = "",
            year = 2026,
            rating = "",
            runtimeMinutes = 0,
            director = "[]",
        )

        assertEquals(null, StremioCatalogMerger.mergeItem(malformed, malformed.copy(director = null)).director)
    }

    @Test
    fun `metadata merge keeps existing imdb and adds critic ratings`() {
        val base = MediaItem(
            id = "tt1234567",
            kind = MediaKind.MOVIE,
            title = "Film",
            synopsis = "Plot",
            year = 2025,
            rating = "",
            runtimeMinutes = 0,
            ratings = TitleRatings(imdb = "7.1/10"),
        )
        val enriched = base.copy(
            ratings = TitleRatings(rottenTomatoes = "92%", metacritic = "74/100"),
        )

        val result = StremioCatalogMerger.mergeItem(base, enriched)

        assertEquals("7.1/10", result.ratings?.imdb)
        assertEquals("92%", result.ratings?.rottenTomatoes)
        assertEquals("74/100", result.ratings?.metacritic)
    }

    @Test
    fun `catalog refresh retains richer cached metadata by imdb identity`() {
        val fresh = MediaItem(
            id = "provider-record",
            kind = MediaKind.MOVIE,
            title = "Fresh Title",
            synopsis = "Fresh plot",
            year = 2025,
            rating = "",
            runtimeMinutes = 0,
            imdbId = "tt1234567",
        )
        val cached = fresh.copy(
            id = "tt1234567",
            backdropUrl = "https://images.example/backdrop.jpg",
            cast = listOf("Actor One"),
            tagline = "Cached enrichment",
        )

        val result = StremioCatalogMerger.retainCachedMetadata(listOf(fresh), listOf(cached)).single()

        assertEquals("Fresh Title", result.title)
        assertEquals("https://images.example/backdrop.jpg", result.backdropUrl)
        assertEquals(listOf("Actor One"), result.cast)
        assertEquals("Cached enrichment", result.tagline)
    }

    @Test
    fun `subtitle parsing safely handles unencoded characters and query parameters`() {
        val subtitles = StremioClient.parseSubtitles(
            """{
                "subtitles":[
                    {"id":"sub-vtt-query","url":"https://subs.example/track.vtt?token=123&lang=en","lang":"eng"},
                    {"id":"sub-ass-space","url":"https://subs.example/path with spaces/track.ass#fragment","lang":"jpn"},
                    {"id":"sub-ttml","url":"https://subs.example/captions.ttml","lang":"fra"}
                ]
            }""".trimIndent(),
        )

        assertEquals(3, subtitles.size)
        assertEquals("text/vtt", subtitles[0].mimeType)
        assertEquals("text/x-ssa", subtitles[1].mimeType)
        assertEquals("application/ttml+xml", subtitles[2].mimeType)
    }
}
