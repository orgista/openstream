package com.orgista.openstream.ui

import android.animation.ValueAnimator
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin

private val LaunchBackground = Color(0xFF030303)
private val LaunchMark = Color(0xFFF5F8F9)
private val LaunchSweep = Color(0xFFEAFEFF)
private val EaseOutCubic = CubicBezierEasing(0.33f, 1f, 0.68f, 1f)

@Composable
fun OpenStreamLaunchGate(content: @Composable () -> Unit) {
    val animatorsEnabled = remember { ValueAnimator.areAnimatorsEnabled() }
    var showing by remember { mutableStateOf(true) }
    val timeline = remember { Animatable(0f) }

    LaunchedEffect(Unit) {
        if (animatorsEnabled) {
            timeline.animateTo(
                LaunchPresentationPolicy.totalMillis.toFloat(),
                tween(LaunchPresentationPolicy.totalMillis, easing = LinearEasing),
            )
        } else {
            delay(LaunchPresentationPolicy.durationMillis(animatorsEnabled = false))
        }
        showing = false
    }

    Box(Modifier.fillMaxSize()) {
        // Discover prepares behind the opaque launch stage, then becomes the
        // real destination during the final scene instead of showing a mock.
        content()
        if (showing) {
            OpenStreamLaunchStage(
                elapsedMillis = timeline.value.roundToInt(),
                animatorsEnabled = animatorsEnabled,
            )
        }
    }
}

