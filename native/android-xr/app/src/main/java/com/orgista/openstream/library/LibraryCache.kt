package com.orgista.openstream.library

import android.content.Context
import com.orgista.openstream.Logs
import com.orgista.openstream.data.MediaCandidate
import com.orgista.openstream.data.MediaItem
import com.orgista.openstream.data.MediaKind
import com.orgista.openstream.data.NasConnection
import com.orgista.openstream.data.SourceKind
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Persists the last indexed library so its real catalog shows instantly while
 * a background re-scan runs.
 * Only the fields needed to browse and play are cached; rich detail metadata
 * is re-fetched lazily when a title opens.
 */
object LibraryCache {
    /**
     * A valid cache is the startup library. Rewalking a large NAS on every
     * process start duplicates the whole catalog in memory and can collide
     * with video decoder allocation. Explicit source/key changes increment
     * the revision and still request a fresh scan.
     */
    fun shouldScanAfterStartup(cacheAvailable: Boolean, libraryRevision: Int): Boolean =
        !cacheAvailable || libraryRevision > 0

    private fun file(context: Context) = File(context.filesDir, "library-cache.json")

    fun save(context: Context, library: IndexedLibrary) {
        try {
            val json = JSONObject()
                .put("movies", JSONArray(library.movies.map { it.toJson() }))
                .put("shows", JSONArray(library.shows.map { it.toJson() }))
            file(context).writeText(json.toString())
            Logs.event("library cache saved: ${library.movies.size} movies, ${library.shows.size} shows")
        } catch (error: Exception) {
            Logs.warn("library cache save failed", error)
        }
    }

    fun load(context: Context): IndexedLibrary? {
        val cacheFile = file(context)
        if (!cacheFile.exists()) return null
        return try {
            val json = JSONObject(cacheFile.readText())
            val movies = json.optJSONArray("movies").toItems()
            val shows = json.optJSONArray("shows").toItems()
            if (movies.isEmpty() && shows.isEmpty()) null else IndexedLibrary(movies, shows)
        } catch (error: Exception) {
            Logs.warn("library cache load failed", error)
            null
        }
    }

    fun clear(context: Context) {
        runCatching { file(context).delete() }
    }

    private fun JSONArray?.toItems(): List<MediaItem> =
        if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it)?.toMediaItem() }

    private fun MediaItem.toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("kind", kind.name)
        .put("title", title)
        .putOpt("subtitle", subtitle)
        .put("synopsis", synopsis)
        .put("year", year)
        .put("rating", rating)
        .put("runtimeMinutes", runtimeMinutes)
        .putOpt("posterUrl", posterUrl)
        .putOpt("backdropUrl", backdropUrl)
        .putOpt("trailerYoutubeKey", trailerYoutubeKey)
        .putOpt("imdbId", imdbId)
        .putOpt("tmdbId", tmdbId)
        .put("genres", JSONArray(genres))
        .put("cast", JSONArray(cast))
        .putOpt("director", director)
        .putOpt("tagline", tagline)
        .putOpt("ratings", ratings?.let {
            JSONObject()
                .putOpt("imdb", it.imdb)
                .putOpt("rottenTomatoes", it.rottenTomatoes)
                .putOpt("metacritic", it.metacritic)
        })
        .put("candidates", JSONArray(candidates.map { it.toJson() }))
        .put("episodes", JSONArray(episodes.map { it.toJson() }))

    private fun MediaCandidate.toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("sourceName", sourceName)
        .put("sourceKind", sourceKind.name)
        .put("uri", uri)
        .put("formatLabel", formatLabel)
        .put("directPlay", directPlay)

    private fun JSONObject.toMediaItem(): MediaItem = MediaItem(
        id = optString("id"),
        kind = runCatching { MediaKind.valueOf(optString("kind")) }.getOrDefault(MediaKind.MOVIE),
        title = optString("title"),
        subtitle = optString("subtitle").takeIf { it.isNotBlank() },
        synopsis = optString("synopsis"),
        year = optInt("year"),
        rating = optString("rating"),
        runtimeMinutes = optInt("runtimeMinutes"),
        posterUrl = optString("posterUrl").takeIf { it.isNotBlank() },
        backdropUrl = optString("backdropUrl").takeIf { it.isNotBlank() },
        trailerYoutubeKey = optString("trailerYoutubeKey").takeIf { it.isNotBlank() },
        imdbId = optString("imdbId").takeIf { it.isNotBlank() },
        tmdbId = if (has("tmdbId") && !isNull("tmdbId")) optInt("tmdbId") else null,
        genres = optJSONArray("genres").toStrings(),
        cast = optJSONArray("cast").toStrings(),
        director = optString("director").takeIf { it.isNotBlank() },
        tagline = optString("tagline").takeIf { it.isNotBlank() },
        ratings = optJSONObject("ratings")?.let { ratings ->
            com.orgista.openstream.data.TitleRatings(
                imdb = ratings.optString("imdb").takeIf { it.isNotBlank() },
                rottenTomatoes = ratings.optString("rottenTomatoes").takeIf { it.isNotBlank() },
                metacritic = ratings.optString("metacritic").takeIf { it.isNotBlank() },
            )
        },
        candidates = optJSONArray("candidates").toCandidates(),
        episodes = optJSONArray("episodes").toItems(),
    )

    private fun JSONArray?.toCandidates(): List<MediaCandidate> =
        if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it)?.toCandidate() }

    private fun JSONArray?.toStrings(): List<String> =
        if (this == null) emptyList() else (0 until length()).mapNotNull { optString(it).takeIf(String::isNotBlank) }

    private fun JSONObject.toCandidate(): MediaCandidate = MediaCandidate(
        id = optString("id"),
        sourceName = optString("sourceName"),
        sourceKind = runCatching { SourceKind.valueOf(optString("sourceKind")) }.getOrDefault(SourceKind.NAS),
        uri = optString("uri"),
        formatLabel = optString("formatLabel"),
        directPlay = optBoolean("directPlay", true),
    )
}
