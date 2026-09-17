package com.orgista.openstream.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.os.Handler
import android.os.Looper
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import com.orgista.openstream.Logs
import com.orgista.openstream.data.ConnectionStore
import com.orgista.openstream.data.DiscoverFeedPreferences
import com.orgista.openstream.data.DiscoveredNas
import com.orgista.openstream.data.NasConnection
import com.orgista.openstream.data.NasDiscovery
import com.orgista.openstream.data.NasEntry
import com.orgista.openstream.data.Smb
import com.orgista.openstream.data.StremioClient
import com.orgista.openstream.data.StremioAddonPresentation
import com.orgista.openstream.data.StremioUrlPolicy
import com.orgista.openstream.data.YoutubeChannelClient
import com.orgista.openstream.library.LibraryFolderLinkPolicy
import com.orgista.openstream.library.LibraryKind
import com.orgista.openstream.library.LibraryStore
import com.orgista.openstream.lan.LanSetupServer
import com.orgista.openstream.lan.LanSetupSession
import com.orgista.openstream.lan.LanSetupPresentation
import com.orgista.openstream.lan.LanSetupQrCode
import com.orgista.openstream.lan.LanSetupMdnsResponder
import com.orgista.openstream.iptv.IptvStore
import com.orgista.openstream.ui.icons.AppIcons
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private fun formatSize(bytes: Long): String = when {
    bytes >= 1_000_000_000 -> "%.1f GB".format(bytes / 1_000_000_000.0)
    bytes >= 1_000_000 -> "${bytes / 1_000_000} MB"
    bytes > 0 -> "${bytes / 1_000} KB"
    else -> ""
}

/**
 * Sources management: SMB NAS shares (browsed and played directly, no
 * gateway) and Stremio add-ons. Hidden entirely in Kids Mode.
 */
