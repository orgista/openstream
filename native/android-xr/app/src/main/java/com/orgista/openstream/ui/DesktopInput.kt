package com.orgista.openstream.ui

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
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
import androidx.compose.ui.unit.dp

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

fun Context.isTelevision(): Boolean =
    getSystemService(UiModeManager::class.java)?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
