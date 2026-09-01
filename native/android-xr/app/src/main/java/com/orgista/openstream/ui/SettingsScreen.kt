package com.orgista.openstream.ui

import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.util.UnstableApi
import com.orgista.openstream.domain.ContentPolicy
import com.orgista.openstream.library.MetadataCredentialPolicy
import com.orgista.openstream.media.HdrCapabilityProbe
import com.orgista.openstream.media.MediaCapabilityReport
import com.orgista.openstream.media.SupportState
import com.orgista.openstream.offline.OfflineMediaRuntime
import com.orgista.openstream.offline.OfflineDeviceCapabilities
import com.orgista.openstream.offline.OfflineStorageLocation
import com.orgista.openstream.ui.icons.AppIcons
import com.orgista.openstream.trakt.TraktClient
import com.orgista.openstream.trakt.TraktDeviceAuthorization
import com.orgista.openstream.trakt.TraktStore
import com.orgista.openstream.streaming.BandwidthMeasurement
import com.orgista.openstream.streaming.BandwidthRuntime
import com.orgista.openstream.streaming.BandwidthStore
import com.orgista.openstream.arr.ArrClient
import com.orgista.openstream.arr.ArrConnection
import com.orgista.openstream.arr.ArrDownloadDestination
import com.orgista.openstream.arr.ArrEndpointPolicy
import com.orgista.openstream.arr.ArrKind
import com.orgista.openstream.arr.ArrStore
import com.orgista.openstream.transcode.TranscodeServerClient
import com.orgista.openstream.transcode.TranscodeServerConfig
import com.orgista.openstream.transcode.TranscodeServerEndpointPolicy
import com.orgista.openstream.transcode.TranscodeServerStore
import com.orgista.openstream.offline.OfflineProgressPolicy
import com.orgista.openstream.offline.OfflineBulkDeletePolicy
import com.orgista.openstream.storage.AppStorageManager
import com.orgista.openstream.storage.AppStorageUsage
import com.orgista.openstream.storage.StorageCleanupPolicy
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private fun rangeLabel(range: MediaCapabilityReport.DynamicRange): String = when (range) {
    MediaCapabilityReport.DynamicRange.SDR -> "SDR"
    MediaCapabilityReport.DynamicRange.HDR10 -> "HDR10"
    MediaCapabilityReport.DynamicRange.HDR10_PLUS -> "HDR10+"
    MediaCapabilityReport.DynamicRange.HLG -> "HLG"
    MediaCapabilityReport.DynamicRange.DOLBY_VISION -> "Dolby Vision"
}

private fun stateLabel(state: SupportState): String = when (state) {
    SupportState.SUPPORTED -> "Supported"
    SupportState.UNSUPPORTED -> "Unsupported"
    SupportState.RUNTIME_CHECK -> "Check on play"
}

private fun stateColor(state: SupportState): Color = when (state) {
    SupportState.SUPPORTED -> OpenStreamColors.Green
    SupportState.UNSUPPORTED -> OpenStreamColors.Danger
    SupportState.RUNTIME_CHECK -> OpenStreamColors.Amber
}

