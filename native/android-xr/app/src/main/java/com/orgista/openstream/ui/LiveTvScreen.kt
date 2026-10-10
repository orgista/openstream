package com.orgista.openstream.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.orgista.openstream.iptv.IptvCatalogPolicy
import com.orgista.openstream.iptv.IptvChannel
import com.orgista.openstream.iptv.IptvClient
import com.orgista.openstream.iptv.IptvGuideClient
import com.orgista.openstream.iptv.IptvGuideProgram
import com.orgista.openstream.iptv.IptvSource
import com.orgista.openstream.iptv.IptvPresentationPolicy
import com.orgista.openstream.iptv.IptvStore
import com.orgista.openstream.iptv.IptvSessionRefreshPolicy
import com.orgista.openstream.iptv.LiveChannelPackagePolicy
import com.orgista.openstream.iptv.LivePreparedGuide
import com.orgista.openstream.iptv.LivePreparedGuidePolicy
import com.orgista.openstream.iptv.LiveGuidePolicy
import com.orgista.openstream.ui.icons.AppIcons
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.abs

object LiveTvEmptyStatePolicy {
    fun message(online: Boolean, sourceLoadFailed: Boolean = false): String = when {
        !online -> "No channels"
        sourceLoadFailed -> "Channels unavailable"
        else -> "No channels"
    }
}

