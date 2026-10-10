package com.orgista.openstream.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Switch
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orgista.openstream.iptv.IptvClient
import com.orgista.openstream.iptv.IptvEndpointPolicy
import com.orgista.openstream.iptv.IptvSourceType
import com.orgista.openstream.iptv.IptvStore
import com.orgista.openstream.ui.icons.AppIcons
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun IptvSettingsPanel(
    store: IptvStore,
    onChanged: () -> Unit,
    onOpenChannelManager: () -> Unit,
) {
    var saved by remember { mutableStateOf(store.custom()) }
    var type by remember { mutableStateOf(saved?.type ?: IptvSourceType.XTREAM) }
    var name by remember { mutableStateOf(saved?.name.orEmpty()) }
    var endpoint by remember { mutableStateOf(saved?.endpoint.orEmpty()) }
    var username by remember { mutableStateOf(saved?.username.orEmpty()) }
    var password by remember { mutableStateOf(saved?.password.orEmpty()) }
    var working by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var messageError by remember { mutableStateOf(false) }
    var deletingSource by remember { mutableStateOf(false) }
    var manualGuideUrl by remember { mutableStateOf(store.manualGuideUrl()) }
    var plutoEnabled by remember { mutableStateOf(store.plutoEnabled) }
    val scope = rememberCoroutineScope()
    val valid = when (type) {
        IptvSourceType.M3U -> IptvEndpointPolicy.isAllowed(endpoint)
        IptvSourceType.XTREAM -> IptvEndpointPolicy.isAllowed(endpoint) && username.isNotBlank() && password.isNotBlank()
        IptvSourceType.PLUTO -> false
    }

    Panel(
        "Live sources",
        "Add an Xtream account with its server address, username, and password, or paste an M3U playlist URL. Use HTTPS when your provider offers it; an HTTP provider does not encrypt account traffic.",
        actions = {
            if (saved != null) {
                OpenStreamTextButton(
                    enabled = !working,
                    onClick = { deletingSource = !deletingSource },
                ) {
                    Text(
                        SourceManagementPolicy.deleteActionLabel(SourceCollection.LIVE_TV, deletingSource),
                        color = if (deletingSource) OpenStreamColors.Danger else OpenStreamColors.TextSoft,
                    )
                }
                AnimatedVisibility(visible = deletingSource) {
                    HoverTooltip("Delete source") {
                        IconButton(
                            enabled = !working,
                            onClick = {
                                store.removeCustom()
                                saved = null
                                endpoint = ""
                                username = ""
                                password = ""
                                deletingSource = false
                                messageError = false
                                message = "Removed from this device."
                                onChanged()
                            },
                        ) {
                            Icon(
                                AppIcons.Close,
                                contentDescription = "Delete Live TV source",
                                tint = OpenStreamColors.Danger,
                                modifier = Modifier.size(20.dp),
                            )
                        }
                    }
                }
            }
        },
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text("Pluto TV", color = OpenStreamColors.Text, fontWeight = FontWeight.Bold)
                Text("Free live channels and current guide", color = OpenStreamColors.TextSoft, fontSize = 13.sp)
            }
            Switch(
                checked = plutoEnabled,
                modifier = Modifier.semantics {
                    contentDescription = "Include Pluto TV"
                    stateDescription = if (plutoEnabled) "Enabled" else "Disabled"
                },
                onCheckedChange = { enabled ->
                    plutoEnabled = enabled
                    store.plutoEnabled = enabled
                    messageError = false
                    message = if (enabled) "Pluto TV added." else "Pluto TV removed."
                    onChanged()
                },
            )
        }
        OpenStreamOutlinedButton(onClick = onOpenChannelManager) {
            Text("Channel manager")
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (type == IptvSourceType.XTREAM) {
                OpenStreamButton(onClick = {}) { Text("Xtream account") }
                OpenStreamOutlinedButton(onClick = { type = IptvSourceType.M3U; message = null }) { Text("M3U playlist") }
            } else {
                OpenStreamOutlinedButton(onClick = { type = IptvSourceType.XTREAM; message = null }) { Text("Xtream account") }
                OpenStreamButton(onClick = {}) { Text("M3U playlist") }
            }
        }
        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            label = { Text("Name") },
            placeholder = { Text("My TV") },
            singleLine = true,
            modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
        )
        OutlinedTextField(
            value = endpoint,
            onValueChange = { endpoint = it.trim() },
            label = { Text(if (type == IptvSourceType.XTREAM) "Server URL" else "M3U/M3U8 playlist URL") },
            placeholder = { Text(if (type == IptvSourceType.XTREAM) "https://tv.example.com" else "https://example.com/playlist.m3u8") },
            singleLine = true,
            modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
        )
        if (type == IptvSourceType.XTREAM) {
            OutlinedTextField(
                value = username,
                onValueChange = { username = it },
                label = { Text("Username") },
                singleLine = true,
                modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
            )
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("Password") },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
            )
        }
        Text("Program guide", color = OpenStreamColors.Text, fontWeight = FontWeight.Bold)
        OutlinedTextField(
            value = manualGuideUrl,
            onValueChange = { manualGuideUrl = it.trim(); message = null },
            label = { Text("XMLTV guide URL (optional)") },
            placeholder = { Text("https://example.com/guide.xml.gz") },
            singleLine = true,
            isError = manualGuideUrl.isNotBlank() && !IptvEndpointPolicy.isAllowed(manualGuideUrl),
            modifier = Modifier.widthIn(max = 760.dp).fillMaxWidth(),
        )
        OpenStreamOutlinedButton(
            enabled = (manualGuideUrl.isBlank() || IptvEndpointPolicy.isAllowed(manualGuideUrl)) && !working,
            onClick = {
                runCatching { store.saveManualGuideUrl(manualGuideUrl) }
                    .onSuccess {
                        messageError = false
                        message = if (manualGuideUrl.isBlank()) "Program guide removed." else "Program guide saved."
                        onChanged()
                    }
                    .onFailure { failure ->
                        messageError = true
                        message = failure.message ?: "Could not save this program guide."
                    }
            },
        ) { Text("Save guide") }
        message?.let {
            Text(
                it,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = if (messageError) OpenStreamColors.Danger else OpenStreamColors.Green,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OpenStreamButton(
                enabled = valid && !working,
                onClick = {
                    val source = IptvStore.custom(name, type, endpoint, username, password)
                    runCatching { store.save(source) }.onSuccess {
                        saved = source
                        deletingSource = false
                        messageError = false
                        message = "Saved privately on this device."
                        onChanged()
                    }.onFailure {
                        messageError = true
                        message = it.message ?: "Could not save this IPTV source."
                    }
                },
            ) { Text("Save") }
            OpenStreamOutlinedButton(
                enabled = valid && !working,
                onClick = {
                    working = true
                    message = null
                    scope.launch {
                        val source = IptvStore.custom(name, type, endpoint, username, password)
                        val result = withContext(Dispatchers.IO) { runCatching { IptvClient.load(source) } }
                        working = false
                        result.onSuccess { channels ->
                            store.save(source)
                            saved = source
                            deletingSource = false
                            messageError = false
                            message = "Connected · ${channels.size} live channels found."
                            onChanged()
                        }.onFailure {
                            messageError = true
                            message = it.message ?: "Could not reach this IPTV source."
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
        }
    }
}