/** Device capability report (real decoder/display probes) plus family status. */
@OptIn(UnstableApi::class)
@Composable
fun SettingsScreen(
    policy: ContentPolicy,
    libraryStore: com.orgista.openstream.library.LibraryStore,
    offlineRuntime: OfflineMediaRuntime,
    onOpenSources: () -> Unit,
    onOpenChannelManager: () -> Unit,
    onTmdbKeyChanged: () -> Unit,
    onArrChanged: () -> Unit,
    onOfflineStorageChanged: (OfflineStorageLocation) -> Unit,
) {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val report = remember { HdrCapabilityProbe.inspect(context) }
    val deviceProfile = remember { OfflineDeviceCapabilities.inspect(context.applicationContext) }
    val scope = rememberCoroutineScope()
    val arrStore = remember { ArrStore(context.applicationContext) }
    val transcodeServerStore = remember { TranscodeServerStore(context.applicationContext) }
    val traktStore = remember { TraktStore(context.applicationContext) }
    val traktClient = remember { TraktClient(traktStore) }
    var tmdbKey by remember { mutableStateOf(libraryStore.tmdbApiKey) }
    var savedKey by remember { mutableStateOf(libraryStore.tmdbApiKey) }
    var omdbKey by remember { mutableStateOf(libraryStore.omdbApiKey) }
    var savedOmdb by remember { mutableStateOf(libraryStore.omdbApiKey) }
    var autoSubs by remember { mutableStateOf(libraryStore.autoSubtitles) }
    var deleteAfterWatched by remember { mutableStateOf(libraryStore.deleteOfflineAfterWatched) }
    var confirmDeleteAll by remember { mutableStateOf(false) }
    var deletingAll by remember { mutableStateOf(false) }
    var metadataOptIn by remember { mutableStateOf(libraryStore.metadataOptIn) }
    var savedMetadataOptIn by remember { mutableStateOf(libraryStore.metadataOptIn) }
    var traktClientId by remember { mutableStateOf(traktStore.credentials?.clientId.orEmpty()) }
    var traktClientSecret by remember { mutableStateOf(traktStore.credentials?.clientSecret.orEmpty()) }
    var traktConnected by remember { mutableStateOf(traktClient.connected) }
    var traktEnabled by remember { mutableStateOf(traktStore.syncEnabled) }
    var traktWorking by remember { mutableStateOf(false) }
    var traktAuthorization by remember { mutableStateOf<TraktDeviceAuthorization?>(null) }
    var traktError by remember { mutableStateOf<String?>(null) }
    var bandwidth by remember { mutableStateOf<BandwidthMeasurement?>(BandwidthStore(context).fresh()) }
    var bandwidthTesting by remember { mutableStateOf(false) }
    var bandwidthError by remember { mutableStateOf<String?>(null) }
    var arrDownloadDestination by remember { mutableStateOf(arrStore.downloadDestination) }
    val initialTranscodeConfig = remember { transcodeServerStore.load() }
    var transcodeEnabled by remember { mutableStateOf(initialTranscodeConfig?.enabled ?: false) }
    var transcodeBaseUrl by remember { mutableStateOf(initialTranscodeConfig?.baseUrl.orEmpty()) }
    var transcodeToken by remember { mutableStateOf(initialTranscodeConfig?.sessionToken.orEmpty()) }
    var transcodeTesting by remember { mutableStateOf(false) }
    var transcodeStatus by remember { mutableStateOf<String?>(null) }
    var storageUsage by remember { mutableStateOf(AppStorageUsage.EMPTY) }
    var storageMeasured by remember { mutableStateOf(false) }
    var storageAction by remember { mutableStateOf<String?>(null) }
    var confirmClearMetadata by remember { mutableStateOf(false) }
    val offlineEntries by offlineRuntime.entries.collectAsState()

    androidx.compose.runtime.LaunchedEffect(Unit) {
        storageUsage = withContext(Dispatchers.IO) {
            AppStorageManager.usage(context.applicationContext)
        }
        storageMeasured = true
    }

    androidx.compose.runtime.LaunchedEffect(offlineEntries.size, deletingAll) {
        if (offlineEntries.isEmpty()) {
            deletingAll = false
            confirmDeleteAll = false
        }
    }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
      Column(
        Modifier
            .widthIn(max = 1080.dp)
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(
                top = 16.dp,
                start = if (configuration.screenWidthDp >= 900) 48.dp else 24.dp,
                end = if (configuration.screenWidthDp >= 900) 48.dp else 24.dp,
            ),
        verticalArrangement = Arrangement.spacedBy(8.dp),
      ) {
        Text(
            "Settings",
            modifier = Modifier.padding(top = 16.dp).semantics { heading() },
            fontSize = 26.sp,
            fontWeight = FontWeight.ExtraBold,
            color = OpenStreamColors.Text,
        )

        Panel(
            "Sources",
            "Libraries, add-ons, live TV, and server connections for this device.",
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OpenStreamButton(onClick = onOpenSources) { Text("Open Sources") }
                OpenStreamOutlinedButton(onClick = onOpenChannelManager) {
                    Text("Channel Manager")
                }
            }
        }

        fun saveKeys() {
            libraryStore.metadataOptIn = metadataOptIn
            libraryStore.tmdbApiKey = tmdbKey
            libraryStore.omdbApiKey = omdbKey
            savedKey = tmdbKey
            savedOmdb = omdbKey
            savedMetadataOptIn = metadataOptIn
            onTmdbKeyChanged()
        }
        val dirty = tmdbKey != savedKey || omdbKey != savedOmdb || metadataOptIn != savedMetadataOptIn
        val tmdbFormatValid = tmdbKey.isBlank() || MetadataCredentialPolicy.looksLikeTmdbCredential(tmdbKey)

        Panel(
            "TMDB API",
            "TMDB provides title artwork, descriptions, cast, genres, and trailers. Create an API credential at themoviedb.org, then save it here for this device.",
        ) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        "Use metadata APIs",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = OpenStreamColors.Text,
                    )
                }
                Switch(
                    checked = metadataOptIn,
                    modifier = Modifier.toggleSemantics("Use metadata APIs", metadataOptIn),
                    onCheckedChange = { metadataOptIn = it },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Color.White,
                        checkedTrackColor = OpenStreamColors.Accent,
                    ),
                )
            }
            androidx.compose.material3.OutlinedTextField(
                value = tmdbKey,
                onValueChange = { tmdbKey = it.trim() },
                singleLine = true,
                label = { Text("TMDB API") },
                enabled = metadataOptIn,
                visualTransformation = PasswordVisualTransformation(),
                supportingText = if (!tmdbFormatValid) {
                    { Text("Enter a 32-character v3 key or a v4 read token.") }
                } else null,
                isError = !tmdbFormatValid,
                modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
                colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = OpenStreamColors.Accent.copy(alpha = 0.6f),
                    unfocusedBorderColor = OpenStreamColors.Border,
                ),
            )
        }

        Panel(
            "Rotten Tomatoes",
            "OpenStream reads Rotten Tomatoes, IMDb, and Metacritic ratings through OMDb. Get a key at omdbapi.com/apikey.aspx and save it here.",
        ) {
            androidx.compose.material3.OutlinedTextField(
                value = omdbKey,
                onValueChange = { omdbKey = it.trim() },
                singleLine = true,
                label = { Text("Rotten Tomatoes API") },
                enabled = metadataOptIn,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
                colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = OpenStreamColors.Accent.copy(alpha = 0.6f),
                    unfocusedBorderColor = OpenStreamColors.Border,
                ),
            )
        }

        OpenStreamButton(
            onClick = { saveKeys() },
            enabled = dirty && tmdbFormatValid,
            colors = androidx.compose.material3.ButtonDefaults.buttonColors(
                containerColor = OpenStreamColors.Accent,
                contentColor = Color.White,
            ),
        ) { Text(if (!metadataOptIn) "Save with metadata off" else "Save & re-scan") }

        Panel(
            "Server downloads",
            "Connect Radarr for movies and Sonarr for series. This sends download requests to your server; it does not add the server's files as an OpenStream library.",
        ) {
            Text(
                "Download button default",
                fontSize = 14.sp,
                fontWeight = FontWeight.ExtraBold,
                color = OpenStreamColors.Text,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ArrDownloadDestination.entries.forEach { destination ->
                    val title = when (destination) {
                        ArrDownloadDestination.ASK -> "Ask"
                        ArrDownloadDestination.DEVICE -> "This device"
                        ArrDownloadDestination.SERVER -> "Server"
                    }
                    ArrDownloadDestinationOption(
                        title = title,
                        selected = arrDownloadDestination == destination,
                    ) {
                        arrDownloadDestination = destination
                        arrStore.downloadDestination = destination
                    }
                }
            }
            ArrEditor(ArrKind.RADARR, arrStore, onArrChanged)
            ArrEditor(ArrKind.SONARR, arrStore, onArrChanged)
        }

        Panel(
            "Server transcoding",
            "Use an OpenStream gateway on your server when this device cannot direct-play a local NAS file.",
        ) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Use server transcoding", fontWeight = FontWeight.Bold, color = OpenStreamColors.Text, fontSize = 14.sp)
                }
                Switch(
                    checked = transcodeEnabled,
                    modifier = Modifier.toggleSemantics("Use server transcoding", transcodeEnabled),
                    onCheckedChange = { transcodeEnabled = it },
                    colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = OpenStreamColors.Accent),
                )
            }
            val transcodeUrlAllowed = transcodeBaseUrl.isBlank() || TranscodeServerEndpointPolicy.isAllowed(transcodeBaseUrl)
            androidx.compose.material3.OutlinedTextField(
                value = transcodeBaseUrl,
                onValueChange = { transcodeBaseUrl = it.trim(); transcodeStatus = null },
                singleLine = true,
                label = { Text("Gateway URL") },
                placeholder = { Text("http://192.168.1.87:8787") },
                isError = !transcodeUrlAllowed,
                supportingText = if (!transcodeUrlAllowed) {
                    { Text("Use HTTPS, or HTTP on a private LAN IP.") }
                } else null,
                modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
                colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = OpenStreamColors.Accent.copy(alpha = 0.6f),
                    unfocusedBorderColor = OpenStreamColors.Border,
                ),
            )
            androidx.compose.material3.OutlinedTextField(
                value = transcodeToken,
                onValueChange = { transcodeToken = it.trim(); transcodeStatus = null },
                singleLine = true,
                label = { Text("Gateway token") },
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
                colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = OpenStreamColors.Accent.copy(alpha = 0.6f),
                    unfocusedBorderColor = OpenStreamColors.Border,
                ),
            )
            transcodeStatus?.let {
                Text(it, color = if (it.startsWith("Ready")) OpenStreamColors.Green else OpenStreamColors.Muted, fontSize = 13.sp)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                OpenStreamButton(
                    enabled = transcodeUrlAllowed && (transcodeBaseUrl.isBlank() || transcodeToken.length >= 32),
                    onClick = {
                        if (transcodeBaseUrl.isBlank()) {
                            transcodeServerStore.remove()
                            transcodeStatus = "Server transcoding removed"
                        } else {
                            runCatching {
                                transcodeServerStore.save(
                                    TranscodeServerConfig(
                                        baseUrl = transcodeBaseUrl,
                                        sessionToken = transcodeToken,
                                        enabled = transcodeEnabled,
                                    ),
                                )
                            }.fold(
                                onSuccess = { transcodeStatus = "Saved" },
                                onFailure = { transcodeStatus = it.message ?: "Could not save gateway" },
                            )
                        }
                    },
                ) { Text("Save") }
                OpenStreamOutlinedButton(
                    enabled = !transcodeTesting && transcodeUrlAllowed && transcodeBaseUrl.isNotBlank() && transcodeToken.length >= 32,
                    onClick = {
                        transcodeTesting = true
                        transcodeStatus = "Testing…"
                        scope.launch {
                            val result = withContext(Dispatchers.IO) {
                                runCatching {
                                    TranscodeServerClient.capabilities(
                                        TranscodeServerConfig(
                                            baseUrl = transcodeBaseUrl,
                                            sessionToken = transcodeToken,
                                            enabled = transcodeEnabled,
                                        ),
                                    )
                                }
                            }
                            transcodeTesting = false
                            transcodeStatus = result.fold(
                                onSuccess = { capabilities ->
                                    if (capabilities.available) {
                                        "Ready · ffmpeg ${capabilities.version ?: ""}".trim()
                                    } else {
                                        "Gateway connected, but ffmpeg is unavailable"
                                    }
                                },
                                onFailure = { it.message ?: "Gateway test failed" },
                            )
                        }
                    },
                ) { Text(if (transcodeTesting) "Testing…" else "Test") }
            }
        }

        Panel(
            "Trakt",
            "Trakt can sync watch progress and resume points between OpenStream devices. A Trakt API app is required until OpenStream has publisher credentials.",
        ) {
            if (traktConnected) {
                Text("Connected", color = OpenStreamColors.Green, fontSize = 13.sp, fontWeight = FontWeight.Bold)
            }
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Sync playback", fontWeight = FontWeight.Bold, color = OpenStreamColors.Text, fontSize = 14.sp)
                }
                Switch(
                    checked = traktEnabled && traktConnected,
                    enabled = traktConnected,
                    modifier = Modifier.toggleSemantics("Sync playback with Trakt", traktEnabled && traktConnected),
                    onCheckedChange = { enabled -> traktEnabled = enabled; traktStore.syncEnabled = enabled },
                    colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = OpenStreamColors.Accent),
                )
            }
            if (!traktConnected) {
                androidx.compose.material3.OutlinedTextField(
                    value = traktClientId,
                    onValueChange = { traktClientId = it.trim() },
                    label = { Text("Trakt client ID") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
                )
                androidx.compose.material3.OutlinedTextField(
                    value = traktClientSecret,
                    onValueChange = { traktClientSecret = it.trim() },
                    label = { Text("Trakt client secret") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
                )
                traktAuthorization?.let { authorization ->
                    Text(
                        "At trakt.tv/activate enter code  ${authorization.userCode}",
                        fontWeight = FontWeight.ExtraBold,
                        color = OpenStreamColors.Cyan,
                        fontSize = 16.sp,
                    )
                }
                traktError?.let { Text(it, color = OpenStreamColors.Danger, fontSize = 13.sp) }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OpenStreamButton(
                        enabled = !traktWorking && traktClientId.isNotBlank() && traktClientSecret.isNotBlank(),
                        onClick = {
                            traktWorking = true
                            traktError = null
                            traktStore.saveCredentials(traktClientId, traktClientSecret)
                            scope.launch {
                                val authorizationResult = withContext(Dispatchers.IO) {
                                    runCatching { traktClient.beginDeviceAuthorization() }
                                }
                                authorizationResult.fold(
                                    onSuccess = { authorization ->
                                        traktAuthorization = authorization
                                        runCatching {
                                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(authorization.verificationUrl)))
                                        }
                                        val tokenResult = withContext(Dispatchers.IO) {
                                            runCatching { traktClient.awaitDeviceAuthorization(authorization) }
                                        }
                                        traktWorking = false
                                        tokenResult.fold(
                                            onSuccess = {
                                                traktConnected = true
                                                traktEnabled = true
                                                traktStore.syncEnabled = true
                                                traktAuthorization = null
                                            },
                                            onFailure = { traktError = it.message ?: "Trakt sign-in failed." },
                                        )
                                    },
                                    onFailure = {
                                        traktWorking = false
                                        traktError = it.message ?: "Trakt sign-in could not start."
                                    },
                                )
                            }
                        },
                    ) { Text(if (traktWorking) "Waiting for Trakt…" else "Connect Trakt") }
                    OpenStreamOutlinedButton(
                        onClick = {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://trakt.tv/oauth/applications")))
                        },
                    ) { Text("Create Trakt app") }
                }
            } else {
                OpenStreamOutlinedButton(
                    onClick = { traktStore.disconnect(); traktConnected = false; traktAuthorization = null },
                ) { Text("Disconnect Trakt") }
            }
        }

        Panel("Streaming") {
            bandwidthError?.let { Text(it, color = OpenStreamColors.Danger, fontSize = 13.sp) }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                OpenStreamOutlinedButton(
                    enabled = !bandwidthTesting,
                    onClick = {
                        bandwidthTesting = true
                        bandwidthError = null
                        scope.launch {
                            val result = runCatching {
                                BandwidthRuntime.currentOrMeasure(context.applicationContext, force = true)
                            }
                            bandwidthTesting = false
                            result.fold(
                                onSuccess = { bandwidth = it },
                                onFailure = { bandwidthError = it.message ?: "The speed test failed." },
                            )
                        }
                    },
                ) {
                    if (bandwidthTesting) {
                        OpenStreamLoadingLabel("Testing")
                    } else {
                        Text("Speed Test")
                    }
                }
                bandwidth?.let {
                    Text(
                        "${String.format(Locale.US, "%.1f", it.mbps)} Mbps",
                        color = OpenStreamColors.Green,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }

        Panel("Captions") {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        "Auto-On",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = OpenStreamColors.Text,
                    )
                }
                Switch(
                    checked = autoSubs,
                    modifier = Modifier.toggleSemantics("Automatically enable captions", autoSubs),
                    onCheckedChange = { autoSubs = it; libraryStore.autoSubtitles = it },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Color.White,
                        checkedTrackColor = OpenStreamColors.Accent,
                    ),
                )
            }
        }

        Panel(
            "Downloads",
            "Device downloads are optimized for this screen and stay in private app storage. Changing storage is available when no downloads are present.",
        ) {
            val storageStats = remember(offlineEntries) { offlineRuntime.storageStats() }
            Text(
                "${OfflineProgressPolicy.formatBytes(storageStats.availableBytes)} free · " +
                    "${OfflineProgressPolicy.formatBytes(storageStats.downloadedBytes)} currently available offline",
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = OpenStreamColors.Cyan,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OfflineStorageOption(
                    title = "Internal storage",
                    detail = "Built in",
                    selected = offlineRuntime.storageTarget.location == OfflineStorageLocation.INTERNAL,
                    enabled = offlineEntries.isEmpty(),
                ) { onOfflineStorageChanged(OfflineStorageLocation.INTERNAL) }
                OfflineStorageOption(
                    title = "SD card",
                    detail = if (offlineRuntime.storageTarget.removableAvailable) "Available" else "Not available",
                    selected = offlineRuntime.storageTarget.location == OfflineStorageLocation.SD_CARD,
                    enabled = offlineEntries.isEmpty() && offlineRuntime.storageTarget.removableAvailable,
                ) { onOfflineStorageChanged(OfflineStorageLocation.SD_CARD) }
            }
            SettingsToggleRow(
                title = "Delete After Watching",
                info = "Automatically removes a completed device download after playback is marked watched.",
                checked = deleteAfterWatched,
                onCheckedChange = {
                    deleteAfterWatched = it
                    libraryStore.deleteOfflineAfterWatched = it
                },
            )
            if (!confirmDeleteAll) {
                OpenStreamTextButton(
                    enabled = OfflineBulkDeletePolicy.canStart(offlineEntries.size, deletingAll),
                    onClick = { confirmDeleteAll = true },
                    colors = androidx.compose.material3.ButtonDefaults.textButtonColors(
                        contentColor = OpenStreamColors.Danger,
                    ),
                ) {
                    Icon(AppIcons.Close, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(
                        if (deletingAll) "Removing downloads…" else "Delete all downloads",
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
            } else {
                AlertDialog(
                    onDismissRequest = { confirmDeleteAll = false },
                    title = { Text("Delete all downloads?") },
                    text = { Text("This removes ${offlineEntries.size} downloaded item${if (offlineEntries.size == 1) "" else "s"} from this device.") },
                    dismissButton = { OpenStreamTextButton(onClick = { confirmDeleteAll = false }) { Text("Cancel") } },
                    confirmButton = {
                        OpenStreamTextButton(
                            onClick = {
                                if (OfflineBulkDeletePolicy.shouldRemove(
                                        confirming = confirmDeleteAll,
                                        downloadCount = offlineEntries.size,
                                        removing = deletingAll,
                                    )
                                ) {
                                    deletingAll = true
                                    confirmDeleteAll = false
                                    val count = offlineRuntime.removeAll()
                                    Toast.makeText(
                                        context,
                                        "Removing $count download${if (count == 1) "" else "s"}",
                                        Toast.LENGTH_SHORT,
                                    ).show()
                                }
                            },
                        ) { Text("Delete", color = OpenStreamColors.Danger) }
                    },
                )
            }
            if (offlineEntries.isNotEmpty()) {
                Text(
                    "Storage is locked while ${offlineEntries.size} offline ${if (offlineEntries.size == 1) "item exists" else "items exist"}. Remove them before switching locations.",
                    fontSize = 12.sp,
                    color = OpenStreamColors.Amber,
                )
            }
        }

        Panel(
            "Storage",
            "Cache includes artwork and temporary files. Metadata includes catalog indexes and title details. Downloads, settings, credentials, and playback history are never removed here.",
        ) {
            StorageCleanupRow(
                title = "Cache",
                detail = if (storageMeasured) {
                    "${StorageCleanupPolicy.formatBytes(storageUsage.cacheBytes)} used"
                } else {
                    "Measuring…"
                },
                actionLabel = "Clear cache",
                enabled = storageMeasured && storageAction == null && storageUsage.cacheBytes > 0L,
                working = storageAction == "cache",
                onClick = {
                    storageAction = "cache"
                    scope.launch {
                        storageUsage = withContext(Dispatchers.IO) {
                            AppStorageManager.clearCache(context.applicationContext)
                        }
                        storageAction = null
                        Toast.makeText(context, "Cache cleared", Toast.LENGTH_SHORT).show()
                    }
                },
            )
            StorageCleanupRow(
                title = "Metadata",
                detail = if (storageMeasured) {
                    "${StorageCleanupPolicy.formatBytes(storageUsage.metadataBytes)} used"
                } else {
                    "Measuring…"
                },
                actionLabel = "Clear metadata",
                enabled = storageMeasured && storageAction == null && storageUsage.metadataBytes > 0L,
                working = storageAction == "metadata",
                onClick = { confirmClearMetadata = true },
            )
        }

        if (confirmClearMetadata) {
            AlertDialog(
                onDismissRequest = { confirmClearMetadata = false },
                title = { Text("Clear metadata?") },
                text = { Text("Catalog indexes and saved title details will reload as you browse. Downloads and playback history will stay on this device.") },
                dismissButton = {
                    OpenStreamTextButton(onClick = { confirmClearMetadata = false }) { Text("Cancel") }
                },
                confirmButton = {
                    OpenStreamTextButton(
                        onClick = {
                            confirmClearMetadata = false
                            storageAction = "metadata"
                            scope.launch {
                                withContext(Dispatchers.IO) {
                                    AppStorageManager.clearMetadata(context.applicationContext)
                                }
                                kotlinx.coroutines.delay(2_000L)
                                storageUsage = withContext(Dispatchers.IO) {
                                    AppStorageManager.usage(context.applicationContext)
                                }
                                storageAction = null
                                Toast.makeText(context, "Metadata cleared", Toast.LENGTH_SHORT).show()
                            }
                        },
                    ) { Text("Clear", color = OpenStreamColors.Danger) }
                },
            )
        }

        Panel("Family & content") {
            when (policy) {
                is ContentPolicy.Kids -> {
                    SettingsValueRow(
                        title = "Kids Mode",
                        value = "On",
                        info = "Kids Mode is permanent for this installation and allows content up to ${policy.cap.label} (${policy.cap.examples}).",
                    )
                    InfoRow(AppIcons.Check, "Unrated content", "Always blocked", OpenStreamColors.Green)
                    InfoRow(
                        AppIcons.Check,
                        "Blocked terms",
                        if (policy.blockedTerms.isEmpty()) "None" else "${policy.blockedTerms.size} hidden",
                        OpenStreamColors.Green,
                    )
                }
                ContentPolicy.Standard -> SettingsValueRow(
                    title = "Kids Mode",
                    value = "Off",
                    info = "Kids Mode is chosen during setup and cannot be enabled later without reinstalling OpenStream.",
                )
            }
        }

        Panel(
            "Playback",
            buildString {
                append("Decoder input up to ${deviceProfile.maxDecodeWidth} × ${deviceProfile.maxDecodeHeight}. ")
                append("Dolby Vision profiles: ")
                append(report.dolbyVisionBitstreamProfiles().takeIf { it.isNotEmpty() }?.joinToString { "P$it" } ?: "none reported")
                append(". HEVC Main10: ${if (report.hasHevcMain10Decoder()) "available" else "unavailable"}. ")
                append("AV1 Main10: ${if (report.hasAv1Main10Decoder()) "available" else "unavailable"}.")
            },
        ) {
            InfoRow(
                AppIcons.Check,
                "Active display",
                "${deviceProfile.maxWidth} × ${deviceProfile.maxHeight} · playback and downloads capped to this display",
                OpenStreamColors.Green,
            )
            InfoRow(
                AppIcons.Check,
                "Audio output",
                if (deviceProfile.dolbyAtmos) "Dolby Atmos output detected" else "Standard surround / stereo output",
                if (deviceProfile.dolbyAtmos) OpenStreamColors.Green else OpenStreamColors.TextSoft,
            )
            MediaCapabilityReport.DynamicRange.entries.filter {
                report.playableState(it) == SupportState.SUPPORTED
            }.forEach { range ->
                val state = report.playableState(range)
                InfoRow(
                    icon = if (state == SupportState.SUPPORTED) AppIcons.Check else AppIcons.Warning,
                    title = rangeLabel(range),
                    detail = stateLabel(state),
                    tint = stateColor(state),
                )
            }
        }

        Panel("About") {
            Surface(
                onClick = {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/cyberbanksy")))
                },
                shape = RoundedCornerShape(10.dp),
                color = OpenStreamColors.SurfaceRaised,
            ) {
                Text(
                    "GitHub · cyberbanksy",
                    modifier = Modifier.fillMaxWidth().padding(14.dp),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    color = OpenStreamColors.Cyan,
                )
            }
        }
        androidx.compose.foundation.layout.Spacer(Modifier.heightIn(min = 36.dp))
      }
    }
}