@Composable
fun LiveTvScreen(
    store: IptvStore,
    revision: Int,
    online: Boolean,
    kidsMode: Boolean,
    onManageChannels: () -> Unit,
    onBrowseDownloads: () -> Unit,
    onPlay: (IptvChannel) -> Unit,
) {
    val initialSession = remember { store.sessionSnapshot() }
    val initialPreparedGuide = remember(initialSession.preparedGuide, initialSession.revision, revision, kidsMode) {
        initialSession.preparedGuide?.takeIf { initialSession.revision == revision }?.takeUnless { prepared ->
            kidsMode && prepared.activeChannels.any {
                LiveChannelPackagePolicy.packageFor(it) != com.orgista.openstream.iptv.LiveChannelPackage.KIDS
            }
        }
    }
    var channels by remember { mutableStateOf(initialSession.channels) }
    var guidePrograms by remember { mutableStateOf(initialSession.programs) }
    var loading by remember { mutableStateOf(online && initialSession.channels.isEmpty()) }
    var guideLoading by remember { mutableStateOf(online && initialSession.programs.isEmpty()) }
    var error by remember { mutableStateOf<String?>(null) }
    var manualChannels by remember { mutableStateOf(store.manualChannels()) }
    var managerRevision by remember { mutableIntStateOf(0) }
    var retryRevision by remember { mutableIntStateOf(0) }
    var timeOffsetHalfHours by remember { mutableIntStateOf(0) }
    var nowMillis by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var preparedGuide by remember { mutableStateOf(initialPreparedGuide) }
    var preparingGuide by remember { mutableStateOf(online && initialPreparedGuide == null) }
    var firstGuidePaintLogged by remember { mutableStateOf(false) }

    val configuration = LocalConfiguration.current
    val layout = BrowseLayoutPolicy.resolve(
        widthDp = configuration.screenWidthDp.toFloat(),
        heightDp = configuration.screenHeightDp.toFloat(),
    )
    val edgePadding = layout.horizontalPaddingDp.dp

    LaunchedEffect(Unit) {
        com.orgista.openstream.Logs.event(
            "live screen entered: ${initialSession.channels.size} session channels, " +
                "prepared=${initialSession.preparedGuide != null}",
        )
        while (true) {
            delay(30_000)
            nowMillis = System.currentTimeMillis()
        }
    }

    LaunchedEffect(revision, online, retryRevision) {
        if (!online) {
            channels = emptyList()
            guidePrograms = emptyList()
            loading = false
            guideLoading = false
            error = "Live TV needs a network connection. Your downloaded movies and shows remain available in Discover."
            return@LaunchedEffect
        }

        val sources = store.sources()
        val currentManualChannels = store.manualChannels()
        val manualGuideCatalog = store.manualGuideCatalog(currentManualChannels)
        manualChannels = currentManualChannels
        val session = store.sessionSnapshot()
        val canReuseSession = IptvSessionRefreshPolicy.canReuse(session, revision, System.currentTimeMillis())
        if (!canReuseSession) {
            preparedGuide = null
            preparingGuide = true
        }
        if (canReuseSession) {
            channels = session.channels
            guidePrograms = session.programs
            manualChannels = store.manualChannels()
            loading = false
            guideLoading = false
            error = null
            if (session.programs.isEmpty()) {
                val cachedPrograms = withContext(Dispatchers.IO) {
                    (sources.map(IptvSource::id) + listOfNotNull(manualGuideCatalog?.source?.id))
                        .distinct()
                        .flatMap { sourceId ->
                            store.cachedGuidePrograms(sourceId, nowMillis)
                        }
                    }
                if (cachedPrograms.isNotEmpty()) {
                    guidePrograms = cachedPrograms
                    store.updateSessionGuidePrograms(cachedPrograms)
                }
            }
            return@LaunchedEffect
        }

        loading = true
        error = null
        val packagesForGuide = store.enabledPackageIds()
        val favoritesForGuide = store.favoriteChannelKeys()
        val cachedGuideBySource = withContext(Dispatchers.IO) {
            (sources.map(IptvSource::id) + listOfNotNull(manualGuideCatalog?.source?.id))
                .distinct()
                .associateWith { sourceId -> store.cachedGuidePrograms(sourceId, nowMillis) }
        }
        val quickCachedGuide = cachedGuideBySource.values.flatten()
        if (quickCachedGuide.isNotEmpty()) {
            guidePrograms = quickCachedGuide
            store.updateSessionGuidePrograms(quickCachedGuide)
        }

        val results = withContext(Dispatchers.IO) {
            coroutineScope {
                sources.map { source -> async { source to runCatching { IptvClient.loadCatalog(source) } } }.awaitAll()
            }
        }
        val configuredChannels = results.flatMap { it.second.getOrNull()?.channels.orEmpty() }
        val embeddedGuidePrograms = results.flatMap { (source, result) ->
            result.getOrNull()?.embeddedGuidePrograms.orEmpty().also { programs ->
                if (programs.isNotEmpty()) store.cacheGuidePrograms(source.id, programs)
            }
        }
        val mergedChannels = withContext(Dispatchers.Default) {
            IptvCatalogPolicy.mergeForPlayback(configuredChannels.distinctBy(IptvChannel::streamUrl))
        }
        channels = mergedChannels
        store.updateSessionChannels(mergedChannels + manualChannels)
        store.markSessionRefreshed(revision)
        loading = false

        val failed = results.filter { it.second.isFailure }
            .map { IptvPresentationPolicy.sourceName(it.first.name) }
            .distinct()
        results.filter { it.second.isFailure }.forEach { (source, result) ->
            com.orgista.openstream.Logs.warn(
                "live source refresh failed: ${IptvPresentationPolicy.sourceName(source.name)} " +
                    "(${result.exceptionOrNull()?.javaClass?.simpleName ?: "unknown"})",
            )
        }
        error = when {
            failed.isEmpty() -> null
            mergedChannels.isNotEmpty() || manualChannels.isNotEmpty() ->
                "Some sources could not refresh: ${failed.joinToString()}."
            else -> "No Live TV source could be refreshed."
        }

        val lineupForGuide = withContext(Dispatchers.Default) {
            val guideCandidates = if (kidsMode) {
                LiveChannelPackagePolicy.kidsChannels(mergedChannels + manualChannels)
            } else {
                mergedChannels + manualChannels
            }
            LiveChannelPackagePolicy.lineupChannels(
                channels = IptvCatalogPolicy.mergeForPlayback(guideCandidates),
                enabledPackageIds = packagesForGuide,
                favoriteChannelKeys = favoritesForGuide,
            )
        }
        val activeGuideKeys = lineupForGuide.mapTo(hashSetOf(), LiveChannelPackagePolicy::channelKey)
        val catalogs = (results.mapNotNull { it.second.getOrNull() } + listOfNotNull(manualGuideCatalog))
            .filter { it.guideUrls.isNotEmpty() }
            .map { catalog ->
                catalog.copy(
                    channels = catalog.channels.filter {
                        LiveChannelPackagePolicy.channelKey(it) in activeGuideKeys
                    },
                )
            }
            .filter { it.channels.isNotEmpty() }
        val cachedGuideByActiveSource = cachedGuideBySource.mapValues { (_, programs) ->
            programs.filter { it.channelKey in activeGuideKeys }
        }
        val cachedProviderGuide = cachedGuideByActiveSource.values.flatten()
        val activeEmbeddedGuide = embeddedGuidePrograms.filter { it.channelKey in activeGuideKeys }
        guidePrograms = (activeEmbeddedGuide + cachedProviderGuide)
            .distinctBy { "${it.channelKey}:${it.startMillis}:${it.title}" }
        val catalogsToRefresh = withContext(Dispatchers.IO) {
            catalogs.filterNot { catalog ->
                val cachedPrograms = cachedGuideByActiveSource[catalog.source.id].orEmpty()
                store.isGuideCacheFresh(catalog.source.id, nowMillis, cachedPrograms.isNotEmpty())
            }
        }
        guideLoading = catalogsToRefresh.isNotEmpty()
        if (guideLoading) {
            val guideStart = LiveGuidePolicy.windowStart(nowMillis, -4)
            val guideEnd = LiveGuidePolicy.windowStart(nowMillis, 96) + LiveGuidePolicy.WINDOW_MILLIS
            val freshProviderPrograms = withContext(Dispatchers.IO) {
                coroutineScope {
                    catalogsToRefresh.map { catalog -> async {
                            store.markGuideRefreshAttempt(catalog.source.id)
                            val programs = runCatching {
                                IptvGuideClient.load(catalog, guideStart, guideEnd)
                            }.getOrDefault(emptyList())
                            if (programs.isNotEmpty()) {
                                store.cacheGuidePrograms(catalog.source.id, programs)
                            }
                            programs
                        } }.awaitAll().flatten()
                }
            }
            guidePrograms = (activeEmbeddedGuide + freshProviderPrograms + cachedProviderGuide)
                .distinctBy { "${it.channelKey}:${it.startMillis}:${it.title}" }
            guideLoading = false
        }
        store.updateSessionGuidePrograms(guidePrograms)
        store.markSessionRefreshed(revision)
    }

    val favoriteChannelKeys = remember(managerRevision) { store.favoriteChannelKeys() }
    val enabledPackageIds = remember(managerRevision) { store.enabledPackageIds() }

    // Route merging and search normalization are deliberately not part of a
    // Compose remember calculation. A configured provider can expose 5,000+
    // channels and tens of thousands of guide rows; doing this work in
    // composition made the Discover → Live tap appear frozen. Retain the old
    // prepared model while its replacement is built so refreshes never blank
    // an already-visible guide.
    LaunchedEffect(channels, manualChannels, guidePrograms, managerRevision, online, guideLoading, kidsMode) {
        if (!online) {
            preparedGuide = null
            preparingGuide = false
            return@LaunchedEffect
        }
        val sourceChannels = if (kidsMode) {
            LiveChannelPackagePolicy.kidsChannels(channels + manualChannels)
        } else {
            channels + manualChannels
        }
        if (sourceChannels.isEmpty()) {
            preparedGuide = null
            preparingGuide = false
            return@LaunchedEffect
        }
        if (guideLoading && preparedGuide != null) {
            // Keep the already-painted guide usable while the catalog and EPG
            // refresh together. Rebuilding a 5k-channel search index once with
            // no schedules and again moments later with schedules caused two
            // multi-second allocation spikes on tablets.
            preparingGuide = false
            return@LaunchedEffect
        }
        if (preparedGuide == null) preparingGuide = true
        val startedAt = android.os.SystemClock.elapsedRealtime()
        val prepared = withContext(Dispatchers.Default) {
            LivePreparedGuidePolicy.build(
                channels = sourceChannels,
                programs = guidePrograms,
                enabledPackageIds = enabledPackageIds,
                favoriteChannelKeys = favoriteChannelKeys,
            )
        }
        preparedGuide = prepared
        store.updateSessionPreparedGuide(prepared)
        preparingGuide = false
        com.orgista.openstream.Logs.event(
            "live guide prepared in ${android.os.SystemClock.elapsedRealtime() - startedAt}ms: " +
                "${prepared.allChannels.size} catalog, ${prepared.activeChannels.size} visible, " +
                "${guidePrograms.size} programs",
        )
    }

    val allChannels = preparedGuide?.allChannels.orEmpty()
    val activeChannels = preparedGuide?.activeChannels.orEmpty()
    val guideByChannel = preparedGuide?.guideByChannel.orEmpty()

    LaunchedEffect(activeChannels) {
        if (!firstGuidePaintLogged && activeChannels.isNotEmpty()) {
            firstGuidePaintLogged = true
            com.orgista.openstream.Logs.event("live first guide paint: ${activeChannels.size} channels")
        }
    }

    val visibleChannels = activeChannels
    val channelWidth = if (layout.compact) 176.dp else 232.dp
    val laneWidth = configuration.screenWidthDp.dp - channelWidth - 1.dp
    val rowHeight = if (layout.compact) 68.dp else 76.dp
    val windowStart = LiveGuidePolicy.windowStart(nowMillis, timeOffsetHalfHours)
    val windowEnd = windowStart + LiveGuidePolicy.WINDOW_MILLIS

    Column(Modifier.fillMaxSize().background(OpenStreamColors.Canvas).padding(top = 16.dp)) {
        error?.takeIf { allChannels.isNotEmpty() }?.let {
            Text(
                it,
                modifier = Modifier
                    .padding(horizontal = edgePadding, vertical = 5.dp)
                    .semantics { liveRegion = LiveRegionMode.Polite },
                color = if (allChannels.isEmpty()) OpenStreamColors.TextSoft else OpenStreamColors.Amber,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        if ((loading || preparingGuide) && allChannels.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    OpenStreamLoadingIndicator(role = LoadingIndicatorRole.CONTENT)
                    Text("Loading channels", color = OpenStreamColors.TextSoft, fontSize = 13.sp)
                }
            }
        } else if (visibleChannels.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text(
                        LiveTvEmptyStatePolicy.message(
                            online = online,
                            sourceLoadFailed = error != null && allChannels.isEmpty(),
                        ),
                        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                        color = OpenStreamColors.TextSoft,
                    )
                    when {
                        !online -> OpenStreamButton(onClick = onBrowseDownloads) { Text("Downloads") }
                        error != null && allChannels.isEmpty() ->
                            OpenStreamButton(onClick = { retryRevision++ }) { Text("Retry") }
                        else -> OpenStreamButton(onClick = onManageChannels) { Text("Channel Manager") }
                    }
                }
            }
        } else {
            LiveGuideTimelineHeader(
                channelWidth = channelWidth,
                channelCount = visibleChannels.size,
                windowStartMillis = windowStart,
                atNow = timeOffsetHalfHours == 0,
                onPrevious = { if (timeOffsetHalfHours > -48) timeOffsetHalfHours-- },
                onNow = { timeOffsetHalfHours = 0 },
                onNext = { if (timeOffsetHalfHours < 96) timeOffsetHalfHours++ },
            )
            var accumulatedDrag by remember { mutableFloatStateOf(0f) }
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(timeOffsetHalfHours) {
                        detectHorizontalDragGestures(
                            onDragStart = { accumulatedDrag = 0f },
                            onDragEnd = {
                                if (abs(accumulatedDrag) > 56f) {
                                    timeOffsetHalfHours = (timeOffsetHalfHours + if (accumulatedDrag < 0) 1 else -1)
                                        .coerceIn(-48, 96)
                                }
                                accumulatedDrag = 0f
                            },
                            onHorizontalDrag = { change, dragAmount ->
                                change.consume()
                                accumulatedDrag += dragAmount
                            },
                        )
                    },
                contentPadding = PaddingValues(bottom = 28.dp),
            ) {
                itemsIndexed(
                    visibleChannels,
                    key = { _, channel -> LiveChannelPackagePolicy.channelKey(channel) },
                ) { index, channel ->
                    val key = LiveChannelPackagePolicy.channelKey(channel)
                    val programs = guideByChannel[key].orEmpty()
                    LiveGuideRow(
                        index = index,
                        channel = channel,
                        programs = programs,
                        favorite = key in favoriteChannelKeys,
                        channelWidth = channelWidth,
                        laneWidth = laneWidth,
                        rowHeight = rowHeight,
                        windowStartMillis = windowStart,
                        windowEndMillis = windowEnd,
                        nowMillis = nowMillis,
                        onFocused = {},
                        onPlay = { onPlay(channel) },
                        onToggleFavorite = {
                            store.setFavorite(channel, key !in favoriteChannelKeys)
                            managerRevision++
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun LiveGuideTimelineHeader(
    channelWidth: Dp,
    channelCount: Int,
    windowStartMillis: Long,
    atNow: Boolean,
    onPrevious: () -> Unit,
    onNow: () -> Unit,
    onNext: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().height(44.dp).background(OpenStreamColors.CanvasDeep),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.width(channelWidth).fillMaxHeight().padding(start = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Channels", color = OpenStreamColors.TextSoft, fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            Text("$channelCount", color = OpenStreamColors.Muted, fontSize = 11.sp)
            OpenStreamTextButton(onClick = onNow, enabled = !atNow) { Text("Now") }
        }
        HoverTooltip("Earlier") {
            IconButton(onClick = onPrevious, modifier = Modifier.size(48.dp)) {
                Icon(AppIcons.Back, contentDescription = "Earlier", tint = OpenStreamColors.TextSoft)
            }
        }
        Row(Modifier.weight(1f).fillMaxHeight()) {
            repeat(4) { index ->
                Box(
                    Modifier.weight(1f).fillMaxHeight().padding(start = 8.dp),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    Text(
                        if (index == 0 && atNow) "Now · ${formatTime(windowStartMillis)}" else formatTime(windowStartMillis + index * LiveGuidePolicy.HALF_HOUR_MILLIS),
                        color = if (index == 0 && atNow) OpenStreamColors.Accent else OpenStreamColors.Muted,
                        fontSize = 11.sp,
                        fontWeight = if (index == 0 && atNow) FontWeight.Bold else FontWeight.Normal,
                    )
                }
            }
        }
        HoverTooltip("Later") {
            IconButton(onClick = onNext, modifier = Modifier.size(48.dp)) {
                Icon(
                    AppIcons.Back,
                    contentDescription = "Later",
                    tint = OpenStreamColors.TextSoft,
                    modifier = Modifier.graphicsLayer(rotationZ = 180f),
                )
            }
        }
    }
}

@Composable
private fun LiveGuideRow(
    index: Int,
    channel: IptvChannel,
    programs: List<IptvGuideProgram>,
    favorite: Boolean,
    channelWidth: Dp,
    laneWidth: Dp,
    rowHeight: Dp,
    windowStartMillis: Long,
    windowEndMillis: Long,
    nowMillis: Long,
    onFocused: (IptvGuideProgram?) -> Unit,
    onPlay: () -> Unit,
    onToggleFavorite: () -> Unit,
) {
    Row(Modifier.fillMaxWidth().height(rowHeight)) {
        GuideChannelCell(
            index = index,
            channel = channel,
            favorite = favorite,
            width = channelWidth,
            onFocused = { onFocused(null) },
            onPlay = onPlay,
            onToggleFavorite = onToggleFavorite,
        )
        Box(Modifier.width(1.dp).fillMaxHeight().background(OpenStreamColors.Border))
        GuideProgramLane(
            channel = channel,
            programs = programs,
            laneWidth = laneWidth,
            windowStartMillis = windowStartMillis,
            windowEndMillis = windowEndMillis,
            nowMillis = nowMillis,
            onFocused = onFocused,
            onPlay = onPlay,
        )
    }
    Box(Modifier.fillMaxWidth().height(1.dp).background(OpenStreamColors.Border))
}

@Composable
private fun GuideChannelCell(
    index: Int,
    channel: IptvChannel,
    favorite: Boolean,
    width: Dp,
    onFocused: () -> Unit,
    onPlay: () -> Unit,
    onToggleFavorite: () -> Unit,
) {
    var focused by remember { mutableStateOf(false) }
    Surface(
        onClick = onPlay,
        modifier = Modifier.width(width).fillMaxHeight().onFocusChanged {
            focused = it.isFocused || it.hasFocus
            if (focused) onFocused()
        },
        color = if (focused) OpenStreamColors.AccentSoft else OpenStreamColors.Surface,
        border = if (focused) BorderStroke(2.dp, OpenStreamColors.Accent) else null,
    ) {
        Row(
            Modifier.fillMaxSize().padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                channel.channelNumber.ifBlank { (index + 1).toString().padStart(3, '0') },
                color = OpenStreamColors.Muted,
                fontSize = 11.sp,
                modifier = Modifier.width(31.dp),
                maxLines = 1,
            )
            Box(
                Modifier.size(36.dp).background(OpenStreamColors.CanvasDeep, RoundedCornerShape(5.dp)),
                contentAlignment = Alignment.Center,
            ) {
                if (channel.logoUrl.isNotBlank()) {
                    AsyncImage(
                        model = channel.logoUrl,
                        contentDescription = null,
                        modifier = Modifier.fillMaxSize().padding(4.dp),
                    )
                } else {
                    Text("LIVE", color = OpenStreamColors.Accent, fontWeight = FontWeight.ExtraBold, fontSize = 8.sp)
                }
            }
            Text(
                channel.name,
                modifier = Modifier.weight(1f),
                color = OpenStreamColors.Text,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            OpenStreamTextButton(
                onClick = onToggleFavorite,
                modifier = Modifier.semantics {
                    contentDescription = if (favorite) {
                        "Remove ${channel.name} from favorites"
                    } else {
                        "Add ${channel.name} to favorites"
                    }
                    stateDescription = if (favorite) "Favorite" else "Not favorite"
                    role = Role.Button
                },
                contentPadding = PaddingValues(2.dp),
            ) {
                Text(if (favorite) "★" else "☆", color = if (favorite) OpenStreamColors.Accent else OpenStreamColors.Muted, fontSize = 18.sp)
            }
        }
    }
}

@Composable
private fun GuideProgramLane(
    channel: IptvChannel,
    programs: List<IptvGuideProgram>,
    laneWidth: Dp,
    windowStartMillis: Long,
    windowEndMillis: Long,
    nowMillis: Long,
    onFocused: (IptvGuideProgram?) -> Unit,
    onPlay: () -> Unit,
) {
    val visible = remember(programs, windowStartMillis, windowEndMillis) {
        LiveGuidePolicy.programsFor(channel, programs, windowStartMillis, windowEndMillis)
    }
    Box(Modifier.fillMaxSize().clipToBounds().background(OpenStreamColors.CanvasDeep)) {
        repeat(4) { index ->
            if (index > 0) {
                Box(
                    Modifier.offset(x = laneWidth * (index / 4f)).width(1.dp).fillMaxHeight().background(OpenStreamColors.Border),
                )
            }
        }
        if (visible.isEmpty()) {
            GuideProgramCell(
                modifier = Modifier.fillMaxSize().padding(2.dp),
                program = null,
                nowMillis = nowMillis,
                onFocused = { onFocused(null) },
                onPlay = onPlay,
            )
        } else {
            visible.forEach { program ->
                val segment = LiveGuidePolicy.segment(program, windowStartMillis, windowEndMillis)
                val desiredWidth = laneWidth * segment.widthFraction
                GuideProgramCell(
                    modifier = Modifier
                        .offset(x = laneWidth * segment.startFraction)
                        .width(if (desiredWidth < 72.dp) 72.dp else desiredWidth)
                        .fillMaxHeight()
                        .padding(2.dp),
                    program = program,
                    nowMillis = nowMillis,
                    onFocused = { onFocused(program) },
                    onPlay = onPlay,
                )
            }
        }
        if (nowMillis in windowStartMillis until windowEndMillis) {
            val nowFraction = (nowMillis - windowStartMillis).toFloat() / (windowEndMillis - windowStartMillis).toFloat()
            Box(
                Modifier.offset(x = laneWidth * nowFraction).width(2.dp).fillMaxHeight().background(OpenStreamColors.Accent),
            )
        }
    }
}

@Composable
private fun GuideProgramCell(
    modifier: Modifier,
    program: IptvGuideProgram?,
    nowMillis: Long,
    onFocused: () -> Unit,
    onPlay: () -> Unit,
) {
    var focused by remember { mutableStateOf(false) }
    Surface(
        onClick = onPlay,
        modifier = modifier.onFocusChanged {
            focused = it.isFocused || it.hasFocus
            if (focused) onFocused()
        },
        shape = RoundedCornerShape(4.dp),
        color = if (focused) OpenStreamColors.SurfaceRaised else OpenStreamColors.Surface,
        border = BorderStroke(if (focused) 2.dp else 1.dp, if (focused) OpenStreamColors.Accent else OpenStreamColors.BorderStrong),
    ) {
        Box(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().padding(horizontal = 9.dp, vertical = 7.dp)) {
                Text(
                    program?.title ?: "Watch live",
                    color = OpenStreamColors.Text,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    program?.let { "${formatTime(it.startMillis)}–${formatTime(it.endMillis)}" } ?: "Schedule unavailable",
                    color = OpenStreamColors.Muted,
                    fontSize = 10.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (program != null && nowMillis in program.startMillis until program.endMillis) {
                val progress = ((nowMillis - program.startMillis).toFloat() / (program.endMillis - program.startMillis).toFloat()).coerceIn(0f, 1f)
                Box(
                    Modifier.align(Alignment.BottomStart).fillMaxWidth(progress).height(3.dp).background(OpenStreamColors.Accent),
                )
            }
        }
    }
}

private fun channelNumberValue(value: String): Double = value.toDoubleOrNull() ?: Double.MAX_VALUE

private val guideTimeFormatter = DateTimeFormatter.ofPattern("h:mm a")

private fun formatTime(epochMillis: Long): String =
    Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()).format(guideTimeFormatter)