@Composable
fun ConnectionsScreen(
    store: ConnectionStore,
    libraryStore: LibraryStore,
    indexing: Boolean,
    onAddLibrary: (NasConnection, String, LibraryKind) -> Unit,
    onRemoveLibrary: (String) -> Unit,
    onPlayNas: (NasConnection, NasEntry) -> Unit,
    iptvStore: IptvStore,
    onIptvChanged: () -> Unit,
    onOpenChannelManager: () -> Unit,
    onAddonsChanged: () -> Unit = {},
) {
    var revision by remember { mutableIntStateOf(0) }
    val nasConnections = remember(revision) { store.nasConnections() }
    val addons = remember(revision) { store.stremioAddons() }
    val youtubeChannels = remember(revision) { store.youtubeChannels() }
    var feedPreferences by remember(revision) { mutableStateOf(store.discoverFeedPreferences()) }
    val libraries = remember(revision, indexing) { libraryStore.folders() }
    var browsing by remember { mutableStateOf<NasConnection?>(null) }
    var showAddNas by remember { mutableStateOf(false) }
    var showAddAddon by remember { mutableStateOf(false) }
    var showAddYoutube by remember { mutableStateOf(false) }
    var deletingCollection by remember { mutableStateOf<SourceCollection?>(null) }
    var testingAddonId by remember { mutableStateOf<String?>(null) }
    var addonTestResults by remember { mutableStateOf<Map<String, com.orgista.openstream.data.StremioAddonTestResult>>(emptyMap()) }
    var lanSession by remember { mutableStateOf<LanSetupSession?>(null) }
    var lanError by remember { mutableStateOf<String?>(null) }
    var lanStarting by remember { mutableStateOf(false) }
    var lanCopied by remember { mutableStateOf(false) }
    var lanFriendlyAddressActive by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mainHandler = remember { Handler(Looper.getMainLooper()) }
    val lanMdnsResponder = remember { LanSetupMdnsResponder(context.applicationContext) }
    val lanServer = remember {
        LanSetupServer(
            addManifest = { manifest ->
                val addon = StremioClient.loadAddon(manifest)
                store.addStremio(addon)
                addon.name
            },
            onAdded = { name ->
                mainHandler.post {
                    lanMdnsResponder.close()
                    lanSession = null
                    lanFriendlyAddressActive = false
                    revision++
                    onAddonsChanged()
                    Logs.event("add-on connected from temporary LAN setup: $name")
                }
            },
        )
    }
    DisposableEffect(lanServer, lanMdnsResponder) {
        onDispose {
            lanMdnsResponder.close()
            lanServer.close()
        }
    }
    LaunchedEffect(lanSession?.expiresAtMillis) {
        val session = lanSession ?: return@LaunchedEffect
        delay((session.expiresAtMillis - System.currentTimeMillis()).coerceAtLeast(0L))
        if (lanSession == session) {
            lanMdnsResponder.close()
            lanServer.close()
            lanSession = null
            lanFriendlyAddressActive = false
        }
    }

    val active = browsing
    if (active != null) {
        NasBrowser(
            connection = active,
            onBack = { browsing = null },
            onPlay = { entry -> onPlayNas(active, entry) },
            onAddLibrary = { path, kind -> onAddLibrary(active, path, kind) },
        )
        return
    }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
      LazyColumn(
        Modifier.fillMaxHeight().widthIn(max = 1080.dp).fillMaxWidth().padding(horizontal = 24.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(top = 16.dp, bottom = 36.dp),
      ) {
        item {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text(
                        "Sources",
                        modifier = Modifier.semantics { heading() },
                        fontSize = 30.sp,
                        fontWeight = FontWeight.ExtraBold,
                        color = OpenStreamColors.Text,
                    )
                    Text("Libraries, add-ons, YouTube, and Live TV", fontSize = 13.sp, color = OpenStreamColors.Muted)
                }
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    OpenStreamOutlinedButton(
                        enabled = !lanStarting,
                        onClick = {
                            lanError = null
                            lanStarting = true
                            scope.launch {
                                val result = withContext(Dispatchers.IO) {
                                    runCatching {
                                        val session = lanServer.start()
                                        session to lanMdnsResponder.start(session)
                                    }
                                }
                                lanStarting = false
                                result.fold(
                                    onSuccess = { (session, friendlyAddressActive) ->
                                        lanSession = session
                                        lanFriendlyAddressActive = friendlyAddressActive
                                        lanCopied = false
                                    },
                                    onFailure = {
                                        lanMdnsResponder.close()
                                        lanServer.close()
                                        lanError = it.message ?: "Local setup could not start."
                                    },
                                )
                            }
                        },
                    ) { Text(if (lanStarting) "Starting…" else "Web Management") }
                }
            }
        }

        lanSession?.let { session ->
            item {
                Surface(
                    shape = RoundedCornerShape(10.dp),
                    color = OpenStreamColors.SurfaceRaised,
                    border = BorderStroke(1.dp, OpenStreamColors.BorderStrong),
                ) {
                    Row(
                        Modifier.fillMaxWidth().padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(18.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text("Connect from a computer", fontWeight = FontWeight.Bold, color = OpenStreamColors.Text)
                            Text("On the same Wi-Fi, type this address into any browser.", color = OpenStreamColors.Muted, fontSize = 13.sp)
                            SelectionContainer {
                                Text(
                                    if (lanFriendlyAddressActive) {
                                        LanSetupPresentation.computerAddress(session)
                                    } else {
                                        LanSetupPresentation.fallbackComputerAddress(session)
                                    },
                                    color = OpenStreamColors.Text,
                                    fontFamily = FontFamily.Monospace,
                                    fontSize = 17.sp,
                                )
                            }
                            if (lanFriendlyAddressActive) {
                                SelectionContainer {
                                    Text(
                                        "If that doesn't open: ${LanSetupPresentation.fallbackComputerAddress(session)}",
                                        color = OpenStreamColors.Muted,
                                        fontFamily = FontFamily.Monospace,
                                        fontSize = 12.sp,
                                    )
                                }
                            }
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                OpenStreamTextButton(
                                    onClick = {
                                        val copiedUrl = if (lanFriendlyAddressActive) {
                                            LanSetupPresentation.computerUrl(session)
                                        } else {
                                            LanSetupPresentation.fallbackComputerUrl(session)
                                        }
                                        context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(
                                            ClipData.newPlainText("OpenStream setup", copiedUrl),
                                        )
                                        lanCopied = true
                                    },
                                ) { Text(if (lanCopied) "Copied" else "Copy address") }
                                Text("Available for 10 minutes", color = OpenStreamColors.Muted, fontSize = 12.sp)
                            }
                        }
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Surface(
                                shape = RoundedCornerShape(8.dp),
                                color = androidx.compose.ui.graphics.Color.White,
                            ) {
                                Image(
                                    bitmap = remember(session.url) {
                                        LanSetupQrCode.imageBitmap(LanSetupPresentation.qrContent(session))
                                    },
                                    contentDescription = "Scan to open setup page",
                                    modifier = Modifier.padding(7.dp).size(104.dp),
                                )
                            }
                            Text("Or scan", color = OpenStreamColors.Muted, fontSize = 11.sp)
                        }
                        OpenStreamTextButton(
                            onClick = {
                                lanMdnsResponder.close()
                                lanServer.close()
                                lanSession = null
                                lanFriendlyAddressActive = false
                            },
                        ) { Text("Stop") }
                    }
                }
            }
        }
        lanError?.let { message -> item { Text(message, color = OpenStreamColors.Danger, fontSize = 13.sp) } }

        if (libraries.isNotEmpty()) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SourceSectionHeading(
                        title = "Libraries",
                        info = "Folders added to your OpenStream library. Remove a folder here without deleting its files from the server.",
                    ) {
                        DeleteModeButton(
                            collection = SourceCollection.LIBRARIES,
                            activeCollection = deletingCollection,
                            itemCount = libraries.size,
                            onClick = {
                                deletingCollection = SourceManagementPolicy.nextDeleteCollection(
                                    SourceCollection.LIBRARIES,
                                    deletingCollection,
                                )
                            },
                        )
                    }
                    if (indexing) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            OpenStreamLoadingIndicator(role = LoadingIndicatorRole.INLINE)
                            Text("Scanning & fetching metadata…", fontSize = 12.sp, color = OpenStreamColors.Accent)
                        }
                    }
                }
            }
            items(libraries, key = { it.id }) { folder ->
                val missingShare = LibraryFolderLinkPolicy.isOrphaned(folder, nasConnections)
                FlatSourceRow {
                    Icon(
                        AppIcons.Folder,
                        contentDescription = null,
                        tint = if (missingShare) OpenStreamColors.Amber else OpenStreamColors.Accent,
                    )
                    Column(Modifier.weight(1f)) {
                        Text(
                            "${folder.connectionName} / ${folder.path.ifBlank { "(root)" }}",
                            fontWeight = FontWeight.Bold,
                            color = OpenStreamColors.Text,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            if (missingShare) {
                                "Share not connected — add \"${folder.connectionName}\" under NAS shares to index this folder"
                            } else {
                                when (folder.kind) {
                                    LibraryKind.MOVIES -> "Movies library"
                                    LibraryKind.TV -> "TV library"
                                    LibraryKind.AUTO -> "Auto-organized library"
                                }
                            },
                            fontSize = 13.sp,
                            color = if (missingShare) OpenStreamColors.Amber else OpenStreamColors.Muted,
                        )
                    }
                    AnimatedVisibility(
                        visible = SourceManagementPolicy.showRemoveControl(SourceCollection.LIBRARIES, deletingCollection),
                    ) {
                        IconButton(onClick = {
                            onRemoveLibrary(folder.id)
                            if (libraries.size == 1) deletingCollection = null
                            revision++
                        }) {
                            Icon(
                                AppIcons.Close,
                                contentDescription = "Delete ${folder.connectionName} library",
                                tint = OpenStreamColors.Danger,
                            )
                        }
                    }
                }
            }
        }

        item {
            SourceSectionHeading(
                title = "NAS shares",
                info = "Network storage connected over SMB. Tap a share to browse it or add one of its folders to the library.",
            ) {
                OpenStreamTextButton(onClick = {
                    deletingCollection = null
                    showAddNas = true
                }) { Text("Add NAS share") }
                DeleteModeButton(
                    collection = SourceCollection.NAS_SHARES,
                    activeCollection = deletingCollection,
                    itemCount = nasConnections.size,
                    onClick = {
                        deletingCollection = SourceManagementPolicy.nextDeleteCollection(
                            SourceCollection.NAS_SHARES,
                            deletingCollection,
                        )
                    },
                )
            }
        }
        if (nasConnections.isEmpty()) {
            item { Text("No NAS shares yet. Add your server's host and share name.", color = OpenStreamColors.Muted, fontSize = 14.sp) }
        }
        items(nasConnections, key = { it.id }) { connection ->
            FlatSourceRow(modifier = Modifier.clickable { browsing = connection }) {
                Icon(AppIcons.Storage, contentDescription = null, tint = OpenStreamColors.Accent)
                Column(Modifier.weight(1f)) {
                    Text(connection.name, fontWeight = FontWeight.Bold, color = OpenStreamColors.Text)
                    Text("smb://${connection.host}/${connection.share}", fontSize = 13.sp, color = OpenStreamColors.Muted)
                }
                AnimatedVisibility(
                    visible = SourceManagementPolicy.showRemoveControl(SourceCollection.NAS_SHARES, deletingCollection),
                ) {
                    IconButton(onClick = {
                        store.removeNas(connection.id)
                        if (nasConnections.size == 1) deletingCollection = null
                        revision++
                    }) {
                        Icon(
                            AppIcons.Close,
                            contentDescription = "Delete NAS share ${connection.name}",
                            tint = OpenStreamColors.Danger,
                        )
                    }
                }
            }
        }

        item {
            SourceSectionHeading(
                title = "Discover feed",
                info = "Choose which source groups appear in Discover and arrange their order. Turning off a group hides its rows without removing the source or its saved configuration.",
            )
        }
        items(feedPreferences.order, key = { "discover-${it.name}" }) { group ->
            FlatSourceRow {
                Column(Modifier.weight(1f)) {
                    Text(group.displayName, fontWeight = FontWeight.Bold, color = OpenStreamColors.Text)
                    Text(group.description, fontSize = 13.sp, color = OpenStreamColors.TextSoft)
                }
                OpenStreamTextButton(
                    modifier = Modifier.semantics { contentDescription = "Move ${group.displayName} up" },
                    enabled = feedPreferences.order.firstOrNull() != group,
                    onClick = {
                        feedPreferences = feedPreferences.move(group, -1)
                        store.saveDiscoverFeedPreferences(feedPreferences)
                        revision++
                        onAddonsChanged()
                    },
                ) { Text("Up") }
                OpenStreamTextButton(
                    modifier = Modifier.semantics { contentDescription = "Move ${group.displayName} down" },
                    enabled = feedPreferences.order.lastOrNull() != group,
                    onClick = {
                        feedPreferences = feedPreferences.move(group, 1)
                        store.saveDiscoverFeedPreferences(feedPreferences)
                        revision++
                        onAddonsChanged()
                    },
                ) { Text("Down") }
                Switch(
                    checked = group in feedPreferences.visibleGroups,
                    modifier = Modifier.semantics {
                        contentDescription = "Show ${group.displayName} in Discover"
                        stateDescription = if (group in feedPreferences.visibleGroups) "Shown" else "Hidden"
                    },
                    onCheckedChange = { visible ->
                        feedPreferences = feedPreferences.withVisibility(group, visible)
                        store.saveDiscoverFeedPreferences(feedPreferences)
                        revision++
                        onAddonsChanged()
                    },
                )
            }
        }

        item {
            SourceSectionHeading(
                title = "YouTube",
                info = "Add an exact channel or @handle. Every enabled channel appears inside the YouTube group and contributes likely new uploads to Up Next. No YouTube API key is required.",
            ) {
                OpenStreamTextButton(onClick = {
                    deletingCollection = null
                    showAddYoutube = true
                }) { Text("Add YouTube channel") }
                DeleteModeButton(
                    collection = SourceCollection.YOUTUBE,
                    activeCollection = deletingCollection,
                    itemCount = youtubeChannels.size,
                    onClick = {
                        deletingCollection = SourceManagementPolicy.nextDeleteCollection(
                            SourceCollection.YOUTUBE,
                            deletingCollection,
                        )
                    },
                )
            }
        }
        if (youtubeChannels.isEmpty()) {
            item { Text("No YouTube channels yet.", color = OpenStreamColors.Muted, fontSize = 14.sp) }
        }
        items(youtubeChannels, key = { it.id }) { channel ->
            FlatSourceRow {
                Icon(AppIcons.Play, contentDescription = null, tint = OpenStreamColors.Text)
                Column(Modifier.weight(1f)) {
                    Text(channel.name, fontWeight = FontWeight.Bold, color = OpenStreamColors.Text)
                    Text("Adds recent uploads to Discover", fontSize = 13.sp, color = OpenStreamColors.TextSoft)
                    Text(
                        "youtube.com/channel/${channel.channelId}",
                        fontSize = 12.sp,
                        color = OpenStreamColors.Muted,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Switch(
                    checked = channel.enabled,
                    modifier = Modifier.semantics {
                        contentDescription = "Show ${channel.name} in Discover"
                        stateDescription = if (channel.enabled) "Enabled" else "Disabled"
                    },
                    onCheckedChange = { enabled ->
                        store.setYoutubeChannelEnabled(channel.id, enabled)
                        revision++
                        onAddonsChanged()
                    },
                )
                AnimatedVisibility(
                    visible = SourceManagementPolicy.showRemoveControl(SourceCollection.YOUTUBE, deletingCollection),
                ) {
                    IconButton(onClick = {
                        store.removeYoutubeChannel(channel.id)
                        if (youtubeChannels.size == 1) deletingCollection = null
                        revision++
                        onAddonsChanged()
                    }) {
                        Icon(
                            AppIcons.Close,
                            contentDescription = "Delete YouTube channel ${channel.name}",
                            tint = OpenStreamColors.Danger,
                        )
                    }
                }
            }
        }

        item {
            SourceSectionHeading(
                title = "Add-Ons",
                info = "Add-ons provide catalogs, metadata, or HTTPS playback routes. Private manifest paths stay on this device.",
            ) {
                OpenStreamTextButton(onClick = {
                    deletingCollection = null
                    showAddAddon = true
                }) { Text("Add add-on") }
                DeleteModeButton(
                    collection = SourceCollection.ADD_ONS,
                    activeCollection = deletingCollection,
                    itemCount = addons.size,
                    onClick = {
                        deletingCollection = SourceManagementPolicy.nextDeleteCollection(
                            SourceCollection.ADD_ONS,
                            deletingCollection,
                        )
                    },
                )
            }
        }
        if (addons.isEmpty()) {
            item { Text("No add-ons yet. Paste an add-on manifest URL to connect one.", color = OpenStreamColors.Muted, fontSize = 14.sp) }
        }
        items(addons, key = { it.id }) { addon ->
            FlatSourceRow {
                Icon(AppIcons.Check, contentDescription = null, tint = OpenStreamColors.Green)
                Column(Modifier.weight(1f)) {
                    Text(addon.name, fontWeight = FontWeight.Bold, color = OpenStreamColors.Text)
                    Text(
                        StremioAddonPresentation.usage(addon),
                        fontSize = 13.sp,
                        color = OpenStreamColors.TextSoft,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        StremioUrlPolicy.safeLabel(addon.transportUrl),
                        fontSize = 12.sp,
                        color = OpenStreamColors.Muted,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                val testing = testingAddonId == addon.id
                val testResult = addonTestResults[addon.id]
                IconButton(
                    modifier = Modifier.semantics {
                        contentDescription = AddonTestIndicatorPolicy.contentDescription(addon.name, testing, testResult)
                    },
                    enabled = testingAddonId == null,
                    onClick = {
                        testingAddonId = addon.id
                        addonTestResults = addonTestResults - addon.id
                        scope.launch {
                            val result = withContext(Dispatchers.IO) { StremioClient.testAddon(addon) }
                            addonTestResults = addonTestResults + (addon.id to result)
                            testingAddonId = null
                            Logs.event("add-on test ${if (result.working) "passed" else "failed"}: ${addon.name}")
                        }
                    },
                ) {
                    when (AddonTestIndicatorPolicy.state(testing, testResult)) {
                        AddonTestIndicatorState.READY -> Icon(
                            AppIcons.Refresh,
                            contentDescription = null,
                            tint = OpenStreamColors.TextSoft,
                            modifier = Modifier.size(21.dp),
                        )
                        AddonTestIndicatorState.TESTING -> OpenStreamLoadingIndicator(role = LoadingIndicatorRole.INLINE)
                        AddonTestIndicatorState.PASSED -> Icon(
                            AppIcons.Check,
                            contentDescription = null,
                            tint = OpenStreamColors.Green,
                            modifier = Modifier.size(22.dp),
                        )
                        AddonTestIndicatorState.FAILED -> Icon(
                            AppIcons.Close,
                            contentDescription = null,
                            tint = OpenStreamColors.Danger,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                }
                Switch(
                    checked = addon.enabled,
                    modifier = Modifier.semantics {
                        contentDescription = "Enable ${addon.name}"
                        stateDescription = if (addon.enabled) "Enabled" else "Disabled"
                    },
                    onCheckedChange = { enabled ->
                        store.setStremioEnabled(addon.id, enabled)
                        revision++
                        onAddonsChanged()
                    },
                )
                AnimatedVisibility(
                    visible = SourceManagementPolicy.showRemoveControl(SourceCollection.ADD_ONS, deletingCollection),
                ) {
                    IconButton(onClick = {
                        store.removeStremio(addon.id)
                        if (addons.size == 1) deletingCollection = null
                        revision++
                        onAddonsChanged()
                    }) {
                        Icon(
                            AppIcons.Close,
                            contentDescription = "Delete add-on ${addon.name}",
                            tint = OpenStreamColors.Danger,
                        )
                    }
                }
            }
        }

        item(key = "live-sources") {
            IptvSettingsPanel(
                store = iptvStore,
                onChanged = onIptvChanged,
                onOpenChannelManager = onOpenChannelManager,
            )
        }
      }
    }

    if (showAddNas) {
        AddNasDialog(
            store = store,
            onDone = { added ->
                showAddNas = false
                if (added) revision++
            },
        )
    }
    if (showAddAddon) {
        AddAddonDialog(
            store = store,
            onDone = { added ->
                showAddAddon = false
                if (added) {
                    revision++
                    onAddonsChanged()
                }
            },
        )
    }
    if (showAddYoutube) {
        AddYoutubeChannelDialog(
            store = store,
            onDone = { added ->
                showAddYoutube = false
                if (added) {
                    revision++
                    onAddonsChanged()
                }
            },
        )
    }
}

@Composable
private fun SourceSectionHeading(
    title: String,
    info: String,
    actions: @Composable RowScope.() -> Unit = {},
) {
    var showInfo by remember(title) { mutableStateOf(false) }
    val layout = SourceSectionLayoutPolicy.current
    Row(
        Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 4.dp),
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
        if (layout.showSectionInfo) {
            IconButton(
                onClick = { showInfo = true },
                modifier = Modifier.size(48.dp).semantics { contentDescription = "$title information" },
            ) {
                Surface(
                    shape = CircleShape,
                    color = androidx.compose.ui.graphics.Color.Transparent,
                    border = BorderStroke(1.dp, OpenStreamColors.Muted),
                ) {
                    androidx.compose.foundation.layout.Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
                        Text("i", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = OpenStreamColors.TextSoft)
                    }
                }
            }
        }
        Spacer(Modifier.weight(1f))
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            actions()
        }
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
private fun DeleteModeButton(
    collection: SourceCollection,
    activeCollection: SourceCollection?,
    itemCount: Int,
    onClick: () -> Unit,
) {
    if (!SourceManagementPolicy.showDeleteAction(itemCount)) return
    val active = SourceManagementPolicy.showRemoveControl(collection, activeCollection)
    OpenStreamTextButton(onClick = onClick) {
        Text(
            SourceManagementPolicy.deleteActionLabel(collection, active),
            color = if (active) OpenStreamColors.Danger else OpenStreamColors.TextSoft,
        )
    }
}

@Composable
private fun FlatSourceRow(
    modifier: Modifier = Modifier,
    content: @Composable RowScope.() -> Unit,
) {
    val layout = SourceSectionLayoutPolicy.current
    Column {
        Row(
            modifier
                .fillMaxWidth()
                .heightIn(min = layout.minimumRowHeightDp.dp)
                .padding(horizontal = 4.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
        HorizontalDivider(color = OpenStreamColors.Border)
    }
}

@Composable
private fun AddNasDialog(store: ConnectionStore, onDone: (Boolean) -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf("") }
    var host by remember { mutableStateOf("") }
    var share by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var checking by remember { mutableStateOf(false) }
    var scanning by remember { mutableStateOf(false) }
    var listingShares by remember { mutableStateOf(false) }
    var discovered by remember { mutableStateOf<List<DiscoveredNas>?>(null) }
    var shares by remember { mutableStateOf<List<String>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = { if (!checking) onDone(false) },
        title = { Text("Add a NAS share") },
        text = {
          Column {
            Column(
                Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OpenStreamOutlinedButton(
                        onClick = {
                            scanning = true
                            error = null
                            scope.launch {
                                discovered = NasDiscovery.discover(context)
                                scanning = false
                                if (discovered.isNullOrEmpty()) {
                                    error = "No SMB servers found on this network. Make sure the tablet and NAS share the same Wi-Fi, then enter the host below."
                                }
                            }
                        },
                        enabled = !scanning,
                    ) {
                        if (scanning) {
                            OpenStreamLoadingLabel("Scanning network…")
                        } else {
                            Text("Scan for servers")
                        }
                    }
                }
                val found = discovered
                if (!found.isNullOrEmpty()) {
                    found.forEach { server ->
                        Surface(
                            onClick = {
                                host = server.host
                                if (name.isBlank()) name = server.name
                                shares = null
                            },
                            shape = RoundedCornerShape(8.dp),
                            color = if (host == server.host) OpenStreamColors.SurfaceRaised else OpenStreamColors.Surface,
                            border = BorderStroke(1.dp, if (host == server.host) OpenStreamColors.Accent.copy(alpha = 0.5f) else OpenStreamColors.Border),
                        ) {
                            Row(Modifier.fillMaxWidth().padding(10.dp), horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(AppIcons.Storage, contentDescription = null, tint = OpenStreamColors.Accent, modifier = Modifier.size(17.dp))
                                Text(server.name, fontWeight = FontWeight.Bold, color = OpenStreamColors.Text, fontSize = 14.sp)
                                Text(server.host, color = OpenStreamColors.Muted, fontSize = 13.sp)
                            }
                        }
                    }
                }
                OutlinedTextField(
                    value = host,
                    onValueChange = { host = it.trim(); shares = null },
                    singleLine = true,
                    label = { Text("Host or IP") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Next, autoCorrectEnabled = false),
                )
                OutlinedTextField(value = username, onValueChange = { username = it.trim(); shares = null }, singleLine = true, label = { Text("Username (blank = guest)") })
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it; shares = null },
                    singleLine = true,
                    label = { Text("Password") },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done, autoCorrectEnabled = false),
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OpenStreamOutlinedButton(
                        onClick = {
                            listingShares = true
                            error = null
                            scope.launch {
                                val result = runCatching { NasDiscovery.listShares(host, username, password) }
                                listingShares = false
                                result.fold(
                                    onSuccess = { shares = it; if (it.isEmpty()) error = "The server exposed no browseable shares." },
                                    onFailure = { error = Smb.friendlyError(it, share) },
                                )
                            }
                        },
                        enabled = !listingShares && host.isNotBlank(),
                    ) {
                        if (listingShares) {
                            OpenStreamLoadingLabel("Listing shares…")
                        } else {
                            Text("List shares")
                        }
                    }
                }
                val shareOptions = shares
                if (!shareOptions.isNullOrEmpty()) {
                    shareOptions.forEach { option ->
                        Surface(
                            onClick = { share = option },
                            shape = RoundedCornerShape(8.dp),
                            color = if (share == option) OpenStreamColors.SurfaceRaised else OpenStreamColors.Surface,
                            border = BorderStroke(1.dp, if (share == option) OpenStreamColors.Accent.copy(alpha = 0.5f) else OpenStreamColors.Border),
                        ) {
                            Row(Modifier.fillMaxWidth().padding(10.dp), horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(AppIcons.Folder, contentDescription = null, tint = OpenStreamColors.Muted, modifier = Modifier.size(16.dp))
                                Text(option, color = OpenStreamColors.Text, fontSize = 14.sp)
                            }
                        }
                    }
                }
                OutlinedTextField(value = share, onValueChange = { share = it.trim() }, singleLine = true, label = { Text("Share name") })
                OutlinedTextField(value = name, onValueChange = { name = it }, singleLine = true, label = { Text("Display name (optional)") })
            }
            if (error != null) {
                Text(error!!, color = OpenStreamColors.Danger, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp))
            }
          }
        },
        confirmButton = {
            OpenStreamButton(
                onClick = {
                    checking = true
                    error = null
                    scope.launch {
                        val candidate = NasConnection("pending", name.ifBlank { share }, host, share, username, password)
                        val failure = withContext(Dispatchers.IO) {
                            runCatching { Smb.validate(candidate) }.exceptionOrNull()
                        }
                        if (failure == null) {
                            checking = false
                            store.addNas(name, host, share, username, password)
                            Logs.event("nas connected: $host/$share")
                            onDone(true)
                        } else {
                            Logs.warn("nas connect failed for $host/$share: ${failure.message}")
                            // When the typed share doesn't exist, list the real
                            // shares so the user can just pick the right one.
                            if (Smb.isMissingShareError(failure)) {
                                val listed = runCatching { NasDiscovery.listShares(host, username, password) }.getOrNull()
                                if (!listed.isNullOrEmpty()) {
                                    shares = listed
                                    error = "No share named “$share”. Pick one of the ${listed.size} below."
                                } else {
                                    error = Smb.friendlyError(failure, share)
                                }
                            } else {
                                error = Smb.friendlyError(failure, share)
                            }
                            checking = false
                        }
                    }
                },
                enabled = !checking && host.isNotBlank() && share.isNotBlank(),
            ) {
                if (checking) {
                    OpenStreamLoadingLabel("Checking…")
                } else {
                    Text("Test & connect")
                }
            }
        },
        dismissButton = { OpenStreamTextButton(onClick = { if (!checking) onDone(false) }) { Text("Cancel") } },
    )
}