private fun Modifier.toggleSemantics(label: String, checked: Boolean): Modifier = semantics {
    contentDescription = label
    stateDescription = if (checked) "Enabled" else "Disabled"
}

@Composable
private fun StorageCleanupRow(
    title: String,
    detail: String,
    actionLabel: String,
    enabled: Boolean,
    working: Boolean,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = OpenStreamColors.Text)
            Text(detail, fontSize = 12.sp, color = OpenStreamColors.Muted)
        }
        OpenStreamOutlinedButton(
            enabled = enabled,
            onClick = onClick,
        ) {
            if (working) OpenStreamLoadingLabel("Clearing") else Text(actionLabel)
        }
    }
}

@Composable
private fun ArrEditor(kind: ArrKind, store: ArrStore, onChanged: () -> Unit) {
    val scope = rememberCoroutineScope()
    var saved by remember(kind) { mutableStateOf(store.load(kind)) }
    var baseUrl by remember(kind) { mutableStateOf(saved?.baseUrl.orEmpty()) }
    var apiKey by remember(kind) { mutableStateOf(saved?.apiKey.orEmpty()) }
    var working by remember(kind) { mutableStateOf(false) }
    var message by remember(kind) { mutableStateOf<String?>(null) }
    var error by remember(kind) { mutableStateOf(false) }
    val valid = baseUrl.isNotBlank() && apiKey.isNotBlank() && ArrEndpointPolicy.isAllowed(baseUrl)

    Text(
        kind.displayName,
        modifier = Modifier.padding(top = 6.dp),
        fontSize = 15.sp,
        fontWeight = FontWeight.ExtraBold,
        color = OpenStreamColors.Text,
    )
    androidx.compose.material3.OutlinedTextField(
        value = baseUrl,
        onValueChange = { baseUrl = it.trim(); message = null },
        singleLine = true,
        label = { Text("${kind.displayName} address") },
        placeholder = { Text("http://192.168.1.20:${kind.defaultPort}") },
        supportingText = if (baseUrl.isNotBlank() && !ArrEndpointPolicy.isAllowed(baseUrl)) {
            { Text("Use HTTPS, or HTTP with a private local IP address.") }
        } else null,
        isError = baseUrl.isNotBlank() && !ArrEndpointPolicy.isAllowed(baseUrl),
        modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
    )
    androidx.compose.material3.OutlinedTextField(
        value = apiKey,
        onValueChange = { apiKey = it.trim(); message = null },
        singleLine = true,
        label = { Text("${kind.displayName} API key") },
        visualTransformation = PasswordVisualTransformation(),
        modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
    )
    message?.let {
        Text(it, fontSize = 12.sp, color = if (error) OpenStreamColors.Danger else OpenStreamColors.Green)
    }
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        OpenStreamButton(
            enabled = valid && !working,
            onClick = {
                val connection = ArrConnection(kind, kind.displayName, baseUrl, apiKey)
                val result = runCatching { store.save(connection) }
                result.onSuccess {
                    saved = connection
                    error = false
                    message = "Saved privately on this device."
                    onChanged()
                }.onFailure {
                    error = true
                    message = it.message ?: "Could not save this connection."
                }
            },
        ) { Text("Save") }
        OpenStreamOutlinedButton(
            enabled = valid && !working,
            onClick = {
                working = true
                message = null
                scope.launch {
                    val connection = ArrConnection(kind, kind.displayName, baseUrl, apiKey)
                    val result = withContext(Dispatchers.IO) { runCatching { ArrClient.test(connection) } }
                    working = false
                    result.onSuccess { status ->
                        store.save(connection)
                        saved = connection
                        error = false
                        onChanged()
                        message = buildString {
                            append("Connected to ").append(status.appName)
                            if (status.version.isNotBlank()) append(" ").append(status.version)
                            if (status.instanceName.isNotBlank()) append(" · ").append(status.instanceName)
                        }
                    }.onFailure {
                        error = true
                        message = it.message ?: "Could not reach ${kind.displayName}."
                    }
                }
            },
        ) {
            if (working) {
                OpenStreamLoadingLabel("Testing")
            } else {
                Text("Test")
            }
        }
        if (saved != null) {
            OpenStreamOutlinedButton(
                enabled = !working,
                onClick = {
                    store.remove(kind)
                    saved = null
                    baseUrl = ""
                    apiKey = ""
                    error = false
                    message = "Removed from this device."
                    onChanged()
                },
            ) { Text("Remove") }
        }
    }
}

