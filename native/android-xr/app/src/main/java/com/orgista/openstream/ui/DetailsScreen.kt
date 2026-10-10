package com.orgista.openstream.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.net.Uri
import android.provider.Settings
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orgista.openstream.data.MediaItem
import com.orgista.openstream.data.MediaKind
import com.orgista.openstream.data.SourceKind
import com.orgista.openstream.data.StremioAddon
import com.orgista.openstream.data.StremioAddonPresentation
import com.orgista.openstream.data.StremioClient
import com.orgista.openstream.data.StremioCatalogMerger
import com.orgista.openstream.data.StremioStream
import com.orgista.openstream.Logs
import com.orgista.openstream.arr.ArrConnection
import com.orgista.openstream.arr.ArrDownloadClient
import com.orgista.openstream.arr.ArrDownloadDestination
import com.orgista.openstream.arr.ArrDownloadTarget
import com.orgista.openstream.arr.ArrKind
import com.orgista.openstream.arr.ArrPendingDownloadPolicy
import com.orgista.openstream.arr.ArrPendingDownloadStore
import com.orgista.openstream.arr.PendingArrDownload
import com.orgista.openstream.arr.ArrStore
import com.orgista.openstream.transcode.TranscodeServerClient
import com.orgista.openstream.transcode.TranscodeServerStore
import com.orgista.openstream.domain.TitlePreferenceStore
import com.orgista.openstream.domain.TitleRating
import com.orgista.openstream.streaming.BandwidthRuntime
import com.orgista.openstream.offline.OfflineMediaRuntime
import com.orgista.openstream.offline.OfflineDeviceCapabilities
import com.orgista.openstream.offline.OfflineMediaProbeCache
import com.orgista.openstream.offline.OfflineDownloadUiPolicy
import com.orgista.openstream.offline.OfflineDownloadVisual
import com.orgista.openstream.offline.OfflineProgressPolicy
import com.orgista.openstream.player.PlaybackStore
import com.orgista.openstream.player.SeriesPlaybackAction
import com.orgista.openstream.player.SeriesPlaybackPolicy
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.offline.Download
import com.orgista.openstream.ui.icons.AppIcons
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val episodeLabelPattern = Regex("(?i)^S(\\d{1,3})\\s*E(\\d{1,4})")
private val stremioEpisodeIdPattern = Regex("tt\\d{5,12}:\\d{1,3}:\\d{1,4}")

private fun MediaItem.episodeSeason(): Int? = subtitle
    ?.let(episodeLabelPattern::find)
    ?.groupValues?.get(1)?.toIntOrNull()

private fun MediaItem.episodeNumber(): Int? = subtitle
    ?.let(episodeLabelPattern::find)
    ?.groupValues?.get(2)?.toIntOrNull()

private fun MediaItem.streamIdentity(): String? =
    id.takeIf(stremioEpisodeIdPattern::matches) ?: imdbId

private fun incompatibleLocalRouteMessage(target: MediaItem, localRequest: PlaybackRequest?): String? {
    val hasLocalCandidate = target.candidates.any { candidate ->
        (candidate.sourceKind == SourceKind.NAS || candidate.sourceKind == SourceKind.OFFLINE) &&
            playableUris(PlaybackRequest(target.title, candidate.sourceName, candidate.uri)).isNotEmpty()
    }
    return if (hasLocalCandidate && localRequest == null) {
        "A local copy exists, but this device should not play that version smoothly. Add a compatible 1080p/H.264 or supported HEVC copy, or connect another stream source for this title."
    } else {
        null
    }
}

private tailrec fun Context.detailsActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.detailsActivity()
    else -> null
}

private fun requestDownloadNotificationPermission(context: Context) {
    if (Build.VERSION.SDK_INT >= 33 &&
        context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
    ) {
        context.detailsActivity()?.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4701)
    }
}

private data class DownloadDestinationChoice(
    val connection: ArrConnection,
    val serverTarget: ArrDownloadTarget,
    val localTarget: MediaItem? = null,
    val localSeasonNumber: Int? = null,
    val submittingIds: Set<String>,
    val label: String,
)