@Composable
private fun AddAddonDialog(store: ConnectionStore, onDone: (Boolean) -> Unit) {
    val scope = rememberCoroutineScope()
    var url by remember { mutableStateOf("") }
    var checking by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = { if (!checking) onDone(false) },
        title = { Text("Add a Stremio add-on") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = url,
                    onValueChange = { url = it.trim() },
                    singleLine = true,
                    label = { Text("Manifest URL") },
                    placeholder = { Text("https://addon.example/manifest.json") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done, autoCorrectEnabled = false),
                )
                if (error != null) Text(error!!, color = OpenStreamColors.Danger, fontSize = 13.sp)
            }
        },
        confirmButton = {
            OpenStreamButton(
                onClick = {
                    checking = true
                    error = null
                    scope.launch {
                        val result = withContext(Dispatchers.IO) {
                            runCatching { StremioClient.loadAddon(url) }
                        }
                        checking = false
                        result.fold(
                            onSuccess = { addon ->
                                store.addStremio(addon)
                                onDone(true)
                            },
                            onFailure = { failure ->
                                error = failure.message ?: "The add-on could not be validated."
                            },
                        )
                    }
                },
                enabled = !checking && url.isNotBlank(),
            ) {
                if (checking) {
                    OpenStreamLoadingLabel("Checking…")
                } else {
                    Text("Validate & add")
                }
            }
        },
        dismissButton = { OpenStreamTextButton(onClick = { if (!checking) onDone(false) }) { Text("Cancel") } },
    )
}

