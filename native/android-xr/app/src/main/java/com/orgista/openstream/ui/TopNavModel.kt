package com.orgista.openstream.ui

import com.orgista.openstream.data.MediaKind

/** Header destinations are split so the always-visible row stays calm on tablets and TVs. */
enum class TopDestination {
    DISCOVER,
    LIBRARY,
    LIVE,
    SOURCES,
    SETTINGS,
}

object TopNavLayoutPolicy {
    /** Android already renders network and battery status; duplicating it made the app bar noisy. */
    const val showConnectivityTelemetry = false
    const val offlineStatusLabel = "Offline"
    val brandDestination = TopDestination.DISCOVER

    fun isCompact(widthDp: Int, heightDp: Int): Boolean = minOf(widthDp, heightDp) < 600

    /** The wide tab includes a 2dp selection rail; compensate its visual center beside the brand. */
    fun brandBottomPaddingDp(compact: Boolean): Int = if (compact) 0 else 7

    // Brand lockup metrics shared by the top bar and the launch animation, so the
    // launch mark lands exactly where the resident brand lives (below the top inset).
    fun brandStartPaddingDp(compact: Boolean): Int = if (compact) 16 else 26
    fun brandTopOffsetDp(compact: Boolean): Int = if (compact) 14 else 17
    fun brandMarkSizeDp(compact: Boolean): Int = if (compact) 24 else 27
    fun brandGapDp(compact: Boolean): Int = if (compact) 4 else 5
    fun brandWordSp(compact: Boolean): Int = if (compact) 17 else 18
}

/** Lets artwork and scrolling content continue under a soft lower-edge scrim. */
object TopNavBlendPolicy {
    const val FADE_OVERLAP_DP = 28

    fun contentTopInsetPx(navHeightPx: Int, fadeOverlapPx: Int): Int =
        (navHeightPx - fadeOverlapPx).coerceAtLeast(0)
}

fun primaryTopDestinations(): List<TopDestination> = listOf(
    TopDestination.DISCOVER,
    TopDestination.LIBRARY,
    TopDestination.LIVE,
)

fun overflowTopDestinations(kidsMode: Boolean): List<TopDestination> = buildList {
    if (!kidsMode) add(TopDestination.SOURCES)
    add(TopDestination.SETTINGS)
}

fun libraryEmptyTitle(
    hasCatalog: Boolean,
    filter: MediaKind?,
    missingSources: Int,
): String = when {
    hasCatalog && filter == MediaKind.MOVIE -> "No movies"
    hasCatalog && filter == MediaKind.SERIES -> "No series"
    missingSources > 0 -> if (missingSources == 1) "Source unavailable" else "Sources unavailable"
    else -> "No titles"
}

fun libraryHeaderStatus(
    indexing: Boolean,
    hasLibraries: Boolean,
    titleCount: Int,
    metadataEnabled: Boolean,
    /** Added folders whose NAS share is missing; silently indexing nothing reads as an empty library. */
    missingSources: Int = 0,
): String = when {
    indexing -> "Scanning library…"
    !hasLibraries -> "Add a source"
    missingSources > 0 && titleCount == 0 ->
        "Reconnect ${if (missingSources == 1) "the NAS share" else "$missingSources NAS shares"} in Settings → Sources"
    missingSources > 0 -> if (missingSources == 1) {
        "$titleCount titles · 1 source needs reconnecting"
    } else {
        "$titleCount titles · $missingSources sources need reconnecting"
    }
    !metadataEnabled -> "$titleCount titles · artwork needs TMDB"
    else -> "$titleCount titles"
}