@Composable
private fun OpenStreamLaunchStage(elapsedMillis: Int, animatorsEnabled: Boolean) {
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .semantics { contentDescription = "OpenStream" }
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
                    }
                }
            },
    ) {
        val density = LocalDensity.current
        val configuration = LocalConfiguration.current
        val layoutDirection = LocalLayoutDirection.current
        val widthPx = with(density) { maxWidth.toPx() }
        val heightPx = with(density) { maxHeight.toPx() }
        val minPx = minOf(widthPx, heightPx)
        val landscape = widthPx > heightPx
        val compact = TopNavLayoutPolicy.isCompact(
            configuration.screenWidthDp,
            configuration.screenHeightDp,
        )
        val insets = WindowInsets.safeDrawing.asPaddingValues()
        val topInsetPx = with(density) { insets.calculateTopPadding().toPx() }
        val startInsetPx = with(density) { insets.calculateStartPadding(layoutDirection).toPx() }
        val eased: (Float) -> Float = { FastOutSlowInEasing.transform(it.coerceIn(0f, 1f)) }
        val progress: (Int, Int) -> Float = { start, duration ->
            LaunchPresentationPolicy.progress(elapsedMillis, start, duration)
        }

        val discover = if (animatorsEnabled) {
            eased(progress(LaunchPresentationPolicy.discoverStartMillis + 50, 800))
        } else {
            0f
        }
        val reveal = if (animatorsEnabled) {
            eased(progress(LaunchPresentationPolicy.discoverStartMillis, 720))
        } else {
            0f
        }
        // The lockup crossfades out exactly as the glide lands on the resident
        // top-bar brand, so the handoff finishes where the real lockup lives.
        val brandExit = if (animatorsEnabled) {
            1f - eased(progress(3_650, 500))
        } else {
            1f
        }

        Canvas(Modifier.fillMaxSize()) {
            drawRect(LaunchBackground.copy(alpha = 1f - reveal))
            val glowAlpha = LaunchBarEffectPolicy.ambientAlpha(reveal)
            if (glowAlpha > 0.001f) {
                val glowRadius = size.minDimension * LaunchBarEffectPolicy.ambientRadiusFraction
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(Color(0xFF3E3A34).copy(alpha = glowAlpha), Color.Transparent),
                        center = Offset(size.width * 0.5f, size.height * 0.44f),
                        radius = glowRadius,
                    ),
                    radius = glowRadius,
                    center = Offset(size.width * 0.5f, size.height * 0.44f),
                )
            }
        }

        // Final geometry mirrors the real top bar exactly: the resident brand
        // renders inside the safe-drawing inset column, so the glide target
        // must include those insets or the mark lands above the real lockup.
        val initialMarkSize = minPx * if (landscape) 0.24f else 0.278f
        val targetMarkSize = with(density) { TopNavLayoutPolicy.brandMarkSizeDp(compact).dp.toPx() }
        val initialMarkX = (widthPx - initialMarkSize) * 0.5f
        val initialMarkY = heightPx * 0.432f - initialMarkSize * 0.5f
        val lockupMove = if (animatorsEnabled) eased(progress(2_200, 500)) else 1f
        val lockedMarkX = if (landscape) {
            mix(initialMarkX, initialMarkX - widthPx * 0.145f, lockupMove)
        } else {
            initialMarkX
        }
        val lockedMarkY = if (landscape) {
            initialMarkY
        } else {
            mix(initialMarkY, initialMarkY - heightPx * 0.0625f, lockupMove)
        }
        val targetMarkX = startInsetPx + with(density) { TopNavLayoutPolicy.brandStartPaddingDp(compact).dp.toPx() }
        val targetMarkY = topInsetPx + with(density) { TopNavLayoutPolicy.brandTopOffsetDp(compact).dp.toPx() }
        val markSize = mix(initialMarkSize, targetMarkSize, discover)
        val markX = mix(lockedMarkX, targetMarkX, discover)
        val markY = mix(lockedMarkY, targetMarkY, discover)

        LaunchSignalAndSources(
            elapsedMillis = elapsedMillis,
            markX = initialMarkX,
            markY = initialMarkY,
            markSize = initialMarkSize,
            widthPx = widthPx,
            heightPx = heightPx,
            visible = animatorsEnabled,
        )

        val bloom = if (animatorsEnabled) {
            eased(progress(1_850, 350)) * (1f - 0.78f * discover)
        } else {
            0f
        }
        OpenStreamAnimatedMark(
            elapsedMillis = elapsedMillis,
            bloom = bloom,
            modifier = Modifier
                .offset { IntOffset(markX.roundToInt(), markY.roundToInt()) }
                .size(with(density) { markSize.toDp() })
                .graphicsLayer { alpha = brandExit },
            immediatelyVisible = !animatorsEnabled,
        )

        var wordSize by remember { mutableStateOf(IntSize.Zero) }
        val initialWordSp = if (landscape) 31f else 35f
        val targetWordSp = TopNavLayoutPolicy.brandWordSp(compact).toFloat()
        val fontSizeSp = mix(initialWordSp, targetWordSp, discover)
        // The supplied lockup tracks at -0.015em; the resident bar uses -0.14sp.
        val letterSpacingSp = mix(-0.015f * initialWordSp, -0.14f, discover)
        val wordWidth = wordSize.width.toFloat()
        val wordHeight = wordSize.height.toFloat()
        val lockedWordX = if (landscape) {
            lockedMarkX + initialMarkSize + with(density) { 18.dp.toPx() }
        } else {
            (widthPx - wordWidth) * 0.5f
        }
        val lockedWordY = if (landscape) {
            lockedMarkY + initialMarkSize * 0.5f - wordHeight * 0.5f
        } else {
            lockedMarkY + initialMarkSize + with(density) { 14.dp.toPx() }
        }
        val targetWordX = targetMarkX + targetMarkSize + with(density) { TopNavLayoutPolicy.brandGapDp(compact).dp.toPx() }
        val targetWordY = targetMarkY + targetMarkSize * 0.5f - wordHeight * 0.5f
        val wordX = mix(lockedWordX, targetWordX, discover)
        val wordY = mix(lockedWordY, targetWordY, discover)

        // Each letter settles individually, rising to its baseline as it fades in.
        val word = "OpenStream"
        val annotatedWord = buildAnnotatedString {
            word.forEachIndexed { index, letter ->
                val letterIn = if (animatorsEnabled) {
                    EaseOutCubic.transform(progress(2_320 + index * 35, 340))
                } else {
                    1f
                }
                pushStyle(
                    SpanStyle(
                        color = Color(0xFFF9FBFC).copy(alpha = letterIn),
                        baselineShift = BaselineShift(-(1f - letterIn) * 0.2f),
                    ),
                )
                append(letter)
                pop()
            }
        }
        Text(
            annotatedWord,
            modifier = Modifier
                .offset { IntOffset(wordX.roundToInt(), wordY.roundToInt()) }
                .onSizeChanged { wordSize = it }
                .graphicsLayer { alpha = brandExit },
            fontSize = fontSizeSp.sp,
            fontWeight = FontWeight.ExtraBold,
            letterSpacing = letterSpacingSp.sp,
            maxLines = 1,
        )

        // Lockup light sweep: a soft band crosses the settled brand once.
        if (animatorsEnabled) {
            val sweep = eased(progress(2_700, 550))
            val sweepAlpha = sin(PI * sweep).toFloat() * 0.15f
            if (sweepAlpha > 0.004f) {
                Canvas(Modifier.fillMaxSize()) {
                    val bandWidth = size.width * if (landscape) 0.11f else 0.176f
                    val bandHeight = size.height * if (landscape) 0.44f else 0.32f
                    val bandLeft = mix(
                        size.width * if (landscape) 0.22f else 0.056f,
                        size.width * if (landscape) 0.78f else 0.83f,
                        sweep,
                    )
                    val bandTop = size.height * if (landscape) 0.28f else 0.27f
                    rotate(
                        degrees = if (landscape) 16f else 14f,
                        pivot = Offset(bandLeft + bandWidth * 0.5f, bandTop + bandHeight * 0.5f),
                    ) {
                        drawRect(
                            brush = Brush.horizontalGradient(
                                colors = listOf(
                                    Color.Transparent,
                                    LaunchSweep.copy(alpha = sweepAlpha),
                                    Color.Transparent,
                                ),
                                startX = bandLeft,
                                endX = bandLeft + bandWidth,
                            ),
                            topLeft = Offset(bandLeft, bandTop),
                            size = Size(bandWidth, bandHeight),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun LaunchSignalAndSources(
    elapsedMillis: Int,
    markX: Float,
    markY: Float,
    markSize: Float,
    widthPx: Float,
    heightPx: Float,
    visible: Boolean,
) {
    if (!visible) return
    val density = LocalDensity.current
    val rawSignal = LaunchPresentationPolicy.progress(elapsedMillis, 0, 720)
    val signalDraw = FastOutSlowInEasing.transform(rawSignal)
    // The line flickers on like a display waking before holding steady.
    val signalFlicker = when {
        rawSignal < 0.1f -> rawSignal * 4f
        rawSignal < 0.16f -> 0.14f
        rawSignal < 0.26f -> 0.9f
        rawSignal < 0.32f -> 0.5f
        else -> 1f
    }
    val signalFade = 1f - LaunchPresentationPolicy.progress(elapsedMillis, 900, 520)
    val streamStarts = listOf(720, 840, 960)
    val streamProgressAt = { index: Int ->
        FastOutSlowInEasing.transform(
            LaunchPresentationPolicy.progress(elapsedMillis, streamStarts[index], 620),
        )
    }

    Canvas(Modifier.fillMaxSize()) {
        val signalAlpha = signalFade * signalFlicker
        if (signalAlpha > 0f) {
            val halfWidth = widthPx * 0.36f * signalDraw
            val center = Offset(widthPx * 0.5f, heightPx * 0.432f)
            drawLine(
                color = LaunchMark.copy(alpha = signalAlpha * 0.2f),
                start = Offset(center.x - halfWidth, center.y),
                end = Offset(center.x + halfWidth, center.y),
                strokeWidth = 3.dp.toPx(),
                cap = StrokeCap.Round,
            )
            drawLine(
                color = Color.White.copy(alpha = signalAlpha * 0.95f),
                start = Offset(center.x - halfWidth, center.y),
                end = Offset(center.x + halfWidth, center.y),
                strokeWidth = 0.75.dp.toPx(),
                cap = StrokeCap.Round,
            )
        }

        OpenStreamBrandGeometry.bars.forEachIndexed { index, bar ->
            val streamProgress = streamProgressAt(index)
            val streamAlpha = sin(PI * streamProgress).toFloat().coerceAtLeast(0f)
            if (streamProgress > 0f && streamAlpha > 0.001f) {
                val target = Offset(
                    markX + markSize * OpenStreamBrandGeometry.startX / OpenStreamBrandGeometry.viewBox,
                    markY + markSize * bar.y / OpenStreamBrandGeometry.viewBox,
                )
                val start = Offset(-widthPx * 0.12f, target.y + (index - 1) * markSize * 0.43f)
                val head = Offset(
                    mix(start.x, target.x, streamProgress),
                    mix(start.y, target.y, streamProgress),
                )
                val tail = Offset(head.x - widthPx * 0.28f, head.y)
                drawLine(
                    brush = Brush.linearGradient(
                        colors = listOf(Color.Transparent, LaunchMark.copy(alpha = streamAlpha * 0.35f)),
                        start = tail,
                        end = head,
                    ),
                    start = tail,
                    end = head,
                    strokeWidth = 3.3.dp.toPx(),
                    cap = StrokeCap.Round,
                )
                drawLine(
                    brush = Brush.linearGradient(
                        colors = listOf(Color.Transparent, LaunchMark.copy(alpha = streamAlpha)),
                        start = tail,
                        end = head,
                    ),
                    start = tail,
                    end = head,
                    strokeWidth = 1.1.dp.toPx(),
                    cap = StrokeCap.Round,
                )
                drawCircle(
                    LaunchMark.copy(alpha = streamAlpha * 0.45f),
                    radius = 4.dp.toPx(),
                    center = head,
                )
                drawCircle(
                    Color.White.copy(alpha = streamAlpha),
                    radius = 1.9.dp.toPx(),
                    center = head,
                )
            }
        }
    }

    val labelSizes = remember { mutableStateListOf(IntSize.Zero, IntSize.Zero, IntSize.Zero) }
    listOf("LOCAL", "NAS", "ADD-ONS").forEachIndexed { index, label ->
        val streamProgress = streamProgressAt(index)
        val alpha = (sin(PI * streamProgress).toFloat() * 0.92f).coerceAtLeast(0f)
        if (alpha > 0.01f) {
            val labelWidth = labelSizes[index].width.toFloat()
            val labelHeight = labelSizes[index].height.toFloat()
            val targetX = markX + markSize * OpenStreamBrandGeometry.startX / OpenStreamBrandGeometry.viewBox
            val y = markY + markSize * OpenStreamBrandGeometry.bars[index].y / OpenStreamBrandGeometry.viewBox
            val restingX = targetX - with(density) { 12.dp.toPx() } - labelWidth
            val offscreenX = -labelWidth - with(density) { 8.dp.toPx() }
            Text(
                label,
                modifier = Modifier
                    .offset {
                        IntOffset(
                            mix(offscreenX, restingX, streamProgress).roundToInt(),
                            (y - labelHeight * 0.5f).roundToInt(),
                        )
                    }
                    .onSizeChanged { labelSizes[index] = it }
                    .graphicsLayer { this.alpha = alpha },
                color = LaunchMark,
                fontSize = 7.sp,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Medium,
                letterSpacing = 1.7.sp,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun OpenStreamAnimatedMark(
    elapsedMillis: Int,
    modifier: Modifier,
    immediatelyVisible: Boolean,
    bloom: Float = 0f,
) {
    Canvas(modifier) {
        val scale = size.minDimension / OpenStreamBrandGeometry.viewBox
        val stroke = OpenStreamBrandGeometry.strokeWidth * scale
        OpenStreamBrandGeometry.bars.forEachIndexed { index, bar ->
            val barProgress = if (immediatelyVisible) {
                1f
            } else {
                FastOutSlowInEasing.transform(
                    LaunchPresentationPolicy.progress(elapsedMillis, 1_150 + index * 140, 720),
                )
            }
            if (barProgress <= 0f) return@forEachIndexed
            val start = Offset(OpenStreamBrandGeometry.startX * scale, bar.y * scale)
            val end = Offset((OpenStreamBrandGeometry.startX + bar.length * barProgress) * scale, bar.y * scale)
            // A restrained edge halo keeps the mark luminous while preserving
            // the sharp silhouette of each bar through the lockup glide.
            drawLine(
                color = LaunchMark.copy(alpha = LaunchBarEffectPolicy.haloAlpha(bloom)),
                start = start,
                end = end,
                strokeWidth = stroke * LaunchBarEffectPolicy.haloStrokeMultiplier(bloom),
                cap = StrokeCap.Round,
            )
            drawLine(
                color = LaunchMark,
                start = start,
                end = end,
                strokeWidth = stroke,
                cap = StrokeCap.Round,
            )
            if (!immediatelyVisible && barProgress < 0.985f) {
                drawCircle(Color.White, radius = stroke * 0.37f, center = end)
            }
        }
    }
}

private fun mix(start: Float, end: Float, progress: Float): Float =
    start + (end - start) * progress.coerceIn(0f, 1f)