@Composable
private fun AddYoutubeChannelDialog(store: ConnectionStore, onDone: (Boolean) -> Unit) {
    val scope = rememberCoroutineScope()
    var input by remember { mutableStateOf("") }
    var checking by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = { if (!checking) onDone(false) },
        title = { Text("Add a YouTube channel") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "Enter an exact @handle, channel ID, or channel URL. No API key is required.",
                    color = OpenStreamColors.TextSoft,
                    fontSize = 14.sp,
                )
                OutlinedTextField(
                    value = input,
                    onValueChange = {
                        input = it
                        error = null
                    },
                    singleLine = true,
                    label = { Text("Channel") },
                    placeholder = { Text("@GoogleDevelopers") },
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Text,
                        imeAction = ImeAction.Done,
                        autoCorrectEnabled = false,
                    ),
                )
                if (error != null) Text(error!!, color = OpenStreamColors.Danger, fontSize = 13.sp)
            }
        },
        confirmButton = {
            OpenStreamButton(
                onClick = {
                    checking = true
                    error = null
                    scope.launch {
                        val result = withContext(Dispatchers.IO) {
                            runCatching { YoutubeChannelClient.resolve(input) }
                        }
                        checking = false
                        result.fold(
                            onSuccess = { channel ->
                                store.addYoutubeChannel(channel)
                                Logs.event("YouTube channel connected: ${channel.name}")
                                onDone(true)
                            },
                            onFailure = { failure ->
                                error = failure.message ?: "That YouTube channel could not be verified."
                            },
                        )
                    }
                },
                enabled = !checking && input.trim().length >= 2,
            ) {
                if (checking) OpenStreamLoadingLabel("Checking…") else Text("Verify & add")
            }
        },
        dismissButton = { OpenStreamTextButton(onClick = { if (!checking) onDone(false) }) { Text("Cancel") } },
    )
}

