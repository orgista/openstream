package com.orgista.openstream.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.C
import androidx.media3.common.MediaItem as Media3Item
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.session.MediaSession
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.video.VideoFrameMetadataListener
import androidx.media3.ui.PlayerView
import androidx.media3.ui.AspectRatioFrameLayout
import com.orgista.openstream.Logs
import com.orgista.openstream.data.StremioAddon
import com.orgista.openstream.data.StremioClient
import com.orgista.openstream.media.DolbyVisionCodecString
import com.orgista.openstream.media.DolbyVisionCompatibility
import com.orgista.openstream.media.DolbyVisionPlaybackPolicy
import com.orgista.openstream.player.SmbDataSource
import com.orgista.openstream.player.PlaybackStore
import com.orgista.openstream.player.PlaybackFormatLabels
import com.orgista.openstream.player.PlaybackHttpPolicy
import com.orgista.openstream.player.PlaybackRouteRetryPolicy
import com.orgista.openstream.player.PlaybackRoutePresentation
import com.orgista.openstream.player.PlaybackTrackSignal
import com.orgista.openstream.player.PlayerLoadingUiPolicy
import com.orgista.openstream.player.PlayerKeyAction
import com.orgista.openstream.player.PlayerKeyboardPolicy
import com.orgista.openstream.player.LivePlayerGesturePolicy
import com.orgista.openstream.player.LiveEdgeSeekDecision
import com.orgista.openstream.player.LiveEdgeSeekPolicy
import com.orgista.openstream.player.LiveMediaSourceFactory
import com.orgista.openstream.player.LiveVideoFreezeRecoveryAction
import com.orgista.openstream.player.LiveVideoFreezeRecoveryPolicy
import com.orgista.openstream.offline.OfflineMediaRuntime
import com.orgista.openstream.offline.OfflineDeviceCapabilities
import com.orgista.openstream.offline.OfflineRetentionPolicy
import com.orgista.openstream.ui.icons.AppIcons
import com.orgista.openstream.trakt.TraktClient
import com.orgista.openstream.trakt.TraktScrobbleAction
import com.orgista.openstream.trakt.TraktStore
import com.orgista.openstream.streaming.BandwidthRuntime
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicLong

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

private fun Throwable.httpResponseCode(): Int? {
    var failure: Throwable? = this
    repeat(12) {
        when (failure) {
            is HttpDataSource.InvalidResponseCodeException -> return failure.responseCode
            null -> return null
            else -> failure = failure?.cause
        }
    }
    return null
}

private fun safePlaybackHeaders(request: PlaybackRequest): Map<String, String> = buildMap {
    request.httpRequestHeaders.forEach { (name, value) ->
        val safeName = name.matches(Regex("[A-Za-z0-9-]{1,64}"))
        val safeValue = value.length <= 1024 && '\r' !in value && '\n' !in value
        if (safeName && safeValue) put(name, value)
    }
    request.httpReferer?.takeIf {
        it.length <= 512 && '\r' !in it && '\n' !in it
    }?.let { referer -> put("Referer", referer) }
}

/**
 * Native Media3 playback. SMB URIs stream through the jcifs-ng DataSource,
 * HTTP(S) routes use the default sources. Only this screen is
 * immersive; system bars come back the moment playback closes so the app
 * never traps the viewer.
 */