@Composable
private fun OfflineStorageOption(
    title: String,
    detail: String,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .widthIn(min = 148.dp, max = 196.dp)
            .heightIn(min = 48.dp)
            .semantics {
                this.selected = selected
                role = Role.RadioButton
            },
        shape = OpenStreamShapes.Control,
        color = if (selected) OpenStreamColors.SurfaceRaised else OpenStreamColors.CanvasDeep,
        border = BorderStroke(
            1.dp,
            if (selected) OpenStreamColors.Cyan.copy(alpha = 0.65f) else OpenStreamColors.Border,
        ),
    ) {
        Row(
            Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                if (selected) AppIcons.Check else AppIcons.Storage,
                contentDescription = null,
                tint = when {
                    selected -> OpenStreamColors.Cyan
                    enabled -> OpenStreamColors.TextSoft
                    else -> OpenStreamColors.Muted
                },
                modifier = Modifier.size(16.dp),
            )
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(title, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = OpenStreamColors.Text)
                Text(detail, fontSize = 11.sp, color = OpenStreamColors.Muted)
            }
        }
    }
}

@Composable
private fun ArrDownloadDestinationOption(
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        modifier = Modifier
            .heightIn(min = 48.dp)
            .semantics {
                this.selected = selected
                role = Role.RadioButton
            },
        shape = OpenStreamShapes.Control,
        color = if (selected) OpenStreamColors.SurfaceRaised else OpenStreamColors.CanvasDeep,
        border = BorderStroke(
            1.dp,
            if (selected) OpenStreamColors.Cyan.copy(alpha = 0.65f) else OpenStreamColors.Border,
        ),
    ) {
        Row(
            Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
            horizontalArrangement = Arrangement.spacedBy(7.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                if (selected) AppIcons.Check else AppIcons.Download,
                contentDescription = null,
                tint = if (selected) OpenStreamColors.Cyan else OpenStreamColors.TextSoft,
                modifier = Modifier.size(15.dp),
            )
            Text(title, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = OpenStreamColors.Text)
        }
    }
}