@Composable
private fun AddLibraryDialog(
    folderLabel: String,
    onDismiss: () -> Unit,
    onConfirm: (LibraryKind) -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add “$folderLabel” as a library") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "OpenStream scans this folder, reads each filename, and organizes it. " +
                        "Add a TMDB key in Settings for posters and descriptions.",
                    color = OpenStreamColors.TextSoft,
                    fontSize = 14.sp,
                )
                LibraryKindOption("Auto-organize", "Sort movies and TV apart automatically", LibraryKind.AUTO, onConfirm)
                LibraryKindOption("Movies", "Everything here is a movie", LibraryKind.MOVIES, onConfirm)
                LibraryKindOption("TV Shows", "Everything here is episodes", LibraryKind.TV, onConfirm)
            }
        },
        confirmButton = {},
        dismissButton = { OpenStreamTextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun LibraryKindOption(title: String, detail: String, kind: LibraryKind, onConfirm: (LibraryKind) -> Unit) {
    Surface(
        onClick = { onConfirm(kind) },
        shape = RoundedCornerShape(10.dp),
        color = OpenStreamColors.Surface,
        border = BorderStroke(1.dp, OpenStreamColors.Border),
    ) {
        Column(Modifier.fillMaxWidth().padding(14.dp)) {
            Text(title, fontWeight = FontWeight.Bold, color = OpenStreamColors.Text)
            Text(detail, fontSize = 13.sp, color = OpenStreamColors.Muted)
        }
    }
}

@Composable
private fun NasBrowser(
    connection: NasConnection,
    onBack: () -> Unit,
    onPlay: (NasEntry) -> Unit,
    onAddLibrary: (String, LibraryKind) -> Unit,
) {
    var path by remember { mutableStateOf("") }
    var entries by remember { mutableStateOf<List<NasEntry>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var showAddLibrary by remember { mutableStateOf(false) }

    LaunchedEffect(connection.id, path) {
        entries = null
        error = null
        val result = withContext(Dispatchers.IO) {
            runCatching { Smb.list(connection, path) }
        }
        result.fold(
            onSuccess = { entries = it },
            onFailure = { error = it.message ?: "The folder could not be read." },
        )
    }

    Column(Modifier.fillMaxSize().padding(horizontal = 24.dp)) {
        Row(
            Modifier.padding(vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = {
                if (path.isEmpty()) onBack() else path = path.substringBeforeLast('/', "")
            }) { Icon(AppIcons.Back, contentDescription = "Back", tint = OpenStreamColors.Text) }
            Column(Modifier.weight(1f)) {
                Text(connection.name, fontWeight = FontWeight.ExtraBold, fontSize = 19.sp, color = OpenStreamColors.Text)
                Text("/${path}", fontSize = 13.sp, color = OpenStreamColors.Muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            OpenStreamButton(onClick = { showAddLibrary = true }) {
                Icon(AppIcons.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                Text("  Add as library")
            }
        }

        if (showAddLibrary) {
            AddLibraryDialog(
                folderLabel = "/${path.ifBlank { connection.share }}",
                onDismiss = { showAddLibrary = false },
                onConfirm = { kind ->
                    showAddLibrary = false
                    onAddLibrary(path, kind)
                },
            )
        }

        // Snapshot into a stable local: the LazyColumn item lambda is deferred,
        // and the LaunchedEffect can flip `entries` to null on navigation — a
        // `!!` re-read there would NPE mid-draw.
        val currentEntries = entries
        val currentError = error
        when {
            currentError != null -> Text(currentError, color = OpenStreamColors.Danger)
            currentEntries == null -> Row(
                Modifier.fillMaxWidth().padding(vertical = 28.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                OpenStreamLoadingLabel(
                    label = "Reading folder…",
                    role = LoadingIndicatorRole.INLINE,
                    labelColor = OpenStreamColors.Muted,
                )
            }
            currentEntries.isEmpty() -> Text("No folders or video files here.", color = OpenStreamColors.Muted)
            else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 16.dp)) {
                items(currentEntries, key = { it.path }) { entry ->
                    Surface(
                        onClick = { if (entry.isDirectory) path = entry.path else onPlay(entry) },
                        shape = RoundedCornerShape(8.dp),
                        color = OpenStreamColors.Surface,
                    ) {
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                if (entry.isDirectory) AppIcons.Folder else AppIcons.Play,
                                contentDescription = null,
                                tint = if (entry.isDirectory) OpenStreamColors.Muted else OpenStreamColors.Accent,
                                modifier = Modifier.size(20.dp),
                            )
                            Text(
                                entry.name,
                                Modifier.weight(1f),
                                color = OpenStreamColors.Text,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            if (!entry.isDirectory) Text(formatSize(entry.sizeBytes), fontSize = 12.sp, color = OpenStreamColors.Muted)
                        }
                    }
                }
            }
        }
    }
}
