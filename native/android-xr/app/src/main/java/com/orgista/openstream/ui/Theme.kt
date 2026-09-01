package com.orgista.openstream.ui

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Matches OpenPanel's design system so both launcher and media UI feel coherent:
 * a neutral near-black canvas (#040404), neutral near-white text (#fafafa),
 * and the OpenPanel brand blue as the single accent. System fonts, like
 * OpenPanel. Status colours (green/amber/red) are OpenPanel's exact values.
 */
object OpenStreamColors {
    val CanvasDeep = Color(0xFF000000)
    val Canvas = Color(0xFF040404)
    val Surface = Color(0xFF171717)
    val SurfaceRaised = Color(0xFF202020)
    val Text = Color(0xFFFAFAFA)
    val TextSoft = Color(0xFFD4D4D4)
    val Muted = Color(0xFFA1A1A1)
    val Border = Color(0xFF262626)
    val BorderStrong = Color(0xFF3A3A3A)

    /** The one accent: OpenPanel's brand blue (the sky→royal X gradient). */
    val Accent = Color(0xFF3B82F6)
    val AccentSoft = Color(0x243B82F6)

    val Danger = Color(0xFFFB2C36)

    // OpenPanel status colours; also serve the back-compat aliases so existing
    // call sites keep compiling.
    val Green = Color(0xFF51C148)
    val Amber = Color(0xFFFFB900)
    val Offline = Color(0xFFB8A46A)
    val Cyan = Accent
    val Coral = Muted
}

object OpenStreamShapes {
    val Tag = RoundedCornerShape(4.dp)
    val Control = RoundedCornerShape(8.dp)
    val Selection = RoundedCornerShape(10.dp)
    val Card = RoundedCornerShape(12.dp)
}

private val shapes = Shapes(
    extraSmall = OpenStreamShapes.Tag,
    small = OpenStreamShapes.Control,
    medium = OpenStreamShapes.Selection,
    large = OpenStreamShapes.Card,
    extraLarge = OpenStreamShapes.Card,
)

private val scheme = darkColorScheme(
    primary = OpenStreamColors.Accent,
    onPrimary = Color(0xFFFFFFFF),
    secondary = OpenStreamColors.Accent,
    onSecondary = Color(0xFFFFFFFF),
    background = OpenStreamColors.Canvas,
    onBackground = OpenStreamColors.Text,
    surface = OpenStreamColors.Surface,
    onSurface = OpenStreamColors.Text,
    surfaceVariant = OpenStreamColors.SurfaceRaised,
    onSurfaceVariant = OpenStreamColors.TextSoft,
    error = OpenStreamColors.Danger,
    outline = OpenStreamColors.BorderStrong,
)

@Composable
fun OpenStreamTheme(content: @Composable () -> Unit) {
    // Always dark: this is a media surface, not a system-themed app.
    MaterialTheme(colorScheme = scheme, shapes = shapes, content = content)
}
