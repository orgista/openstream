package com.orgista.openstream.ui

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.draganddrop.dragAndDropTarget
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.draganddrop.DragAndDropEvent
import androidx.compose.ui.draganddrop.DragAndDropTarget
import androidx.compose.ui.draganddrop.mimeTypes
import androidx.compose.ui.draganddrop.toAndroidDragEvent
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import android.view.DragEvent
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.Text
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.rememberTooltipState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.isSecondaryPressed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.input.key.KeyEvent as ComposeKeyEvent
import androidx.compose.ui.unit.dp
import android.view.InputDevice
import android.view.View
import android.view.ViewGroup
import kotlinx.coroutines.delay

/** Right-click (or two-finger trackpad click): calls [onClick] with the press position. */
fun Modifier.onSecondaryClick(onClick: (Offset) -> Unit): Modifier = pointerInput(onClick) {
    awaitPointerEventScope {
        while (true) {
            val event = awaitPointerEvent(PointerEventPass.Initial)
            if (event.type == PointerEventType.Press && event.buttons.isSecondaryPressed) {
                event.changes.forEach { it.consume() }
                onClick(event.changes.first().position)
            }
        }
    }
}

/** Visible-position snapshot used to place a scrollbar thumb. */
private data class ScrollMetrics(val scrolledPx: Float, val contentPx: Float, val viewportPx: Float)

/**
 * Thin fading scrollbar while a list scrolls (mouse wheel, trackpad, touch),
 * the desktop guideline's "show scrollbars". Leanback TV keeps its clean rails.
 */
private fun Modifier.scrollbar(scrolling: () -> Boolean, metrics: () -> ScrollMetrics?): Modifier = composed {
    val context = LocalContext.current
    val television = remember(context) { context.isTelevision() }
    if (television) return@composed this
    val active = scrolling()
    val alpha by animateFloatAsState(
        targetValue = if (active) 1f else 0f,
        animationSpec = tween(durationMillis = if (active) 120 else 700, delayMillis = if (active) 0 else 500),
        label = "scrollbar-alpha",
    )
    drawWithContent {
        drawContent()
        if (alpha <= 0f) return@drawWithContent
        val m = metrics() ?: return@drawWithContent
        if (m.contentPx <= m.viewportPx || m.viewportPx <= 0f) return@drawWithContent
        val thumb = (m.viewportPx / m.contentPx * size.height).coerceIn(28.dp.toPx(), size.height)
        val progress = (m.scrolledPx / (m.contentPx - m.viewportPx)).coerceIn(0f, 1f)
        val width = 5.dp.toPx()
        drawRoundRect(
            color = Color.White.copy(alpha = 0.42f * alpha),
            topLeft = Offset(size.width - width - 3.dp.toPx(), progress * (size.height - thumb)),
            size = Size(width, thumb),
            cornerRadius = CornerRadius(width / 2f),
        )
    }
}

fun Modifier.verticalScrollbar(state: LazyListState): Modifier = scrollbar({ state.isScrollInProgress }) {
    val info = state.layoutInfo
    val visible = info.visibleItemsInfo
    if (visible.isEmpty()) return@scrollbar null
    val average = visible.sumOf { it.size }.toFloat() / visible.size
    ScrollMetrics(
        scrolledPx = state.firstVisibleItemIndex * average + state.firstVisibleItemScrollOffset,
        contentPx = average * info.totalItemsCount,
        viewportPx = (info.viewportEndOffset - info.viewportStartOffset).toFloat(),
    )
}

fun Modifier.verticalScrollbar(state: LazyGridState): Modifier = scrollbar({ state.isScrollInProgress }) {
    val info = state.layoutInfo
    val visible = info.visibleItemsInfo
    if (visible.isEmpty()) return@scrollbar null
    val columns = visible.count { it.row == visible.first().row }.coerceAtLeast(1)
    val rowHeight = visible.maxOf { it.size.height }.toFloat()
    ScrollMetrics(
        scrolledPx = state.firstVisibleItemIndex / columns * rowHeight + state.firstVisibleItemScrollOffset,
        contentPx = rowHeight * ((info.totalItemsCount + columns - 1) / columns),
        viewportPx = (info.viewportEndOffset - info.viewportStartOffset).toFloat(),
    )
}