@Composable
internal fun Panel(
    title: String,
    info: String? = null,
    actions: @Composable RowScope.() -> Unit = {},
    content: @Composable () -> Unit,
) {
    var showInfo by remember(title) { mutableStateOf(false) }
    val layout = SettingsSectionLayoutPolicy.current
    Column(
        Modifier.fillMaxWidth().padding(
            top = layout.topPaddingDp.dp,
            bottom = layout.bottomPaddingDp.dp,
        ),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                title,
                modifier = Modifier.semantics { heading() },
                fontSize = layout.headingSizeSp.sp,
                fontWeight = FontWeight.ExtraBold,
                color = OpenStreamColors.Text,
            )
            if (info != null) {
                SettingsInfoButton(label = "$title information", onClick = { showInfo = true })
            }
            Spacer(Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically) {
                actions()
            }
        }
        content()
    }
    if (showInfo && info != null) {
        AlertDialog(
            onDismissRequest = { showInfo = false },
            title = { Text(title) },
            text = { Text(info) },
            confirmButton = { OpenStreamTextButton(onClick = { showInfo = false }) { Text("Done") } },
        )
    }
}

@Composable
private fun SettingsInfoButton(label: String, onClick: () -> Unit) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(48.dp).semantics { contentDescription = label },
    ) {
        Surface(
            shape = CircleShape,
            color = Color.Transparent,
            border = BorderStroke(1.dp, OpenStreamColors.Muted),
        ) {
            androidx.compose.foundation.layout.Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
                Text("i", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = OpenStreamColors.TextSoft)
            }
        }
    }
}

