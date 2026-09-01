package com.orgista.openstream.ui

object LaunchPresentationPolicy {
    const val signalMillis = 450
    const val confluenceMillis = 650
    const val lockupMillis = 550
    const val discoverMillis = 850
    const val discoverStartMillis = signalMillis + confluenceMillis + lockupMillis
    const val totalMillis = signalMillis + confluenceMillis + lockupMillis + discoverMillis

    fun durationMillis(animatorsEnabled: Boolean): Long =
        if (animatorsEnabled) totalMillis.toLong() else 220L

    fun progress(elapsedMillis: Int, startMillis: Int, durationMillis: Int): Float =
        ((elapsedMillis - startMillis).toFloat() / durationMillis.coerceAtLeast(1)).coerceIn(0f, 1f)
}

/** Keeps the animated mark luminous without softening its three bar silhouettes. */
object LaunchBarEffectPolicy {
    private const val haloBaseAlpha = 0.04f
    private const val haloBloomAlpha = 0.05f
    private const val haloBaseStrokeMultiplier = 1.12f
    private const val haloBloomStrokeMultiplier = 0.16f
    private const val ambientMaxAlpha = 0.07f
    const val ambientRadiusFraction = 0.24f

    fun haloAlpha(bloom: Float): Float =
        haloBaseAlpha + haloBloomAlpha * bloom.coerceIn(0f, 1f)

    fun haloStrokeMultiplier(bloom: Float): Float =
        haloBaseStrokeMultiplier + haloBloomStrokeMultiplier * bloom.coerceIn(0f, 1f)

    fun ambientAlpha(reveal: Float): Float =
        (1f - reveal.coerceIn(0f, 1f)) * ambientMaxAlpha
}

data class OpenStreamBrandBar(val y: Float, val length: Float)

/** Exact 96-grid geometry supplied with the new OpenStream brand package. */
object OpenStreamBrandGeometry {
    const val viewBox = 96f
    const val startX = 22f
    const val strokeWidth = 12.5f
    val bars = listOf(
        OpenStreamBrandBar(y = 31f, length = 40f),
        OpenStreamBrandBar(y = 48.5f, length = 56f),
        OpenStreamBrandBar(y = 66f, length = 40f),
    )
}

/**
 * Sizes the three-bar mark to the Material adaptive-icon square keyline
 * (44dp on the 108dp grid): balanced in the tile — neither edge-to-edge at
 * the 52dp wide-rectangle keyline nor lost in the mask — and always inside
 * the 66dp safe circle.
 */
object LauncherIconPresentationPolicy {
    const val adaptiveCanvasDp = 108f
    const val safeZoneDiameterDp = 66f
    const val squareKeylineDp = 44f
    const val foregroundInsetDp = 23f

    private val contentWidth = OpenStreamBrandGeometry.bars.maxOf { it.length } + OpenStreamBrandGeometry.strokeWidth
    private val contentHeight =
        OpenStreamBrandGeometry.bars.last().y - OpenStreamBrandGeometry.bars.first().y + OpenStreamBrandGeometry.strokeWidth

    fun renderedMarkWidthDp(): Float =
        contentWidth / OpenStreamBrandGeometry.viewBox * (adaptiveCanvasDp - foregroundInsetDp * 2f)

    fun renderedMarkHeightDp(): Float =
        contentHeight / OpenStreamBrandGeometry.viewBox * (adaptiveCanvasDp - foregroundInsetDp * 2f)
}