@OptIn(UnstableApi::class)
@Composable
fun PlayerScreen(
    request: PlaybackRequest,
    autoSubtitles: Boolean = false,
    subtitleAddons: List<StremioAddon> = emptyList(),
    deleteOfflineAfterWatched: Boolean = false,
    playbackStore: PlaybackStore,
    onBack: () -> Unit,
    onExit: () -> Unit,
    onProgressSaved: () -> Unit = {},
    onChangeLiveChannel: (Int) -> Unit = {},
) {
    val context = LocalContext.current
    val syncScope = rememberCoroutineScope()
    val currentLiveChannelChange by rememberUpdatedState(onChangeLiveChannel)
    var error by remember { mutableStateOf<String?>(null) }
    var chromeVisible by remember { mutableStateOf(false) }
    var formatLabels by remember { mutableStateOf<List<String>>(emptyList()) }
    var formatIndicatorVisible by remember { mutableStateOf(false) }
    var streamingStatusVisible by remember(request) { mutableStateOf(request.streamingPlan != null) }
    var streamingStatusText by remember(request) { mutableStateOf(request.streamingPlan?.statusText.orEmpty()) }
    var verifiedPlaybackLabel by remember(request) { mutableStateOf("") }
    var selectedRouteFormatLabels by remember(request) { mutableStateOf<List<String>>(emptyList()) }
    var selectedVideoHeight by remember(request) { mutableStateOf<Int?>(null) }
    var livePlaybackStarted by remember(request) { mutableStateOf(false) }
    val offlineRuntime = remember { OfflineMediaRuntime.get(context.applicationContext) }
    val deviceProfile = remember { OfflineDeviceCapabilities.inspect(context.applicationContext) }
    val traktStore = remember { TraktStore(context.applicationContext) }
    val traktClient = remember { TraktClient(traktStore) }
    val traktIdentity = request.traktIdentity.takeIf { traktStore.syncEnabled && traktClient.connected }
    val progressKey = request.mediaId ?: request.uri
    val playbackRoutes = remember(request) {
        playableUris(request).ifEmpty { listOf(request.uri) }
    }
    val startupStartedAt = remember(request) { android.os.SystemClock.elapsedRealtime() }
    var activeRouteIndex by remember(request) { mutableIntStateOf(0) }
    val savedPosition = remember(request.uri, progressKey) {
        (playbackStore.load(progressKey) ?: request.uri.takeIf { it != progressKey }?.let(playbackStore::load))?.let {
            com.orgista.openstream.player.PlaybackProgressPolicy.resumePosition(it.positionMs, it.durationMs)
        } ?: 0L
    }

    fun playerUri(uri: String): android.net.Uri = android.net.Uri.parse(uri)

    val mediaUri = remember(playbackRoutes) { playerUri(playbackRoutes.first()) }
    val initialMediaItem = remember(request, mediaUri) {
        request.offlineDownloadId?.let(offlineRuntime::downloadMediaItem)
            ?: Media3Item.Builder()
                .setUri(mediaUri)
                .apply {
                    request.offlineDownloadId?.let { setCustomCacheKey("offline-$it") }
                }
                .build()
    }

    val player = remember(request, playbackRoutes) {
        if (request.isLive) {
            Logs.event("live startup begin: ${request.title} · ${playbackRoutes.size} route(s)")
        }
        val dataSourceFactory: DataSource.Factory = when {
            request.offlineDownloadId != null -> offlineRuntime.cacheOnlyDataSourceFactory()
            request.uri.startsWith("smb://") && request.nasConnection != null ->
                SmbDataSource.Factory(request.nasConnection)
            else -> DefaultDataSource.Factory(
                context,
                DefaultHttpDataSource.Factory()
                    .setUserAgent(
                        request.httpUserAgent?.takeIf {
                            it.length <= 512 && '\r' !in it && '\n' !in it
                        } ?: PlaybackHttpPolicy.userAgent,
                    )
                    .setConnectTimeoutMs(
                        if (request.isLive) PlaybackHttpPolicy.liveConnectTimeoutMs
                        else PlaybackHttpPolicy.connectTimeoutMs,
                    )
                    .setReadTimeoutMs(
                        if (request.isLive) PlaybackHttpPolicy.liveReadTimeoutMs
                        else PlaybackHttpPolicy.readTimeoutMs,
                    )
                    .setAllowCrossProtocolRedirects(PlaybackHttpPolicy.followCrossProtocolRedirects)
                    .apply {
                        safePlaybackHeaders(request).takeIf { it.isNotEmpty() }?.let(::setDefaultRequestProperties)
                    },
            )
        }
        // Hardware decoders first — this preserves Dolby Vision video and
        // Dolby Atmos (TrueHD/E-AC3) passthrough that this device supports
        // natively — with the FFmpeg software decoders as a *fallback* only
        // for codecs the hardware can't handle. MODE_ON = hardware first,
        // extension fallback (not MODE_PREFER, which would force software and
        // lose Atmos/DV). This is the Infuse/Jellyfin behaviour.
        val renderersFactory = io.github.anilbeesetti.nextlib.media3ext.ffdecoder.NextRenderersFactory(context)
            .setExtensionRendererMode(androidx.media3.exoplayer.DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            .setEnableDecoderFallback(true)
        val mediaSourceFactory = if (request.isLive) {
            LiveMediaSourceFactory(dataSourceFactory)
        } else {
            DefaultMediaSourceFactory(dataSourceFactory)
        }
        val playerBuilder = ExoPlayer.Builder(context, renderersFactory)
            .setMediaSourceFactory(mediaSourceFactory)
            .setSeekBackIncrementMs(10_000)
            .setSeekForwardIncrementMs(10_000)
        request.streamingPlan?.let { plan ->
            val playbackBufferMs = plan.startupBufferSeconds.coerceIn(3, 30) * 1_000
            playerBuilder.setLoadControl(
                DefaultLoadControl.Builder()
                    .setBufferDurationsMs(
                        maxOf(20_000, playbackBufferMs * 2),
                        maxOf(50_000, playbackBufferMs * 4),
                        playbackBufferMs,
                        maxOf(10_000, playbackBufferMs),
                    )
                    .setPrioritizeTimeOverSizeThresholds(false)
                    .build(),
            )
        }
        playerBuilder.build()
            .apply {
                trackSelectionParameters = trackSelectionParameters
                    .buildUpon()
                    .setMaxVideoSize(deviceProfile.maxDecodeWidth, deviceProfile.maxDecodeHeight)
                    .setViewportSize(deviceProfile.maxWidth, deviceProfile.maxHeight, true)
                    .build()
                setAudioAttributes(
                    androidx.media3.common.AudioAttributes.Builder()
                        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                        .setUsage(C.USAGE_MEDIA)
                        .build(),
                    true,
                )
                setMediaItem(initialMediaItem)
                if (savedPosition > 0L) seekTo(savedPosition)
                playWhenReady = true
                prepare()
            }
    }

    fun returnToLiveEdge() {
        val liveOffsetMs = player.currentLiveOffset.takeUnless { it == C.TIME_UNSET }
        val durationMs = player.duration.takeUnless { it == C.TIME_UNSET || it <= 0L }
        val positionBeforeMs = player.currentPosition
        val decision = LiveEdgeSeekPolicy.decide(
            timelineIsLive = player.isCurrentMediaItemLive,
            currentPositionMs = positionBeforeMs,
            durationMs = durationMs,
            currentLiveOffsetMs = liveOffsetMs,
        )
        player.setPlaybackSpeed(1f)
        when (decision) {
            LiveEdgeSeekDecision.Resume -> player.play()
            is LiveEdgeSeekDecision.SeekForward -> {
                player.seekTo(decision.positionMs)
                player.play()
            }
            LiveEdgeSeekDecision.Reconnect -> {
                streamingStatusVisible = true
                streamingStatusText = "Returning to live"
                error = null
                player.setMediaItem(Media3Item.fromUri(playerUri(playbackRoutes[activeRouteIndex])))
                player.playWhenReady = true
                player.prepare()
            }
        }
        Logs.event(
            "live edge requested: ${request.title} · ${decision::class.simpleName} · " +
                "position ${positionBeforeMs}ms · offset ${liveOffsetMs ?: -1L}ms",
        )
    }

    LaunchedEffect(player, request.streamingPlan) {
        val plan = request.streamingPlan
        var playingSince = 0L
        var bufferingSince = 0L
        var slowStartOptimizationStarted = false
        while (true) {
            val bufferedSeconds = ((player.bufferedPosition - player.currentPosition).coerceAtLeast(0L) / 1_000L)
            val verified = verifiedPlaybackLabel.takeIf(String::isNotBlank)?.let { " · $it" }.orEmpty()
            val routeStatus = if (request.isLive) {
                if (activeRouteIndex == 0) "Loading" else {
                    "Trying another channel stream"
                }
            } else if (plan == null) {
                if (activeRouteIndex == 0) "Preparing playback" else {
                    "Preparing alternative ${activeRouteIndex + 1}/${playbackRoutes.size}"
                }
            } else {
                PlaybackRoutePresentation.status(
                    primaryStatus = plan.statusText,
                    activeRouteIndex = activeRouteIndex,
                    routeCount = playbackRoutes.size,
                    selectedTrackLabels = selectedRouteFormatLabels,
                )
            }
            if (!player.playWhenReady) {
                streamingStatusVisible = false
                playingSince = 0L
                bufferingSince = 0L
            } else if (player.playbackState == Player.STATE_BUFFERING) {
                streamingStatusVisible = true
                streamingStatusText = "$routeStatus$verified · ${bufferedSeconds}s buffered"
                playingSince = 0L
                if (bufferingSince == 0L) bufferingSince = android.os.SystemClock.elapsedRealtime()
                if (!slowStartOptimizationStarted && !request.isLive && plan == null && request.offlineDownloadId == null &&
                    !request.uri.startsWith("smb://") &&
                    android.os.SystemClock.elapsedRealtime() - bufferingSince >= 5_000L
                ) {
                    slowStartOptimizationStarted = true
                    syncScope.launch(Dispatchers.IO) {
                        runCatching { BandwidthRuntime.optimizeAfterSlowStart(context.applicationContext) }
                    }
                }
            } else if (player.isPlaying && streamingStatusVisible) {
                bufferingSince = 0L
                if (playingSince == 0L) playingSince = android.os.SystemClock.elapsedRealtime()
                streamingStatusText = "$routeStatus$verified"
                val confirmationMs = if (plan == null) 1_500L else 8_000L
                if (android.os.SystemClock.elapsedRealtime() - playingSince >= confirmationMs) {
                    streamingStatusVisible = false
                    playingSince = 0L
                }
            }
            kotlinx.coroutines.delay(500)
        }
    }

    // Prefer a local resume point; otherwise adopt Trakt's cross-device point
    // after Media3 knows the actual duration.
    LaunchedEffect(player, traktIdentity, savedPosition) {
        if (savedPosition > 0L || traktIdentity == null) return@LaunchedEffect
        val remotePercent = withContext(Dispatchers.IO) {
            runCatching { traktClient.resumePercent(traktIdentity) }.getOrNull()
        } ?: return@LaunchedEffect
        repeat(40) {
            if (player.duration > 0L) {
                if (player.currentPosition < 15_000L) {
                    player.seekTo((player.duration * (remotePercent / 100.0)).toLong())
                }
                return@LaunchedEffect
            }
            kotlinx.coroutines.delay(250)
        }
    }

    LaunchedEffect(request.mediaId) {
        request.mediaId?.let(playbackStore::markStarted)
    }

    // Combine subtitle files beside NAS media with tracks from enabled Stremio
    // subtitle add-ons. Re-setting once avoids one source replacing the other.
    LaunchedEffect(request.uri, request.stremioId, subtitleAddons) {
        if (request.offlineDownloadId != null) return@LaunchedEffect
        if (request.isLive) return@LaunchedEffect
        val (nasSubtitles, remoteSubtitles) = withContext(Dispatchers.IO) {
            coroutineScope {
                val local = async {
                    val connection = request.nasConnection
                    if (connection == null || !request.uri.startsWith("smb://")) return@async emptyList()
                    val relative = request.uri.removePrefix(com.orgista.openstream.data.Smb.shareUrl(connection))
                    runCatching {
                        com.orgista.openstream.data.Smb.siblingSubtitles(connection, relative)
                    }.getOrDefault(emptyList())
                }
                val stremioId = request.stremioId
                val stremioType = request.stremioType
                val remote = if (stremioId == null || stremioType == null) {
                    emptyList()
                } else {
                    subtitleAddons.map { addon ->
                        async {
                            addon to runCatching {
                                StremioClient.subtitlesFor(addon, stremioType, stremioId)
                            }.onFailure {
                                Logs.warn("captions failed for ${addon.name}")
                            }.getOrDefault(emptyList())
                        }
                    }.awaitAll()
                }
                local.await() to remote
            }
        }
        val configurations = nasSubtitles.map { sub ->
            Media3Item.SubtitleConfiguration.Builder(android.net.Uri.parse(sub.uri))
                .setMimeType(sub.mimeType)
                .setLanguage(sub.language)
                .setLabel(sub.label)
                .build()
        } + remoteSubtitles.flatMap { (addon, subtitles) ->
            subtitles.map { sub ->
                Media3Item.SubtitleConfiguration.Builder(android.net.Uri.parse(sub.url))
                    .setMimeType(sub.mimeType)
                    .setLanguage(sub.language)
                    .setLabel("${sub.language.uppercase()} · ${addon.name}")
                    .build()
            }
        }
        if (configurations.isEmpty()) return@LaunchedEffect
        Logs.event(
            "loaded ${configurations.size} caption track(s) for ${request.title}: " +
                "${nasSubtitles.size} local, ${configurations.size - nasSubtitles.size} add-on",
        )
        val item = Media3Item.Builder()
            .setUri(playerUri(playbackRoutes[activeRouteIndex]))
            .setSubtitleConfigurations(configurations.distinctBy { "${it.uri}:${it.language}" }.take(100))
            .build()
        val resume = player.currentPosition.coerceAtLeast(savedPosition)
        player.setMediaItem(item, resume)
        player.playWhenReady = true
        player.prepare()
    }

    // Save in small intervals so an activity or gesture-back transition cannot
    // lose the resume point. The URI is hashed by PlaybackStore.
    LaunchedEffect(player, progressKey) {
        while (true) {
            kotlinx.coroutines.delay(5_000)
            if (player.duration > 0L) {
                playbackStore.save(progressKey, player.currentPosition, player.duration)
            }
        }
    }

    LaunchedEffect(formatLabels) {
        if (formatLabels.isNotEmpty()) {
            formatIndicatorVisible = true
            kotlinx.coroutines.delay(3_500)
            formatIndicatorVisible = false
        }
    }

    // Keep the status bar hidden while playing, but leave the navigation bar
    // shown so swipe-up-to-Home keeps working — matching the app-wide behaviour
    // in NativeAppActivity. Critically, do NOT hide the nav bar on dispose:
    // doing so left the whole app in immersive-sticky and broke the Home
    // gesture on the browse screens after a video closed.
    DisposableEffect(Unit) {
        val window = context.findActivity()?.window
        fun applyBars() {
            if (window == null) return
            @Suppress("DEPRECATION")
            window.navigationBarColor = android.graphics.Color.TRANSPARENT
            if (Build.VERSION.SDK_INT >= 29) window.isNavigationBarContrastEnforced = false
            if (Build.VERSION.SDK_INT >= 30) {
                window.insetsController?.hide(WindowInsets.Type.statusBars())
                window.insetsController?.show(WindowInsets.Type.navigationBars())
            } else {
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility =
                    View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            }
        }
        applyBars()
        onDispose { applyBars() }
    }

    DisposableEffect(player, request) {
        var lastLoggedTrackSummary: String? = null
        val rejectedDolbyVisionRoutes = mutableSetOf<Int>()
        val routeRetryCounts = mutableMapOf<Int, Int>()
        val pendingRouteRetries = mutableSetOf<Int>()
        val readyRoutes = mutableSetOf<Int>()
        val lastVideoFrameAt = AtomicLong(android.os.SystemClock.elapsedRealtime())
        val freezeRecoveryAttempts = mutableMapOf<Int, Int>()
        val lastFreezeRecoveryAt = mutableMapOf<Int, Long>()
        var hasSelectedVideo = false
        var freezeMonitorRouteIndex = activeRouteIndex
        var lastObservedPositionMs: Long? = null
        var firstFrameLogged = false
        var bufferingStartedAt = 0L

        fun resetFreezeMonitor(routeIndex: Int = activeRouteIndex) {
            freezeMonitorRouteIndex = routeIndex
            lastObservedPositionMs = null
            hasSelectedVideo = false
            lastVideoFrameAt.set(android.os.SystemClock.elapsedRealtime())
        }

        fun tryNextRoute(reason: String, status: String): Boolean {
            val nextRoute = activeRouteIndex + 1
            if (nextRoute >= playbackRoutes.size) return false
            val resume = player.currentPosition.coerceAtLeast(savedPosition)
            activeRouteIndex = nextRoute
            livePlaybackStarted = false
            resetFreezeMonitor(nextRoute)
            pendingRouteRetries.clear()
            error = null
            verifiedPlaybackLabel = ""
            selectedRouteFormatLabels = emptyList()
            lastLoggedTrackSummary = null
            Logs.warn(
                "$reason; trying alternate ${nextRoute + 1}/${playbackRoutes.size} for ${request.title}",
            )
            streamingStatusVisible = true
            streamingStatusText = "$status · trying alternative ${nextRoute + 1}/${playbackRoutes.size}"
            if (request.isLive) {
                player.setMediaItem(Media3Item.fromUri(playerUri(playbackRoutes[nextRoute])))
                player.seekToDefaultPosition()
            } else {
                player.setMediaItem(Media3Item.fromUri(playerUri(playbackRoutes[nextRoute])), resume)
            }
            player.playWhenReady = true
            player.prepare()
            return true
        }

        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                Logs.event("playback ${if (isPlaying) "playing" else "paused"}: ${request.title}")
                if (request.isLive && isPlaying) {
                    lastObservedPositionMs = null
                    lastVideoFrameAt.set(android.os.SystemClock.elapsedRealtime())
                }
                val identity = traktIdentity ?: return
                if (player.duration <= 0L || player.playbackState != Player.STATE_READY) return
                val progress = player.currentPosition.toDouble() / player.duration.toDouble() * 100.0
                val action = if (isPlaying) TraktScrobbleAction.START else TraktScrobbleAction.PAUSE
                syncScope.launch(Dispatchers.IO) { runCatching { traktClient.scrobble(action, identity, progress) } }
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                val elapsed = android.os.SystemClock.elapsedRealtime() - startupStartedAt
                if (playbackState == Player.STATE_BUFFERING && bufferingStartedAt == 0L) {
                    bufferingStartedAt = android.os.SystemClock.elapsedRealtime()
                }
                if (playbackState == Player.STATE_READY) {
                    pendingRouteRetries.remove(activeRouteIndex)
                    error = null
                    Logs.event("playback ready: ${request.title}")
                    if (request.isLive && readyRoutes.add(activeRouteIndex)) {
                        val bufferedFor = if (bufferingStartedAt == 0L) 0L else {
                            android.os.SystemClock.elapsedRealtime() - bufferingStartedAt
                        }
                        Logs.event(
                            "live startup ready in ${elapsed}ms: ${request.title} · " +
                                "route ${activeRouteIndex + 1}/${playbackRoutes.size} · buffered ${bufferedFor}ms",
                        )
                    }
                    bufferingStartedAt = 0L
                } else if (playbackState == Player.STATE_ENDED) {
                    traktIdentity?.let { identity ->
                        syncScope.launch(Dispatchers.IO) {
                            runCatching { traktClient.scrobble(TraktScrobbleAction.STOP, identity, 100.0) }
                        }
                    }
                    playbackStore.clear(progressKey)
                    if (progressKey != request.uri) playbackStore.clear(request.uri)
                    request.mediaId?.let { playbackStore.markCompleted(it) }
                    if (OfflineRetentionPolicy.shouldDelete(
                            deleteAfterWatched = deleteOfflineAfterWatched,
                            playbackEnded = true,
                            offlineDownloadId = request.offlineDownloadId,
                        )
                    ) {
                        request.offlineDownloadId?.let { downloadId ->
                            offlineRuntime.remove(downloadId)
                            Logs.event("completed offline download scheduled for removal")
                        }
                    }
                }
            }

            // Auto-captions: when the setting is on and nothing has selected a
            // text track yet, force-select the first available subtitle track
            // (embedded or side-loaded). The isSelected guard stops the
            // parameter change from looping through onTracks.
            override fun onTracksChanged(tracks: Tracks) {
                fun selectedFormat(type: Int): androidx.media3.common.Format? = tracks.groups
                    .asSequence()
                    .filter { it.type == type }
                    .flatMap { group ->
                        (0 until group.length).asSequence()
                            .filter(group::isTrackSelected)
                            .map(group::getTrackFormat)
                    }
                    .firstOrNull()
                val video = selectedFormat(C.TRACK_TYPE_VIDEO)
                val audio = selectedFormat(C.TRACK_TYPE_AUDIO)
                val text = selectedFormat(C.TRACK_TYPE_TEXT)
                if (!hasSelectedVideo && video != null) {
                    lastVideoFrameAt.set(android.os.SystemClock.elapsedRealtime())
                }
                hasSelectedVideo = video != null
                val dolbyDescriptor = DolbyVisionCodecString.parse(video?.codecs).orElse(null)
                val dolbyCompatibility = DolbyVisionPlaybackPolicy.compatibility(
                    video?.sampleMimeType,
                    video?.codecs,
                    deviceProfile.dolbyVisionProfiles,
                )
                val trackSummary = listOf(
                    "video=${video?.sampleMimeType ?: "none"}",
                    "codec=${dolbyDescriptor?.label() ?: video?.codecs?.take(48) ?: "not-signaled"}",
                    "audio=${audio?.sampleMimeType ?: "none"}",
                    "captions=${text?.language ?: if (text == null) "off" else "und"}",
                ).joinToString(",")
                if (trackSummary != lastLoggedTrackSummary) {
                    lastLoggedTrackSummary = trackSummary
                    Logs.event("selected tracks: $trackSummary")
                }
                if (dolbyCompatibility == DolbyVisionCompatibility.UNSUPPORTED &&
                    rejectedDolbyVisionRoutes.add(activeRouteIndex)
                ) {
                    val profile = dolbyDescriptor?.profile()?.let { "P$it" } ?: "an unsupported profile"
                    val status = "Dolby Vision $profile is not supported by this decoder"
                    if (tryNextRoute(status, status)) return
                    streamingStatusVisible = false
                    error = status
                    return
                }
                if (dolbyCompatibility == DolbyVisionCompatibility.SUPPORTED && dolbyDescriptor != null) {
                    verifiedPlaybackLabel = "Dolby Vision P${dolbyDescriptor.profile()} verified"
                }
                val detectedFormatLabels = PlaybackFormatLabels.forSignal(
                    PlaybackTrackSignal(
                        videoCodecs = video?.codecs,
                        colorTransfer = video?.colorInfo?.colorTransfer,
                        hasHdrStaticInfo = video?.colorInfo?.hdrStaticInfo != null,
                        audioMimeType = audio?.sampleMimeType,
                        audioCodecs = audio?.codecs,
                        sourceHint = request.subtitle,
                    ),
                )
                formatLabels = detectedFormatLabels
                selectedRouteFormatLabels = detectedFormatLabels
                selectedVideoHeight = video?.height?.takeIf { it > 0 }
                if (!autoSubtitles) return
                val alreadyOn = tracks.groups.any { it.type == C.TRACK_TYPE_TEXT && it.isSelected }
                if (alreadyOn) return
                val textGroup = tracks.groups.firstOrNull { it.type == C.TRACK_TYPE_TEXT && it.isSupported }
                    ?: return
                player.trackSelectionParameters = player.trackSelectionParameters
                    .buildUpon()
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                    .setOverrideForType(TrackSelectionOverride(textGroup.mediaTrackGroup, 0))
                    .build()
                Logs.event("auto-captions: subtitle track enabled for ${request.title}")
            }

            override fun onPlayerError(playbackError: PlaybackException) {
                // PlaybackException causes may include signed media URLs.
                val routeIndex = activeRouteIndex
                if (routeIndex in pendingRouteRetries) return
                val responseCode = playbackError.httpResponseCode()
                if (request.isLive) {
                    Logs.warn(
                        "live route ${routeIndex + 1}/${playbackRoutes.size} failed after " +
                            "${android.os.SystemClock.elapsedRealtime() - startupStartedAt}ms " +
                            "(${responseCode ?: playbackError.errorCodeName}) for ${request.title}",
                    )
                }
                val retryAttempt = routeRetryCounts[routeIndex] ?: 0
                if (PlaybackRouteRetryPolicy.shouldRetry(
                        statusCode = responseCode,
                        attempt = retryAttempt,
                        preferredRoute = routeIndex == 0,
                        isLive = request.isLive,
                        playedSuccessfully = livePlaybackStarted,
                    )
                ) {
                    val resumeAfterRetry = player.playWhenReady
                    routeRetryCounts[routeIndex] = retryAttempt + 1
                    pendingRouteRetries += routeIndex
                    val retryNumber = retryAttempt + 1
                    val responseLabel = responseCode?.toString() ?: "network"
                    streamingStatusVisible = true
                    streamingStatusText = if (request.isLive) {
                        "Loading"
                    } else {
                        "Provider temporarily unavailable ($responseLabel) · retry $retryNumber/${PlaybackRouteRetryPolicy.MAX_RETRIES}"
                    }
                    Logs.warn(
                        "playback provider returned $responseLabel; retrying preferred route " +
                            "$retryNumber/${PlaybackRouteRetryPolicy.MAX_RETRIES} for ${request.title}",
                    )
                    syncScope.launch {
                        kotlinx.coroutines.delay(PlaybackRouteRetryPolicy.delayMs(retryAttempt))
                        pendingRouteRetries.remove(routeIndex)
                        if (activeRouteIndex != routeIndex) return@launch
                        if (request.isLive) {
                            player.setMediaItem(Media3Item.fromUri(playerUri(playbackRoutes[routeIndex])))
                            player.seekToDefaultPosition()
                        }
                        player.prepare()
                        player.playWhenReady = resumeAfterRetry
                    }
                    return
                }
                val reason = "playback route unavailable (${playbackError.errorCodeName})"
                if (!tryNextRoute(reason, "Primary stream failed")) {
                    Logs.error("playback error for ${request.title}: ${playbackError.errorCodeName}")
                    streamingStatusVisible = false
                    error = PlaybackRouteRetryPolicy.terminalMessage(
                        statusCode = responseCode,
                        isLive = request.isLive,
                        errorCodeName = playbackError.errorCodeName,
                    )
                }
            }

            override fun onRenderedFirstFrame() {
                livePlaybackStarted = request.isLive
                routeRetryCounts.remove(activeRouteIndex)
                streamingStatusVisible = false
                if (request.isLive && !firstFrameLogged) {
                    firstFrameLogged = true
                    Logs.event(
                        "live startup first frame in " +
                            "${android.os.SystemClock.elapsedRealtime() - startupStartedAt}ms: ${request.title}",
                    )
                }
            }
        }
        val videoFrameMetadataListener = VideoFrameMetadataListener { _, _, _, _ ->
            lastVideoFrameAt.set(android.os.SystemClock.elapsedRealtime())
        }
        player.setVideoFrameMetadataListener(videoFrameMetadataListener)
        player.addListener(listener)
        val freezeMonitorJob = if (request.isLive) {
            syncScope.launch {
                while (true) {
                    kotlinx.coroutines.delay(1_000)
                    val routeIndex = activeRouteIndex
                    if (freezeMonitorRouteIndex != routeIndex) {
                        resetFreezeMonitor(routeIndex)
                    }
                    val positionMs = player.currentPosition
                    val positionAdvanced = lastObservedPositionMs?.let { positionMs >= it + 250L } ?: false
                    lastObservedPositionMs = positionMs
                    val now = android.os.SystemClock.elapsedRealtime()
                    val millisSinceLastFrame = now - lastVideoFrameAt.get()
                    val attempts = freezeRecoveryAttempts[routeIndex] ?: 0
                    val recoveredAt = lastFreezeRecoveryAt[routeIndex]
                    if (attempts > 0 && recoveredAt != null &&
                        now - recoveredAt >= LiveVideoFreezeRecoveryPolicy.STABLE_PLAYBACK_RESET_MS &&
                        millisSinceLastFrame < 2_000L
                    ) {
                        freezeRecoveryAttempts[routeIndex] = 0
                    }
                    when (LiveVideoFreezeRecoveryPolicy.action(
                        isLive = true,
                        isPlaying = player.isPlaying,
                        hasSelectedVideo = hasSelectedVideo,
                        playbackPositionAdvanced = positionAdvanced,
                        millisSinceLastVideoFrame = millisSinceLastFrame,
                        recoveryAttempts = freezeRecoveryAttempts[routeIndex] ?: 0,
                    )) {
                        LiveVideoFreezeRecoveryAction.NONE -> Unit
                        LiveVideoFreezeRecoveryAction.RESTART_ROUTE -> {
                            freezeRecoveryAttempts[routeIndex] = attempts + 1
                            lastFreezeRecoveryAt[routeIndex] = now
                            resetFreezeMonitor(routeIndex)
                            streamingStatusVisible = true
                            streamingStatusText = "Video stalled · reconnecting live stream"
                            Logs.warn(
                                "live video stalled while audio advanced; restarting route " +
                                    "${routeIndex + 1}/${playbackRoutes.size} for ${request.title}",
                            )
                            player.setMediaItem(Media3Item.fromUri(playerUri(playbackRoutes[routeIndex])))
                            player.seekToDefaultPosition()
                            player.playWhenReady = true
                            player.prepare()
                        }
                        LiveVideoFreezeRecoveryAction.ADVANCE_ROUTE -> {
                            val reason = "live video remained frozen after reconnect"
                            if (!tryNextRoute(reason, "Video stalled")) {
                                Logs.error("$reason for ${request.title}; no alternate route")
                                player.pause()
                                streamingStatusVisible = false
                                error = "Live video stopped updating. Reopen the channel to try again."
                            }
                        }
                    }
                }
            }
        } else {
            null
        }
        onDispose {
            if (player.duration > 0L) {
                playbackStore.save(progressKey, player.currentPosition, player.duration)
            }
            Logs.event("playback closed: ${request.title}")
            freezeMonitorJob?.cancel()
            player.clearVideoFrameMetadataListener(videoFrameMetadataListener)
            player.removeListener(listener)
            player.release()
            onProgressSaved()
        }
    }

    // Android 17 hardens background media starts. OpenStream playback is
    // always user initiated, and it pauses/saves as soon as the activity is no
    // longer visible instead of continuing unexpectedly in the background.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, player, progressKey) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) {
                if (player.duration > 0L) {
                    playbackStore.save(progressKey, player.currentPosition, player.duration)
                }
                player.pause()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // Desktop and picture-in-picture integration. The media session makes
    // hardware media keys and the PiP window's play/pause control work.
    val windowHost = remember(context) { context.playbackWindowHost() }
    val inPictureInPicture = windowHost?.inPictureInPicture?.value == true
    // Window mode changes arrive as configuration changes (no restart).
    val windowConfiguration = LocalConfiguration.current
    val fullscreenWindow = remember(windowConfiguration) { windowHost?.fullscreenWindow == true }
    val canToggleFullscreen = remember(windowConfiguration) { windowHost?.canToggleFullscreen == true }
    var playerViewRef by remember { mutableStateOf<PlayerView?>(null) }
    DisposableEffect(player) {
        val session = runCatching {
            MediaSession.Builder(context, player).setId("openstream-${System.identityHashCode(player)}").build()
        }.onFailure { Logs.warn("media session unavailable: ${it.message}") }.getOrNull()
        val windowListener = object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                windowHost?.updatePlayback(isPlaying, player.videoSize.width, player.videoSize.height)
                // Play/pause swaps its label after this; refresh the hover tooltips.
                playerViewRef?.let { view -> view.post { view.syncHoverTooltips() } }
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                windowHost?.updatePlayback(player.isPlaying, videoSize.width, videoSize.height)
            }
        }
        player.addListener(windowListener)
        windowHost?.setPlayerKeyHandler { event ->
            val fullKeyboard = event.device?.keyboardType == InputDevice.KEYBOARD_TYPE_ALPHABETIC
            val modified = event.isCtrlPressed || event.isAltPressed || event.isMetaPressed
            val fullscreen = windowHost.fullscreenWindow
            when (PlayerKeyboardPolicy.action(event.keyCode, fullKeyboard, modified, fullscreen)) {
                PlayerKeyAction.TOGGLE_PLAY -> Util.handlePlayPauseButtonAction(player)
                PlayerKeyAction.PLAY -> Util.handlePlayButtonAction(player)
                PlayerKeyAction.PAUSE -> Util.handlePauseButtonAction(player)
                PlayerKeyAction.SEEK_BACK, PlayerKeyAction.SEEK_FORWARD -> {
                    if (!player.isCurrentMediaItemSeekable) return@setPlayerKeyHandler false
                    val forward = event.keyCode in setOf(
                        KeyEvent.KEYCODE_DPAD_RIGHT,
                        KeyEvent.KEYCODE_L,
                        KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
                    )
                    player.seekTo(PlayerKeyboardPolicy.seekTarget(player.currentPosition, player.duration, forward))
                    playerViewRef?.showController()
                    true
                }
                PlayerKeyAction.TOGGLE_MUTE -> {
                    player.volume = if (player.volume > 0f) 0f else 1f
                    Logs.event("player ${if (player.volume == 0f) "muted" else "unmuted"} (keyboard)")
                    true
                }
                PlayerKeyAction.TOGGLE_FULLSCREEN, PlayerKeyAction.EXIT_FULLSCREEN -> {
                    if (!windowHost.canToggleFullscreen) return@setPlayerKeyHandler false
                    windowHost.toggleFullscreenWindow()
                    true
                }
                PlayerKeyAction.PICTURE_IN_PICTURE -> windowHost.enterPictureInPicture()
                PlayerKeyAction.NONE -> false
            }
        }
        onDispose {
            windowHost?.setPlayerKeyHandler(null)
            windowHost?.updatePlayback(false, 0, 0)
            player.removeListener(windowListener)
            session?.release()
        }
    }
    LaunchedEffect(inPictureInPicture) {
        if (inPictureInPicture) {
            playerViewRef?.hideController()
            chromeVisible = false
        }
    }

    var swipeStartNearBottom by remember { mutableStateOf(false) }
    var upwardDrag by remember { mutableFloatStateOf(0f) }
    var exitTriggered by remember { mutableStateOf(false) }
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        AndroidView(
            factory = { viewContext ->
                object : PlayerView(viewContext) {
                    private var liveGestureStartX = 0f
                    private var liveGestureStartY = 0f

                    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
                        if (request.isLive) {
                            when (event.actionMasked) {
                                MotionEvent.ACTION_DOWN -> {
                                    liveGestureStartX = event.x
                                    liveGestureStartY = event.y
                                }
                                MotionEvent.ACTION_UP -> {
                                    val direction = LivePlayerGesturePolicy.channelDirection(
                                        startX = liveGestureStartX,
                                        endX = event.x,
                                        deltaY = event.y - liveGestureStartY,
                                        screenWidthPx = width.toFloat(),
                                    )
                                    if (direction != 0) {
                                        Logs.event("live player swipe: ${if (direction > 0) "next" else "previous"} channel")
                                        currentLiveChannelChange(direction)
                                        return true
                                    }
                                }
                            }
                        }
                        return super.dispatchTouchEvent(event)
                    }
                }.apply {
                    // Disable and hide Media3's indicator before attaching an
                    // already-buffering player. Attaching first can flash its
                    // native circle underneath OpenStream's preparation panel.
                    setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
                    findViewById<View>(androidx.media3.ui.R.id.exo_buffering)?.visibility = View.GONE
                    this.player = player
                    // Always honor the encoded display aspect ratio. FIT keeps
                    // 4:3 and 16:9 channels proportional without cropping or
                    // stretching them to the tablet panel.
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                    setShowNextButton(false)
                    setShowPreviousButton(false)
                    setShowRewindButton(true)
                    setShowFastForwardButton(true)
                    // CC button opens the subtitle-track picker (embedded +
                    // side-loaded); the settings menu covers audio tracks.
                    setShowSubtitleButton(true)
                    controllerShowTimeoutMs = 3500
                    controllerAutoShow = false
                    setControllerVisibilityListener(
                        PlayerView.ControllerVisibilityListener { visibility ->
                            chromeVisible = visibility == View.VISIBLE
                            if (visibility == View.VISIBLE) syncHoverTooltips()
                        },
                    )
                    post { hideController() }
                    keepScreenOn = true
                    playerViewRef = this
                }
            },
            update = { playerView ->
                playerView.useController = !inPictureInPicture
                // AndroidView retains its PlayerView when a live-channel
                // change recomposes this screen. Move that surface to the
                // current ExoPlayer or audio can advance with no video output.
                if (playerView.player !== player) {
                    playerView.player = player
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
        // Limit the app-level Home gesture to the bottom edge where that
        // gesture starts. A full-screen drag detector prevents PlayerView from
        // receiving ordinary taps, which makes pause/audio/caption controls
        // inaccessible on touch devices.
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(28.dp)
                .pointerInput(onExit) {
                    detectVerticalDragGestures(
                        onDragStart = {
                            swipeStartNearBottom = true
                            upwardDrag = 0f
                            exitTriggered = false
                        },
                        onVerticalDrag = { change, dragAmount ->
                            if (!swipeStartNearBottom || exitTriggered) return@detectVerticalDragGestures
                            upwardDrag += -dragAmount
                            if (upwardDrag >= 96.dp.toPx()) {
                                exitTriggered = true
                                change.consume()
                                Logs.event("exit to launcher (swipe up from player)")
                                onExit()
                            }
                        },
                    )
                },
        )
        // Title, source, and back are part of the transient controller chrome:
        // touch or remote input reveals them; they never sit over the movie.
        if (chromeVisible && !inPictureInPicture) {
            Row(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .fillMaxWidth()
                    .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.60f), Color.Transparent)))
                    .padding(start = 6.dp, end = 16.dp, top = 6.dp, bottom = 22.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                HoverTooltip("Back") {
                    IconButton(onClick = onBack) {
                        Icon(AppIcons.Back, contentDescription = "Back", tint = Color.White)
                    }
                }
                Column(Modifier.padding(start = 4.dp)) {
                    Text(
                        request.title,
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 18.sp,
                    )
                    Text(
                        PlaybackRoutePresentation.compactLabel(
                            selectedVideoHeight,
                            playbackRoutes.getOrElse(activeRouteIndex) { request.uri },
                            request.offlineDownloadId != null,
                        ),
                        color = Color.White.copy(alpha = 0.72f),
                        fontSize = 13.sp,
                    )
                }
                // Desktop windows get pointer-reachable window controls; the
                // keyboard equivalents are F and P (see PlayerKeyboardPolicy).
                if (windowHost?.desktopWindowing == true) {
                    Spacer(Modifier.weight(1f))
                    OpenStreamTextButton(onClick = { windowHost.enterPictureInPicture() }) {
                        Text("Mini player", color = Color.White)
                    }
                    if (canToggleFullscreen) {
                        OpenStreamTextButton(onClick = { windowHost.toggleFullscreenWindow() }) {
                            Text(if (fullscreenWindow) "Exit full screen" else "Full screen", color = Color.White)
                        }
                    }
                }
            }
        }
        if (chromeVisible && !inPictureInPicture && request.isLive) {
            Surface(
                modifier = Modifier.align(Alignment.BottomEnd).padding(end = 140.dp, bottom = 18.dp),
                shape = RoundedCornerShape(8.dp),
                color = Color.Black.copy(alpha = 0.78f),
            ) {
                OpenStreamTextButton(
                    onClick = ::returnToLiveEdge,
                    modifier = Modifier.padding(horizontal = 2.dp),
                ) {
                    Text("●", color = Color(0xFFE50914), fontSize = 11.sp)
                    Text("  Live", color = Color.White, fontWeight = FontWeight.Bold)
                }
            }
        }
        if (formatIndicatorVisible && formatLabels.isNotEmpty()) {
            Surface(
                modifier = Modifier.align(Alignment.TopEnd).padding(20.dp),
                shape = RoundedCornerShape(8.dp),
                color = Color.Black.copy(alpha = 0.72f),
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 9.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    formatLabels.forEachIndexed { index, label ->
                        if (index > 0) Text("•", color = Color.White.copy(alpha = 0.55f))
                        Text(
                            label,
                            color = Color.White,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.ExtraBold,
                        )
                    }
                }
            }
        }
        if (PlayerLoadingUiPolicy.showPreparationOverlay(
                statusVisible = streamingStatusVisible,
                statusText = streamingStatusText,
                hasTerminalError = error != null,
                playWhenReady = player.playWhenReady,
            )
        ) {
            val remoteRoute = request.offlineDownloadId == null && !request.uri.startsWith("smb://")
            val statusHeading = PlayerLoadingUiPolicy.heading(
                isLive = request.isLive,
                isRemote = remoteRoute,
                isBuffering = player.playbackState == Player.STATE_BUFFERING,
                livePlaybackStarted = livePlaybackStarted,
            )
            Surface(
                modifier = Modifier
                    .align(Alignment.Center)
                    .widthIn(max = PlayerLoadingUiPolicy.overlayMaxWidthDp.dp)
                    .fillMaxWidth(PlayerLoadingUiPolicy.overlayWidthFraction),
                shape = RoundedCornerShape(12.dp),
                color = Color.Black.copy(alpha = 0.84f),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(
                        horizontal = PlayerLoadingUiPolicy.horizontalPaddingDp.dp,
                        vertical = PlayerLoadingUiPolicy.verticalPaddingDp.dp,
                    ),
                    horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    OpenStreamLoadingIndicator(
                        role = LoadingIndicatorRole.PLAYBACK,
                        color = Color.White,
                        trackColor = Color.White.copy(alpha = 0.22f),
                    )
                    Text(
                        statusHeading,
                        color = Color.White,
                        fontSize = PlayerLoadingUiPolicy.headingSizeSp.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
        val message = error
        if (message != null) {
            Surface(
                modifier = Modifier.align(Alignment.Center).widthIn(max = 560.dp).padding(horizontal = 24.dp),
                shape = RoundedCornerShape(12.dp),
                color = Color.Black.copy(alpha = 0.86f),
            ) {
                Column(
                    Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        if (request.isLive) "Channel unavailable" else "Playback failed",
                        color = Color.White,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        if (request.isLive) message else "$message. Try another title or source.",
                        color = Color.White.copy(alpha = 0.74f),
                        fontSize = 13.sp,
                    )
                    if (request.isLive) {
                        Text(
                            "Swipe left or right to try another channel.",
                            color = Color.White.copy(alpha = 0.56f),
                            fontSize = 12.sp,
                        )
                    }
                }
            }
        }
    }
}