fun Modifier.verticalScrollbar(state: ScrollState): Modifier = scrollbar({ state.isScrollInProgress }) {
    val viewport = state.viewportSize.toFloat()
    ScrollMetrics(state.value.toFloat(), viewport + state.maxValue, viewport)
}

/**
 * High-contrast keyboard focus ring for buttons; Material's 10% focus layer is
 * nearly invisible on the dark canvas. TV keeps its existing focus styling.
 */
fun Modifier.keyboardFocusRing(shape: Shape): Modifier = composed {
    val context = LocalContext.current
    val television = remember(context) { context.isTelevision() }
    if (television) return@composed this
    var focused by remember { mutableStateOf(false) }
    onFocusChanged { focused = it.isFocused }
        .then(if (focused) Modifier.border(2.dp, OpenStreamColors.Text, shape) else Modifier)
}

fun Context.isTelevision(): Boolean =
    getSystemService(UiModeManager::class.java)?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION

/** A key from a full alphabetic keyboard (desktop, laptop), not a TV remote or D-pad. */
fun ComposeKeyEvent.fromFullKeyboard(): Boolean =
    nativeKeyEvent.device?.keyboardType == InputDevice.KEYBOARD_TYPE_ALPHABETIC

/**
 * Hover tooltip for icon-only buttons (desktop T-Hover_Parity): the label
 * appears after the pointer rests on [content]. Touch long-press keeps
 * Material's behavior; TV has no pointer, so it gets the bare content.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HoverTooltip(label: String, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val television = remember(context) { context.isTelevision() }
    if (television || label.isBlank()) {
        content()
        return
    }
    // Persistent: stays up while the pointer rests on the button, not 1.5 s.
    val state = rememberTooltipState(isPersistent = true)
    var hovered by remember { mutableStateOf(false) }
    LaunchedEffect(hovered) {
        if (hovered) {
            delay(500)
            state.show()
        } else {
            state.dismiss()
        }
    }
    TooltipBox(
        positionProvider = TooltipDefaults.rememberPlainTooltipPositionProvider(),
        tooltip = { PlainTooltip { Text(label) } },
        state = state,
        modifier = Modifier.pointerInput(Unit) {
            awaitPointerEventScope {
                while (true) {
                    val event = awaitPointerEvent(PointerEventPass.Initial)
                    when (event.type) {
                        PointerEventType.Enter -> hovered = true
                        PointerEventType.Exit, PointerEventType.Press -> hovered = false
                    }
                }
            }
        },
    ) {
        content()
    }
}

/**
 * Android-view counterpart of [HoverTooltip] for Media3's controller: every
 * labelled control shows its current description on hover. Call again when
 * descriptions change (play/pause swaps its label).
 */
fun View.syncHoverTooltips() {
    if (android.os.Build.VERSION.SDK_INT < 26 || context.isTelevision()) return
    if (isClickable && !contentDescription.isNullOrBlank()) tooltipText = contentDescription
    if (this is ViewGroup) for (index in 0 until childCount) getChildAt(index).syncHoverTooltips()
}

/**
 * Drop a video or audio file from the Files app (or any app) anywhere on the
 * window to play it (T-Drag_Drop_Support). TV has no drag source, so it gets
 * the bare content.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LocalMediaDropZone(enabled: Boolean, onDrop: (DragEvent) -> Boolean, content: @Composable () -> Unit) {
    if (!enabled) {
        content()
        return
    }
    var over by remember { mutableStateOf(false) }
    val currentOnDrop by rememberUpdatedState(onDrop)
    val target = remember {
        object : DragAndDropTarget {
            override fun onEntered(event: DragAndDropEvent) { over = true }
            override fun onExited(event: DragAndDropEvent) { over = false }
            override fun onEnded(event: DragAndDropEvent) { over = false }
            override fun onDrop(event: DragAndDropEvent): Boolean {
                over = false
                return currentOnDrop(event.toAndroidDragEvent())
            }
        }
    }
    Box(
        Modifier
            .fillMaxSize()
            .dragAndDropTarget(
                shouldStartDragAndDrop = { event ->
                    event.mimeTypes().any { it.startsWith("video/") || it.startsWith("audio/") }
                },
                target = target,
            ),
    ) {
        content()
        if (over) {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.62f))
                    .border(3.dp, OpenStreamColors.Accent),
                contentAlignment = Alignment.Center,
            ) {
                Text("Drop to play", color = OpenStreamColors.Text, fontSize = 22.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}
