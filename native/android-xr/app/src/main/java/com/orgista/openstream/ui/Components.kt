package com.orgista.openstream.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.TextButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orgista.openstream.data.MediaItem

/** Material action with the app's compact control radius instead of a capsule. */
@Composable
fun OpenStreamButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    colors: ButtonColors = ButtonDefaults.buttonColors(),
    content: @Composable RowScope.() -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        shape = OpenStreamShapes.Control,
        colors = colors,
        content = content,
    )
}

/** Outlined Material action with the same non-capsule control radius. */
@Composable
fun OpenStreamOutlinedButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        shape = OpenStreamShapes.Control,
        content = content,
    )
}

/** Uncontained Material action whose keyboard/remote focus state is rectangular. */
@Composable
fun OpenStreamTextButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    colors: ButtonColors = ButtonDefaults.textButtonColors(),
    contentPadding: PaddingValues = ButtonDefaults.TextButtonContentPadding,
    content: @Composable RowScope.() -> Unit,
) {
    TextButton(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        shape = OpenStreamShapes.Control,
        colors = colors,
        contentPadding = contentPadding,
        content = content,
    )
}

/** Compact rectangular action used for the app's primary and secondary controls. */
@Composable
fun ActionButton(
    label: String,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    prominent: Boolean = true,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        enabled = enabled,
        shape = OpenStreamShapes.Control,
        color = when {
            !enabled -> OpenStreamColors.SurfaceRaised
            prominent -> Color(0xFFF5F8F9)
            else -> Color.Transparent
        },
        border = if (prominent) null else BorderStroke(1.dp, OpenStreamColors.Border),
    ) {
        Row(
            Modifier.padding(horizontal = 22.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val contentColor = when {
                !enabled -> OpenStreamColors.Muted
                prominent -> Color(0xFF071014)
                else -> OpenStreamColors.Text
            }
            if (icon != null) Icon(icon, contentDescription = null, tint = contentColor, modifier = Modifier.size(19.dp))
            Text(label, color = contentColor, fontWeight = FontWeight.Bold, fontSize = 15.sp)
        }
    }
}

/** Accessible icon-only action for compact preference controls. */
@Composable
fun IconActionButton(
    icon: ImageVector,
    contentDescription: String,
    selected: Boolean = false,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        shape = OpenStreamShapes.Control,
        color = if (selected) OpenStreamColors.Text else Color.Transparent,
        border = BorderStroke(1.dp, if (selected) OpenStreamColors.Text else OpenStreamColors.Border),
    ) {
        Icon(
            icon,
            contentDescription = contentDescription,
            tint = if (selected) OpenStreamColors.Canvas else OpenStreamColors.Text,
            modifier = Modifier.padding(13.dp).size(20.dp),
        )
    }
}

/** Small uppercase section header used across browse surfaces. */
@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(),
        modifier = modifier.semantics { heading() },
        fontSize = 12.sp,
        fontWeight = FontWeight.ExtraBold,
        letterSpacing = 1.4.sp,
        color = OpenStreamColors.Muted,
    )
}

@Composable
fun RatingChip(rating: String, modifier: Modifier = Modifier) {
    if (rating.isBlank()) return
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(4.dp),
        color = Color(0xB3060A0D),
        border = BorderStroke(1.dp, Color(0x38FFFFFF)),
    ) {
        Text(
            rating,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            fontSize = 10.sp,
            fontWeight = FontWeight.ExtraBold,
            letterSpacing = 0.6.sp,
            color = OpenStreamColors.TextSoft,
        )
    }
}

/**
 * Poster card: artwork with the title set inside over a scrim, so grids read
 * as a wall of art instead of labeled boxes.
 */
@Composable
fun MediaCard(
    item: MediaItem,
    width: Dp,
    useBackdrop: Boolean = false,
    onOpen: (MediaItem) -> Unit,
) {
    var focused by remember { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    val interactionSource = remember { MutableInteractionSource() }
    // Mouse hover gets the same lift as remote/keyboard focus.
    val hovered by interactionSource.collectIsHoveredAsState()
    val highlighted = focused || hovered
    val clipboard = LocalClipboardManager.current
    val cardScale by animateFloatAsState(
        targetValue = if (highlighted) 1.055f else 1f,
        label = "title-card-scale",
    )
    Box {
    Surface(
        onClick = { onOpen(item) },
        modifier = Modifier
            .width(width)
            .scale(cardScale)
            .onFocusChanged { focused = it.isFocused || it.hasFocus }
            .pointerHoverIcon(PointerIcon.Hand)
            .onSecondaryClick { menuOpen = true },
        shape = RoundedCornerShape(12.dp),
        color = OpenStreamColors.Surface,
        border = BorderStroke(
            if (highlighted) 2.dp else 1.dp,
            if (highlighted) OpenStreamColors.Text else Color(0x14E6F0F5),
        ),
        interactionSource = interactionSource,
    ) {
        Box(Modifier.fillMaxWidth().aspectRatio(if (useBackdrop) 16f / 9f else 2f / 3f)) {
            Poster(item, Modifier.fillMaxSize(), useBackdrop = useBackdrop)
            Box(
                Modifier.fillMaxSize().background(
                    Brush.verticalGradient(
                        (if (useBackdrop) 0.35f else 0.45f) to Color.Transparent,
                        1f to Color(0xF2060A0D),
                    ),
                ),
            )
            RatingChip(item.rating, Modifier.align(Alignment.TopEnd).padding(8.dp))
            Column(Modifier.align(Alignment.BottomStart).padding(horizontal = 13.dp, vertical = 12.dp)) {
                Text(
                    item.title,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = OpenStreamColors.Text,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    MediaCardPresentation.subtitle(item),
                    fontSize = 12.sp,
                    color = OpenStreamColors.Muted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (item.progressPercent != null) {
                Box(
                    Modifier
                        .align(Alignment.BottomStart)
                        .fillMaxWidth(item.progressPercent / 100f)
                        .height(3.dp)
                        .background(OpenStreamColors.Accent),
                )
            }
        }
    }
    // Right-click / secondary tap: desktop-style context menu.
    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
        DropdownMenuItem(text = { Text("Open") }, onClick = { menuOpen = false; onOpen(item) })
        DropdownMenuItem(
            text = { Text("Copy title") },
            onClick = {
                menuOpen = false
                clipboard.setText(AnnotatedString(if (item.year > 0) "${item.title} (${item.year})" else item.title))
            },
        )
    }
    }
}

/** Dot-separated metadata line: `2025 · PG-13 · 2h 07m · 4K Dolby Vision`. */
@Composable
fun MetaRow(item: MediaItem, includeFormat: Boolean = true) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("${item.year}", color = OpenStreamColors.TextSoft, fontSize = 15.sp)
        Dot()
        RatingChip(item.rating)
        if (item.rating.isNotBlank()) Dot()
        Text(formatRuntime(item.runtimeMinutes), color = OpenStreamColors.TextSoft, fontSize = 15.sp)
        if (includeFormat) {
            item.candidates.firstOrNull()?.let { candidate ->
                Dot()
                Text(candidate.formatLabel, color = OpenStreamColors.Muted, fontSize = 14.sp)
            }
        }
    }
}

@Composable
private fun Dot() {
    Text("·", color = OpenStreamColors.Muted, fontSize = 15.sp)
}