@Composable
private fun SettingsToggleRow(
    title: String,
    info: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    var showInfo by remember(title) { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f),
            horizontalArrangement = Arrangement.spacedBy(9.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = OpenStreamColors.Text)
            SettingsInfoButton(label = "$title information", onClick = { showInfo = true })
        }
        Switch(
            checked = checked,
            modifier = Modifier.toggleSemantics(title, checked),
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = OpenStreamColors.Accent,
            ),
        )
    }
    if (showInfo) {
        AlertDialog(
            onDismissRequest = { showInfo = false },
            title = { Text(title) },
            text = { Text(info) },
            confirmButton = { OpenStreamTextButton(onClick = { showInfo = false }) { Text("Done") } },
        )
    }
}

@Composable
private fun SettingsValueRow(
    title: String,
    value: String,
    info: String,
) {
    var showInfo by remember(title) { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().heightIn(min = 44.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = OpenStreamColors.Text)
        Text(value, fontSize = 13.sp, color = OpenStreamColors.Muted)
        SettingsInfoButton(label = "$title information", onClick = { showInfo = true })
    }
    if (showInfo) {
        AlertDialog(
            onDismissRequest = { showInfo = false },
            title = { Text(title) },
            text = { Text(info) },
            confirmButton = { OpenStreamTextButton(onClick = { showInfo = false }) { Text("Done") } },
        )
    }
}

@Composable
private fun InfoRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    detail: String,
    tint: Color,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(11.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(17.dp))
        Text(title, fontWeight = FontWeight.Bold, color = OpenStreamColors.Text, fontSize = 14.sp)
        Text(detail, color = OpenStreamColors.Muted, fontSize = 13.sp)
    }
}
