package com.orgista.openstream.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orgista.openstream.ui.icons.AppIcons

@Composable
fun YoutubeVideoPlayerScreen(
    videoId: String,
    title: String,
    onBack: () -> Unit,
) {
    var playing by remember(videoId) { mutableStateOf(false) }
    var unavailable by remember(videoId) { mutableStateOf(false) }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        YoutubeEmbedPlayer(
            youtubeKey = videoId,
            modifier = Modifier.fillMaxSize(),
            muted = false,
            fullscreen = true,
            onPlaying = {
                playing = true
                unavailable = false
            },
            onUnavailable = { unavailable = true },
        )
        if (!playing && !unavailable) {
            OpenStreamLoadingLabel("Loading video…", modifier = Modifier.align(Alignment.Center))
        }
        if (unavailable) {
            Surface(
                modifier = Modifier.align(Alignment.Center),
                color = OpenStreamColors.SurfaceRaised,
                shape = CircleShape,
            ) {
                Text(
                    "This YouTube video is unavailable",
                    modifier = Modifier.padding(horizontal = 22.dp, vertical = 13.dp),
                    color = OpenStreamColors.Text,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
        Surface(
            modifier = Modifier.align(Alignment.TopStart).padding(18.dp),
            shape = CircleShape,
            color = Color.Black.copy(alpha = 0.62f),
        ) {
            HoverTooltip("Back") {
                IconButton(onClick = onBack) {
                    Icon(AppIcons.Back, contentDescription = "Back from $title", tint = Color.White)
                }
            }
        }
    }
}