@OptIn(UnstableApi::class)
@Composable
fun DetailsScreen(
    item: MediaItem,
    kidsMode: Boolean,
    addons: List<StremioAddon>,
    offlineRuntime: OfflineMediaRuntime,
    playbackStore: PlaybackStore,
    online: Boolean,
    metadataLoader: com.orgista.openstream.library.MetadataLoader,
    mediaProbeCache: OfflineMediaProbeCache,
    mediaProbeRevision: Int = 0,
    onMediaProbeChanged: () -> Unit = {},
    initialPlaybackSourceUnavailable: Boolean = false,
    onMetadataEnriched: (MediaItem) -> Unit = {},
    onBack: () -> Unit,
    onOpenSources: () -> Unit,
    onPlay: (PlaybackRequest) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var searching by remember { mutableStateOf(false) }
    var offlinePreparingIds by remember(item.id) { mutableStateOf(emptySet<String>()) }
    var serverSubmittingIds by remember(item.id) { mutableStateOf(emptySet<String>()) }
    var destinationChoice by remember(item.id) { mutableStateOf<DownloadDestinationChoice?>(null) }
    var playbackSourceUnavailable by remember(item.id, initialPlaybackSourceUnavailable) {
        mutableStateOf(initialPlaybackSourceUnavailable)
    }
    var playbackUnavailableMessage by remember(item.id) { mutableStateOf<String?>(null) }
    val offlineEntries by offlineRuntime.entries.collectAsState()
    val arrStore = remember { ArrStore(context.applicationContext) }
    val transcodeServerStore = remember { TranscodeServerStore(context.applicationContext) }
    val pendingArrStore = remember { ArrPendingDownloadStore(context.applicationContext) }
    val radarr = remember(item.id) { arrStore.load(ArrKind.RADARR)?.takeIf(ArrConnection::enabled) }
    val sonarr = remember(item.id) { arrStore.load(ArrKind.SONARR)?.takeIf(ArrConnection::enabled) }
    val arrDownloadDestination = remember(item.id) { arrStore.downloadDestination }
    val deviceProfile = remember { OfflineDeviceCapabilities.inspect(context.applicationContext) }
    val mediaProbeResolver: (com.orgista.openstream.data.MediaCandidate) -> com.orgista.openstream.offline.OfflineMediaProbe? = remember(
        mediaProbeCache,
        mediaProbeRevision,
    ) {
        { candidate -> mediaProbeCache.get(candidate.uri) }
    }
    val preferenceStore = remember { TitlePreferenceStore(context.applicationContext) }
    var titleRating by remember(item.id) { mutableStateOf(preferenceStore.rating(item.id)) }
    var streamSearchLabel by remember { mutableStateOf("Finding best stream…") }

    // Lazily fetch full metadata (genres, cast, RT/IMDb/Metacritic) for this
    // one title when the screen opens — keeps the library scan fast.
    var enriched by remember(item.id) { mutableStateOf(item) }
    var metadataLoading by remember(item.id) {
        mutableStateOf(online && (metadataLoader.active || addons.any { "meta" in it.resources }))
    }
    androidx.compose.runtime.LaunchedEffect(item.id) {
        var result = item
        if (online && metadataLoader.active) {
            runCatching { metadataLoader.enrich(result) }.getOrNull()?.let { result = it }
        }
        val metaId = result.imdbId ?: result.id.takeIf { it.startsWith("tt") }
        if (online && metaId != null) {
            val type = if (result.kind == MediaKind.SERIES) "series" else "movie"
            val remoteMeta = withContext(Dispatchers.IO) {
                addons.asSequence()
                    .filter { "meta" in it.resources }
                    .mapNotNull { addon -> runCatching { StremioClient.metaFor(addon, type, metaId) }.getOrNull() }
                    .firstOrNull()
            }
            if (remoteMeta != null) result = StremioCatalogMerger.mergeItem(result, remoteMeta)
        }
        enriched = result
        onMetadataEnriched(result)
        metadataLoading = false
    }
    val item = enriched
    val configuration = LocalConfiguration.current
    val connectivityManager = remember {
        context.getSystemService(ConnectivityManager::class.java)
    }
    val meteredNetwork = remember(online) {
        connectivityManager?.isActiveNetworkMetered ?: true
    }
    val motionAllowed = remember {
        Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) > 0f
    }
    var trailerUnavailable by remember(item.id, item.trailerYoutubeKey) { mutableStateOf(false) }
    var trailerPlaying by remember(item.id, item.trailerYoutubeKey) { mutableStateOf(false) }
    val showTrailer = TrailerPreviewPolicy.shouldAutoplay(
        youtubeKey = item.trailerYoutubeKey,
        online = online,
        metered = meteredNetwork,
        stageVisible = true,
        motionAllowed = motionAllowed,
    ) && !trailerUnavailable
    val revealTrailer = TrailerPreviewPolicy.shouldRevealPlayer(
        started = trailerPlaying,
        unavailable = trailerUnavailable,
    )
    androidx.compose.runtime.LaunchedEffect(showTrailer, trailerPlaying) {
        if (showTrailer && !trailerPlaying) {
            delay(TrailerPreviewPolicy.START_TIMEOUT_MS)
            if (!trailerPlaying) trailerUnavailable = true
        }
    }
    val streamAddons = addons.filter(StremioAddonPresentation::isPlaybackProvider)
    val seriesDecision = remember(item.id, item.episodes) {
        val ids = item.episodes.map(MediaItem::id)
        SeriesPlaybackPolicy.select(
            episodes = item.episodes,
            history = playbackStore.viewingSignals(ids),
            resumableIds = ids.filterTo(LinkedHashSet()) { playbackStore.load(it) != null },
        )
    }
    val seasons = remember(item.id, item.episodes) {
        item.episodes.mapNotNull(MediaItem::episodeSeason).distinct().sorted()
    }
    val defaultSeason = seriesDecision?.episode?.episodeSeason()
        ?: seasons.firstOrNull { it > 0 }
        ?: seasons.firstOrNull()
    var selectedSeason by remember(item.id, seasons) { mutableStateOf(defaultSeason) }
    val visibleEpisodes = remember(item.episodes, selectedSeason) {
        if (selectedSeason == null) item.episodes else item.episodes.filter { it.episodeSeason() == selectedSeason }
    }
    var seasonMenuOpen by remember(item.id) { mutableStateOf(false) }

    suspend fun resolveStreams(target: MediaItem): List<StremioStream> {
        val streamId = target.streamIdentity() ?: return emptyList()
        val type = if (target.kind == MediaKind.SERIES) "series" else "movie"
        return withContext(Dispatchers.IO) {
            // Query every stream add-on concurrently; add-on order is preserved
            // and a single add-on failure still yields the others' streams.
            coroutineScope {
                streamAddons.map { addon ->
                    async {
                        runCatching { StremioClient.streamsFor(addon, type, streamId) }.getOrDefault(emptyList())
                    }
                }.flatMap { it.await() }
            }.distinctBy { it.url }
        }
    }

    fun canResolveStream(target: MediaItem): Boolean =
        streamAddons.isNotEmpty() && target.streamIdentity() != null

    suspend fun serverTranscodeRequest(target: MediaItem): PlaybackRequest? {
        val config = transcodeServerStore.load()?.takeIf { it.enabled } ?: return null
        val candidate = bestServerTranscodeCandidate(target, deviceProfile, mediaProbeResolver) ?: return null
        streamSearchLabel = "Starting server transcode…"
        return withContext(Dispatchers.IO) {
            runCatching {
                TranscodeServerClient.startSmbSession(config, candidate.uri, deviceProfile)
            }
        }.onFailure { error ->
            Logs.warn("server transcode could not start for ${target.title}", error)
        }.getOrNull()?.let { transcodeUrl ->
            serverTranscodePlaybackRequest(target, transcodeUrl, config.sessionToken)
        }
    }

    fun playTarget(target: MediaItem) {
        if (searching) return
        searching = true
        scope.launch {
            playbackSourceUnavailable = false
            playbackUnavailableMessage = null
            val hasUnprobedLocal = target.candidates.any { candidate ->
                (candidate.sourceKind == SourceKind.NAS || candidate.sourceKind == SourceKind.OFFLINE) &&
                    mediaProbeCache.get(candidate.uri) == null
            }
            if (hasUnprobedLocal) {
                streamSearchLabel = "Checking local format…"
                runCatching {
                    probeLocalCandidates(context.applicationContext, mediaProbeCache, target)
                }.onSuccess { count ->
                    if (count > 0) onMediaProbeChanged()
                }.onFailure { error ->
                    Logs.warn("local media probe failed for ${target.title}", error)
                }
            }
            val localRequest = bestPlaybackRequest(
                target,
                deviceProfile = deviceProfile,
                mediaProbe = mediaProbeResolver,
            )
            val localIncompatibleMessage = incompatibleLocalRouteMessage(target, localRequest)
            if (localRequest != null) {
                searching = false
                onPlay(localRequest)
                return@launch
            }
            serverTranscodeRequest(target)?.let { request ->
                searching = false
                onPlay(request)
                return@launch
            }
            if (!canResolveStream(target)) {
                searching = false
                playbackUnavailableMessage = localIncompatibleMessage
                playbackSourceUnavailable = true
                return@launch
            }
            streamSearchLabel = "Finding best stream…"
            val found = resolveStreams(target)
            if (found.isEmpty()) {
                searching = false
                playbackUnavailableMessage = localIncompatibleMessage
                Logs.warn(
                    "no direct playback route for ${target.title}: " +
                        "${streamAddons.size} stream add-on(s), 0 direct result(s)",
                )
                playbackSourceUnavailable = true
                return@launch
            }
            streamSearchLabel = "Optimizing for your network…"
            val bandwidth = runCatching {
                BandwidthRuntime.forPlayback(context.applicationContext)
            }.getOrNull()
            searching = false
            Logs.event(
                "stream selection capabilities: display=${deviceProfile.maxWidth}x${deviceProfile.maxHeight}," +
                    "decode=${deviceProfile.maxDecodeWidth}x${deviceProfile.maxDecodeHeight}," +
                    "ranges=${deviceProfile.dynamicRanges.joinToString("|")}," +
                    "dvProfiles=${deviceProfile.dolbyVisionProfiles.sorted().joinToString("|")}",
            )
            val request = bestPlaybackRequest(target, found, deviceProfile, bandwidth?.mbps, mediaProbeResolver)
            if (request == null) {
                playbackUnavailableMessage = localIncompatibleMessage
                Logs.warn(
                    "no direct playback route for ${target.title}: " +
                        "${streamAddons.size} stream add-on(s), ${found.size} direct result(s)",
                )
                playbackSourceUnavailable = true
            } else {
                onPlay(request)
            }
        }
    }

    suspend fun offlineStreams(target: MediaItem): List<StremioStream> {
        val direct = target.candidates.mapNotNull { candidate ->
            candidate.uri.takeIf { it.startsWith("https://") || it.startsWith("http://") || it.startsWith("smb://") }
                ?.let {
                    StremioStream(
                        "${candidate.formatLabel} · ${candidate.sourceName}",
                        it,
                        filename = Uri.parse(it).lastPathSegment,
                    )
                }
        }
        val remote = if (online && !kidsMode && streamAddons.isNotEmpty()) resolveStreams(target) else emptyList()
        return (direct + remote).distinctBy { it.url }
    }

    fun offlineEntry(target: MediaItem) = offlineEntries.firstOrNull { it.item.id == target.id }

    fun offlineCompleted(target: MediaItem): Boolean =
        offlineEntry(target)?.let { it.completed && it.identityVerified } == true

    fun offlineActive(target: MediaItem): Boolean = offlineEntry(target)?.state in setOf(
        Download.STATE_DOWNLOADING,
        Download.STATE_QUEUED,
        Download.STATE_RESTARTING,
        Download.STATE_REMOVING,
    )

    suspend fun enqueueOfflineTarget(target: MediaItem) = offlineEntry(target).let { existing ->
        val routes = offlineStreams(target)
        if (existing?.completed == true && !existing.identityVerified) {
            offlineRuntime.replace(target, existing.downloadId, routes)
        } else {
            offlineRuntime.enqueue(target, routes)
        }
    }

    fun downloadTarget(target: MediaItem) {
        val preparing = target.id in offlinePreparingIds
        if (!OfflineDownloadUiPolicy.canQueue(
                completed = offlineCompleted(target),
                active = offlineActive(target),
                preparing = preparing,
            )
        ) return
        requestDownloadNotificationPermission(context)
        offlinePreparingIds = offlinePreparingIds + target.id
        scope.launch {
            val result = runCatching { enqueueOfflineTarget(target) }
            offlinePreparingIds = offlinePreparingIds - target.id
            result.onSuccess { selected ->
                Logs.event("offline download queued: ${target.title} (${selected.qualityLabel})")
                Toast.makeText(context, "Downloading ${selected.qualityLabel} to this device", Toast.LENGTH_LONG).show()
            }.onFailure { failure ->
                Logs.warn("offline download could not start for ${target.title}")
                Toast.makeText(
                    context,
                    failure.message ?: "The offline download could not start",
                    Toast.LENGTH_LONG,
                ).show()
            }
        }
    }

    fun downloadSeason(season: Int) {
        val episodes = item.episodes.filter { it.episodeSeason() == season }
        val targets = episodes.filter { episode ->
            OfflineDownloadUiPolicy.canQueue(
                completed = offlineCompleted(episode),
                active = offlineActive(episode),
                preparing = episode.id in offlinePreparingIds,
            )
        }
        if (targets.isEmpty()) {
            Toast.makeText(context, "Season $season is already downloaded or queued", Toast.LENGTH_SHORT).show()
            return
        }
        requestDownloadNotificationPermission(context)
        val targetIds = targets.mapTo(LinkedHashSet(), MediaItem::id)
        offlinePreparingIds = offlinePreparingIds + targetIds
        scope.launch {
            var queued = 0
            var firstFailure: String? = null
            targets.forEach { episode ->
                runCatching { enqueueOfflineTarget(episode) }
                    .onSuccess { queued++ }
                    .onFailure { if (firstFailure == null) firstFailure = it.message }
            }
            offlinePreparingIds = offlinePreparingIds - targetIds
            val message = when {
                queued > 0 -> "$queued episode${if (queued == 1) "" else "s"} queued for Season $season"
                firstFailure != null -> firstFailure
                else -> "Season $season is already downloaded or queued"
            }
            Toast.makeText(context, message, Toast.LENGTH_LONG).show()
        }
    }

    fun configuredArr(): ArrConnection? = when (item.kind) {
        MediaKind.MOVIE -> radarr
        MediaKind.SERIES -> sonarr
        MediaKind.VIDEO -> null
    }

    fun submitToServer(choice: DownloadDestinationChoice) {
        destinationChoice = null
        fun saveForRetry() {
            pendingArrStore.add(
                PendingArrDownload(
                    kind = choice.connection.kind,
                    target = choice.serverTarget,
                    queuedAtEpochMillis = System.currentTimeMillis(),
                ),
            )
            Toast.makeText(
                context,
                "Saved. OpenStream will send it to ${choice.connection.kind.displayName} when the server is reachable.",
                Toast.LENGTH_LONG,
            ).show()
        }
        if (!online) {
            saveForRetry()
            return
        }
        serverSubmittingIds = serverSubmittingIds + choice.submittingIds
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ArrDownloadClient.enqueue(choice.connection, choice.serverTarget) }
            }
            serverSubmittingIds = serverSubmittingIds - choice.submittingIds
            result.onSuccess { queued ->
                Logs.event("ARR search submitted: ${choice.connection.kind.displayName} · ${choice.label}")
                Toast.makeText(context, queued.message, Toast.LENGTH_LONG).show()
            }.onFailure { failure ->
                Logs.warn("ARR search could not start: ${choice.connection.kind.displayName} · ${choice.label}")
                if (ArrPendingDownloadPolicy.shouldQueue(failure)) {
                    saveForRetry()
                } else {
                    Toast.makeText(
                        context,
                        failure.message ?: "${choice.connection.kind.displayName} could not start the download",
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }
        }
    }

    fun applyDownloadDestination(choice: DownloadDestinationChoice) {
        when (arrDownloadDestination) {
            ArrDownloadDestination.ASK -> destinationChoice = choice
            ArrDownloadDestination.DEVICE -> choice.localSeasonNumber?.let(::downloadSeason)
                ?: choice.localTarget?.let(::downloadTarget)
            ArrDownloadDestination.SERVER -> submitToServer(choice)
        }
    }

    fun requestTargetDownload(target: MediaItem) {
        if (!OfflineDownloadUiPolicy.canQueue(
                completed = offlineCompleted(target),
                active = offlineActive(target),
                preparing = target.id in offlinePreparingIds || target.id in serverSubmittingIds,
            )
        ) return
        val connection = configuredArr()
        if (connection == null) {
            downloadTarget(target)
            return
        }
        val season = target.episodeSeason()
        val episode = target.episodeNumber()
        applyDownloadDestination(DownloadDestinationChoice(
            connection = connection,
            serverTarget = ArrDownloadTarget(
                title = item.title,
                year = item.year,
                tmdbId = item.tmdbId,
                imdbId = item.imdbId,
                seasonNumber = season,
                episodeNumber = episode,
            ),
            localTarget = target,
            submittingIds = setOf(target.id),
            label = if (season != null && episode != null) {
                "${item.title} · Season $season Episode $episode"
            } else {
                item.title
            },
        ))
    }

    fun requestSeasonDownload(season: Int) {
        val episodes = item.episodes.filter { it.episodeSeason() == season }
        val ids = episodes.filterNot(::offlineCompleted).mapTo(LinkedHashSet(), MediaItem::id)
        if (ids.isEmpty()) {
            Toast.makeText(context, "Season $season is already downloaded", Toast.LENGTH_SHORT).show()
            return
        }
        val connection = configuredArr()
        if (connection == null) {
            downloadSeason(season)
            return
        }
        applyDownloadDestination(DownloadDestinationChoice(
            connection = connection,
            serverTarget = ArrDownloadTarget(
                title = item.title,
                year = item.year,
                tmdbId = item.tmdbId,
                imdbId = item.imdbId,
                seasonNumber = season,
            ),
            localSeasonNumber = season,
            submittingIds = ids,
            label = "${item.title} · Season $season",
        ))
    }

    destinationChoice?.let { choice ->
        AlertDialog(
            onDismissRequest = { destinationChoice = null },
            containerColor = OpenStreamColors.SurfaceRaised,
            titleContentColor = OpenStreamColors.Text,
            textContentColor = OpenStreamColors.TextSoft,
            title = { Text("Download to") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Where should ${choice.label} be made available?")
                    DownloadDestinationOption(
                        title = "Download to this Device",
                        detail = "Save an optimized offline copy",
                    ) {
                        destinationChoice = null
                        choice.localSeasonNumber?.let(::downloadSeason)
                            ?: choice.localTarget?.let(::downloadTarget)
                    }
                    DownloadDestinationOption(
                        title = "Send to ${choice.connection.kind.displayName}",
                        detail = "Download the strongest available quality to your server",
                    ) { submitToServer(choice) }
                }
            },
            confirmButton = {
                OpenStreamTextButton(onClick = { destinationChoice = null }) {
                    Text("Cancel", color = OpenStreamColors.TextSoft)
                }
            },
        )
    }

    if (playbackSourceUnavailable) {
        val localIncompatible = playbackUnavailableMessage != null
        AlertDialog(
            onDismissRequest = { playbackSourceUnavailable = false },
            containerColor = OpenStreamColors.SurfaceRaised,
            titleContentColor = OpenStreamColors.Text,
            textContentColor = OpenStreamColors.TextSoft,
            title = { Text(if (localIncompatible) "Source not compatible" else "No playable source") },
            text = {
                Text(
                    playbackUnavailableMessage
                        ?: "This title is in your catalog, but none of your connected sources returned a video.",
                )
            },
            confirmButton = {
                OpenStreamTextButton(
                    onClick = {
                        playbackSourceUnavailable = false
                        onOpenSources()
                    },
                ) {
                    Text("Manage Sources", color = OpenStreamColors.Accent)
                }
            },
            dismissButton = {
                OpenStreamTextButton(onClick = { playbackSourceUnavailable = false }) {
                    Text("Close", color = OpenStreamColors.TextSoft)
                }
            },
        )
    }

    val effectiveSeason = selectedSeason ?: seasons.firstOrNull()
    val selectedSeasonEpisodes = effectiveSeason?.let { season ->
        item.episodes.filter { it.episodeSeason() == season }
    }.orEmpty()
    val selectedSeasonCompleted = selectedSeasonEpisodes.isNotEmpty() &&
        selectedSeasonEpisodes.all(::offlineCompleted)
    val selectedSeasonActive = selectedSeasonEpisodes.any(::offlineActive)
    val selectedSeasonPreparing = selectedSeasonEpisodes.any {
        it.id in offlinePreparingIds || it.id in serverSubmittingIds
    }
    val decisionEpisode = seriesDecision?.episode
    val playbackItem = decisionEpisode?.takeIf { it.episodeSeason() == effectiveSeason }
        ?: visibleEpisodes.firstOrNull()
        ?: decisionEpisode
        ?: item
    val playbackAction = seriesDecision?.action.takeIf { decisionEpisode?.id == playbackItem.id }
    val localRequest = bestPlaybackRequest(
        playbackItem,
        deviceProfile = deviceProfile,
        mediaProbe = mediaProbeResolver,
    )
    val episodeLabel = playbackItem.subtitle?.substringBefore('·')?.trim()
    val playLabel = when (playbackAction) {
        SeriesPlaybackAction.RESUME -> "Resume ${episodeLabel.orEmpty()}".trim()
        SeriesPlaybackAction.NEXT -> "Play next · ${episodeLabel.orEmpty()}".trimEnd(' ', '·')
        SeriesPlaybackAction.REPLAY -> "Replay ${episodeLabel.orEmpty()}".trim()
        SeriesPlaybackAction.FIRST,
        SeriesPlaybackAction.CONTINUE,
        -> episodeLabel?.let { "Play $it" } ?: "Play"
        null -> "Play"
    }
    val playbackCanResolve = canResolveStream(playbackItem)
    val expandedDetailsOverlay = ArtworkPresentationPolicy.usesExpandedDetailsOverlay(
        widthDp = configuration.screenWidthDp.toFloat(),
        heightDp = configuration.screenHeightDp.toFloat(),
    )
    val showDetailsOverlay = TrailerPreviewPolicy.shouldShowDetailsOverlay(
        expandedLayout = expandedDetailsOverlay,
        trailerVisible = revealTrailer,
    )

    val detailsInformation: @Composable (Boolean) -> Unit = { overArtwork ->
        Column(verticalArrangement = Arrangement.spacedBy(if (overArtwork) 7.dp else 12.dp)) {
            item.tagline?.let { tagline ->
                Text(
                    tagline,
                    color = if (overArtwork) Color.White.copy(alpha = 0.78f) else OpenStreamColors.Muted,
                    fontSize = 15.sp,
                    fontStyle = androidx.compose.ui.text.font.FontStyle.Italic,
                    maxLines = if (overArtwork) 1 else Int.MAX_VALUE,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (metadataLoading) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(9.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    OpenStreamLoadingIndicator(role = LoadingIndicatorRole.INLINE)
                    Text(
                        "Loading artwork and details",
                        color = if (overArtwork) Color.White.copy(alpha = 0.84f) else OpenStreamColors.TextSoft,
                        fontSize = 13.sp,
                    )
                }
            }
            item.ratings?.let { ratings ->
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    ratings.rottenTomatoes?.let { ScoreBadge("🍅", it, OpenStreamColors.Coral) }
                    ratings.imdb?.let { ScoreBadge("IMDb", it, OpenStreamColors.Accent) }
                    ratings.metacritic?.let { ScoreBadge("Metacritic", it, OpenStreamColors.TextSoft) }
                }
            }
            if (item.genres.isNotEmpty()) {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    item.genres.take(4).forEach { genre ->
                        Surface(
                            shape = OpenStreamShapes.Tag,
                            color = if (overArtwork) Color.Black.copy(alpha = 0.58f) else OpenStreamColors.SurfaceRaised,
                            border = if (overArtwork) BorderStroke(1.dp, Color.White.copy(alpha = 0.16f)) else null,
                        ) {
                            Text(
                                genre,
                                Modifier.padding(horizontal = 12.dp, vertical = 5.dp),
                                fontSize = 12.sp,
                                color = if (overArtwork) Color.White.copy(alpha = 0.90f) else OpenStreamColors.TextSoft,
                            )
                        }
                    }
                }
            }
            item.subtitle?.let { subtitle ->
                val isCatalogName = addons.any { addon -> addon.name.equals(subtitle, ignoreCase = true) }
                Text(
                    if (isCatalogName) "Stream" else subtitle,
                    color = if (overArtwork) Color.White.copy(alpha = 0.70f) else OpenStreamColors.Muted,
                    fontSize = 14.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (item.synopsis.isNotBlank()) {
                Text(
                    item.synopsis,
                    fontSize = 16.sp,
                    lineHeight = 23.sp,
                    color = if (overArtwork) Color.White.copy(alpha = 0.92f) else OpenStreamColors.TextSoft,
                    maxLines = if (overArtwork) 3 else Int.MAX_VALUE,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            item.director?.let { director ->
                Text(
                    "Director  $director",
                    fontSize = 13.sp,
                    color = if (overArtwork) Color.White.copy(alpha = 0.68f) else OpenStreamColors.Muted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (item.cast.isNotEmpty()) {
                Text(
                    "Cast  ${item.cast.take(5).joinToString(", ")}",
                    fontSize = 13.sp,
                    color = if (overArtwork) Color.White.copy(alpha = 0.68f) else OpenStreamColors.Muted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }

    val detailsActions: @Composable (Boolean) -> Unit = { overArtwork ->
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ActionButton(
                    if (searching) streamSearchLabel else playLabel,
                    icon = AppIcons.Play,
                    enabled = !searching && (localRequest != null || playbackCanResolve),
                ) {
                    playTarget(playbackItem)
                }
                if (seasons.isNotEmpty() && effectiveSeason != null) {
                    Box {
                        Surface(
                            onClick = { seasonMenuOpen = true },
                            shape = OpenStreamShapes.Control,
                            color = if (overArtwork) Color.Black.copy(alpha = 0.68f) else OpenStreamColors.SurfaceRaised,
                            border = BorderStroke(
                                1.dp,
                                if (overArtwork) Color.White.copy(alpha = 0.28f) else OpenStreamColors.Border,
                            ),
                        ) {
                            Text(
                                "Season $effectiveSeason",
                                modifier = Modifier.padding(horizontal = 15.dp, vertical = 12.dp),
                                color = Color.White,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                        DropdownMenu(
                            expanded = seasonMenuOpen,
                            onDismissRequest = { seasonMenuOpen = false },
                            containerColor = OpenStreamColors.SurfaceRaised,
                        ) {
                            seasons.forEach { season ->
                                DropdownMenuItem(
                                    text = { Text("Season $season", color = OpenStreamColors.Text) },
                                    onClick = {
                                        selectedSeason = season
                                        seasonMenuOpen = false
                                    },
                                )
                            }
                        }
                    }
                    OfflineActionButton(
                        completed = selectedSeasonCompleted,
                        active = selectedSeasonActive,
                        preparing = selectedSeasonPreparing,
                        contentDescription = if (selectedSeasonCompleted) {
                            "Season $effectiveSeason downloaded"
                        } else {
                            "Download Season $effectiveSeason"
                        },
                    ) { requestSeasonDownload(effectiveSeason) }
                } else {
                    val completed = offlineCompleted(item)
                    OfflineActionButton(
                        completed = completed,
                        active = offlineActive(item),
                        preparing = item.id in offlinePreparingIds || item.id in serverSubmittingIds,
                        contentDescription = if (completed) "Downloaded" else "Download",
                    ) { requestTargetDownload(item) }
                }
                IconActionButton(
                    icon = AppIcons.ThumbUp,
                    contentDescription = "Like",
                    selected = titleRating == TitleRating.UP,
                ) {
                    titleRating = preferenceStore.toggle(item.id, TitleRating.UP)
                }
                IconActionButton(
                    icon = AppIcons.ThumbDown,
                    contentDescription = "Dislike",
                    selected = titleRating == TitleRating.DOWN,
                ) {
                    titleRating = preferenceStore.toggle(item.id, TitleRating.DOWN)
                }
            }
            val storageStats = remember(offlineEntries, offlinePreparingIds) { offlineRuntime.storageStats() }
            Text(
                "${OfflineProgressPolicy.formatBytes(storageStats.availableBytes)} free on this device" +
                    if (storageStats.downloadedBytes > 0L) {
                        " · ${OfflineProgressPolicy.formatBytes(storageStats.downloadedBytes)} available offline"
                    } else {
                        ""
                    },
                color = if (overArtwork) Color.White.copy(alpha = 0.62f) else OpenStreamColors.Muted,
                fontSize = 12.sp,
            )
        }
    }

    val detailsScroll = rememberScrollState()
    Column(
        Modifier.fillMaxSize().background(OpenStreamColors.Canvas).verticalScrollbar(detailsScroll).verticalScroll(detailsScroll),
    ) {
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val heroHeight = ArtworkPresentationPolicy.stageHeightDp(
                widthDp = maxWidth.value,
                screenHeightDp = configuration.screenHeightDp.toFloat(),
            ).dp
            val detailsOverlayWidth = ArtworkPresentationPolicy.detailsOverlayWidthDp(maxWidth.value).dp
            Box(Modifier.fillMaxWidth().height(heroHeight).background(Color.Black)) {
                CinematicArtwork(item, Modifier.fillMaxSize())
                if (showTrailer) {
                    YoutubeTrailerPreview(
                        youtubeKey = item.trailerYoutubeKey.orEmpty(),
                        modifier = Modifier.fillMaxSize().alpha(if (revealTrailer) 1f else 0f),
                        onPlaying = { trailerPlaying = true },
                        onUnavailable = {
                            trailerPlaying = false
                            trailerUnavailable = true
                        },
                    )
                }
                if (!revealTrailer) {
                    Box(
                        Modifier.fillMaxSize().background(
                            Brush.horizontalGradient(
                                0f to OpenStreamColors.Canvas.copy(alpha = 0.58f),
                                0.25f to Color.Transparent,
                                0.75f to Color.Transparent,
                                1f to OpenStreamColors.Canvas.copy(alpha = 0.58f),
                            ),
                        ),
                    )
                    Box(
                        Modifier.fillMaxSize().background(
                            Brush.verticalGradient(
                                0f to Color.Transparent,
                                0.72f to Color.Transparent,
                                1f to OpenStreamColors.Canvas,
                            ),
                        ),
                    )
                    Box(
                        Modifier.fillMaxSize().background(
                            Brush.verticalGradient(
                                0f to Color.Black.copy(alpha = 0.78f),
                                0.34f to Color.Transparent,
                                1f to OpenStreamColors.Canvas.copy(alpha = 0.95f),
                            ),
                        ),
                    )
                }
                Surface(
                    onClick = onBack,
                    modifier = Modifier.align(Alignment.TopStart).padding(14.dp),
                    shape = CircleShape,
                    color = Color.Black.copy(alpha = 0.62f),
                    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.16f)),
                ) {
                    Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) {
                        Icon(
                            AppIcons.Back,
                            contentDescription = "Back",
                            tint = Color.White,
                            modifier = Modifier.size(19.dp),
                        )
                    }
                }
                if (!revealTrailer) {
                    Column(
                        modifier = Modifier.align(Alignment.TopStart).padding(start = 70.dp, end = 28.dp, top = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            item.title,
                            fontSize = 32.sp,
                            fontWeight = FontWeight.ExtraBold,
                            color = Color.White,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        MetaRow(item, includeFormat = false)
                    }
                }
                if (showDetailsOverlay) {
                    Column(
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(start = 28.dp, end = 28.dp, bottom = 24.dp)
                            .width(detailsOverlayWidth),
                        verticalArrangement = Arrangement.spacedBy(13.dp),
                    ) {
                        detailsInformation(true)
                        detailsActions(true)
                    }
                }
            }
        }

        Column(Modifier.padding(horizontal = 28.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (!expandedDetailsOverlay) {
                detailsInformation(false)
                detailsActions(false)
            }

            if (item.episodes.isNotEmpty()) {
                SectionHeader("Episodes")
                val episodeRailState = rememberLazyListState()
                LazyRow(
                    state = episodeRailState,
                    flingBehavior = rememberSnapFlingBehavior(lazyListState = episodeRailState),
                    contentPadding = PaddingValues(vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    items(visibleEpisodes, key = MediaItem::id) { episode ->
                        EpisodeCard(
                            episode = episode,
                            enabled = !searching &&
                                (
                                    bestPlaybackRequest(
                                        episode,
                                        deviceProfile = deviceProfile,
                                        mediaProbe = mediaProbeResolver,
                                    ) != null || canResolveStream(episode)
                                    ),
                            offlineCompleted = offlineCompleted(episode),
                            offlineActive = offlineActive(episode),
                            offlinePreparing = episode.id in offlinePreparingIds || episode.id in serverSubmittingIds,
                            onPlay = { playTarget(episode) },
                            onDownload = { requestTargetDownload(episode) },
                        )
                    }
                }
            }

            if (item.candidates.isNotEmpty()) SectionHeader("Playback sources")
            item.candidates.sortedBy { candidate -> if (candidate.offlineDownloadId != null) 0 else 1 }.forEach { candidate ->
                Surface(
                    shape = RoundedCornerShape(10.dp),
                    color = OpenStreamColors.Surface,
                    border = BorderStroke(1.dp, OpenStreamColors.Border),
                ) {
                    Row(
                        Modifier.fillMaxWidth().padding(16.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column {
                            Text(candidate.sourceName, fontWeight = FontWeight.Bold, color = OpenStreamColors.Text)
                            Text(
                                when {
                                    candidate.offlineDownloadId != null -> "Preferred automatically · stored on this device"
                                    candidate.directPlay -> "Preferred automatically when local"
                                    else -> "Compatible transcode"
                                },
                                fontSize = 13.sp,
                                color = OpenStreamColors.Muted,
                            )
                        }
                        Text(candidate.formatLabel, fontSize = 13.sp, color = OpenStreamColors.TextSoft)
                    }
                }
            }
            Box(Modifier.height(24.dp))
        }
    }

}

@Composable
private fun EpisodeCard(
    episode: MediaItem,
    enabled: Boolean,
    offlineCompleted: Boolean,
    offlineActive: Boolean,
    offlinePreparing: Boolean,
    onPlay: () -> Unit,
    onDownload: () -> Unit,
) {
    val label = episode.subtitle?.substringBefore('·')?.trim().orEmpty().ifBlank { "Episode" }
    val title = episode.subtitle?.substringAfter('·', "")?.trim().orEmpty()
    Surface(
        onClick = onPlay,
        enabled = enabled,
        modifier = Modifier.width(310.dp),
        shape = RoundedCornerShape(12.dp),
        color = OpenStreamColors.Surface,
        border = BorderStroke(1.dp, OpenStreamColors.Border),
    ) {
        Column {
            Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).background(Color.Black)) {
                Poster(
                    item = episode,
                    modifier = Modifier.fillMaxSize(),
                    useBackdrop = true,
                    contentScale = ContentScale.Crop,
                )
                Box(
                    Modifier.fillMaxSize().background(
                        Brush.verticalGradient(0.45f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.85f)),
                    ),
                )
                Surface(
                    modifier = Modifier.align(Alignment.BottomStart).padding(12.dp),
                    shape = OpenStreamShapes.Tag,
                    color = Color.Black.copy(alpha = 0.72f),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 11.dp, vertical = 7.dp),
                        horizontalArrangement = Arrangement.spacedBy(7.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(AppIcons.Play, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                        Text(label, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.ExtraBold)
                    }
                }
                OfflineActionButton(
                    completed = offlineCompleted,
                    active = offlineActive,
                    preparing = offlinePreparing,
                    contentDescription = if (offlineCompleted) {
                        "$label downloaded"
                    } else {
                        "Download $label"
                    },
                    modifier = Modifier.align(Alignment.TopEnd).padding(10.dp),
                    onDownload = onDownload,
                )
            }
            Column(Modifier.padding(13.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(
                    title.ifBlank { label },
                    color = OpenStreamColors.Text,
                    fontWeight = FontWeight.Bold,
                    fontSize = 15.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (episode.synopsis.isNotBlank()) {
                    Text(
                        episode.synopsis,
                        color = OpenStreamColors.Muted,
                        fontSize = 12.sp,
                        lineHeight = 17.sp,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

@Composable
private fun OfflineActionButton(
    completed: Boolean,
    active: Boolean,
    preparing: Boolean,
    contentDescription: String,
    modifier: Modifier = Modifier,
    onDownload: () -> Unit,
) {
    val visual = OfflineDownloadUiPolicy.visual(completed, active, preparing)
    val enabled = OfflineDownloadUiPolicy.canQueue(completed, active, preparing)
    Surface(
        onClick = onDownload,
        enabled = enabled,
        modifier = modifier.size(46.dp),
        shape = CircleShape,
        color = Color.Black.copy(alpha = 0.76f),
        border = BorderStroke(
            1.dp,
            if (completed) OpenStreamColors.Green else Color.White.copy(alpha = 0.30f),
        ),
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            when (visual) {
                OfflineDownloadVisual.DOWNLOAD -> Icon(
                    AppIcons.Download,
                    contentDescription = contentDescription,
                    tint = Color.White,
                    modifier = Modifier.size(20.dp),
                )
                OfflineDownloadVisual.CHECK -> Icon(
                    AppIcons.Check,
                    contentDescription = contentDescription,
                    tint = OpenStreamColors.Green,
                    modifier = Modifier.size(20.dp),
                )
                OfflineDownloadVisual.PROGRESS -> OpenStreamLoadingIndicator(
                    role = LoadingIndicatorRole.DOWNLOAD,
                    color = Color.White,
                    trackColor = Color.White.copy(alpha = 0.20f),
                )
            }
        }
    }
}

@Composable
private fun DownloadDestinationOption(
    title: String,
    detail: String,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = OpenStreamColors.Surface,
        border = BorderStroke(1.dp, OpenStreamColors.Border),
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 13.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(title, color = OpenStreamColors.Text, fontWeight = FontWeight.Bold, fontSize = 15.sp)
            Text(detail, color = OpenStreamColors.Muted, fontSize = 12.sp)
        }
    }
}

@Composable
private fun ScoreBadge(label: String, value: String, accent: androidx.compose.ui.graphics.Color) {
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = OpenStreamColors.Surface,
        border = androidx.compose.foundation.BorderStroke(1.dp, OpenStreamColors.Border),
    ) {
        Row(
            Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
            horizontalArrangement = Arrangement.spacedBy(7.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = accent)
            Text(value, fontSize = 14.sp, fontWeight = FontWeight.ExtraBold, color = OpenStreamColors.Text)
        }
    }
}
