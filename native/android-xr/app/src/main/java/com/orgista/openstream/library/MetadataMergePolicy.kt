package com.orgista.openstream.library

import com.orgista.openstream.data.MediaItem
import com.orgista.openstream.data.TitleRatings
import com.orgista.openstream.domain.normalizedRatingAge

object MetadataMergePolicy {
    fun merge(item: MediaItem, tmdbId: Int?, details: TmdbDetails?, omdb: OmdbResult?): MediaItem {
        fun mergeStrings(existing: List<String>, first: List<String>, second: List<String>): List<String> =
            (existing + first + second).map(String::trim).filter(String::isNotBlank).distinct().take(12)

        val incomingRatings = omdb?.ratings
        val ratings = TitleRatings(
            imdb = incomingRatings?.imdb ?: item.ratings?.imdb,
            rottenTomatoes = incomingRatings?.rottenTomatoes ?: item.ratings?.rottenTomatoes,
            metacritic = incomingRatings?.metacritic ?: item.ratings?.metacritic,
        ).takeIf { it.imdb != null || it.rottenTomatoes != null || it.metacritic != null }

        return item.copy(
            tmdbId = tmdbId ?: item.tmdbId,
            imdbId = details?.imdbId ?: item.imdbId,
            synopsis = item.synopsis.takeUnless { synopsis ->
                synopsis.isBlank() || (synopsis.startsWith("From ") && synopsis.endsWith('.'))
            } ?: details?.overview.orEmpty().ifBlank { item.synopsis },
            year = item.year.takeIf { it > 0 } ?: details?.releaseYear ?: 0,
            rating = item.rating.takeIf { normalizedRatingAge(it) != null }
                ?: details?.certification
                ?: omdb?.rated.orEmpty(),
            runtimeMinutes = item.runtimeMinutes.takeIf { it > 0 }
                ?: details?.runtimeMinutes?.takeIf { it > 0 }
                ?: omdb?.runtimeMinutes?.takeIf { it > 0 }
                ?: 0,
            genres = mergeStrings(item.genres, details?.genres.orEmpty(), omdb?.genres.orEmpty()).take(8),
            cast = mergeStrings(item.cast, details?.cast.orEmpty(), omdb?.actors.orEmpty()),
            director = item.director ?: details?.director ?: omdb?.director,
            tagline = item.tagline ?: details?.tagline,
            posterUrl = item.posterUrl ?: Tmdb.posterUrl(details?.posterPath),
            backdropUrl = item.backdropUrl ?: Tmdb.backdropUrl(details?.backdropPath),
            trailerYoutubeKey = details?.trailerYoutubeKey ?: item.trailerYoutubeKey,
            ratings = ratings,
        )
    }
}
