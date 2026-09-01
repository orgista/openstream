package com.orgista.openstream.ui.icons

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/**
 * Icon set built from the bundled core icons plus two small custom glyphs, so
 * the app avoids the multi-megabyte extended icon dependency.
 */
object AppIcons {
    val Home = Icons.Filled.Home
    val Library = Icons.AutoMirrored.Filled.List
    val Search = Icons.Filled.Search
    val Settings = Icons.Filled.Settings
    val Back = Icons.AutoMirrored.Filled.ArrowBack
    val Play = Icons.Filled.PlayArrow
    val Add = Icons.Filled.Add
    val Lock = Icons.Filled.Lock
    val More = Icons.Filled.MoreVert
    val Warning = Icons.Filled.Warning
    val Check = Icons.Filled.CheckCircle
    val Refresh = Icons.Filled.Refresh
    val Close = Icons.Filled.Close
    val ThumbUp = Icons.Filled.ThumbUp
    val Download: ImageVector by lazy {
        ImageVector.Builder(
            name = "Download",
            defaultWidth = 24.dp,
            defaultHeight = 24.dp,
            viewportWidth = 24f,
            viewportHeight = 24f,
        ).apply {
            path(fill = SolidColor(Color.White), pathFillType = PathFillType.NonZero) {
                moveTo(11f, 3f)
                horizontalLineTo(13f)
                verticalLineTo(13f)
                lineTo(16.5f, 9.5f)
                lineTo(18f, 11f)
                lineTo(12f, 17f)
                lineTo(6f, 11f)
                lineTo(7.5f, 9.5f)
                lineTo(11f, 13f)
                close()
                moveTo(5f, 19f)
                horizontalLineTo(19f)
                verticalLineTo(21f)
                horizontalLineTo(5f)
                close()
            }
        }.build()
    }
    val ThumbDown: ImageVector by lazy {
        ImageVector.Builder(
            name = "ThumbDown",
            defaultWidth = 24.dp,
            defaultHeight = 24.dp,
            viewportWidth = 24f,
            viewportHeight = 24f,
        ).apply {
            path(fill = SolidColor(Color.White), pathFillType = PathFillType.NonZero) {
                moveTo(15f, 3f)
                horizontalLineTo(6f)
                curveTo(5.18f, 3f, 4.46f, 3.5f, 4.16f, 4.22f)
                lineTo(1.14f, 11.27f)
                curveTo(1.05f, 11.5f, 1f, 11.74f, 1f, 12f)
                verticalLineTo(14f)
                curveTo(1f, 15.1f, 1.9f, 16f, 3f, 16f)
                horizontalLineTo(9.31f)
                lineTo(8.36f, 20.57f)
                curveTo(8.24f, 21.08f, 8.39f, 21.61f, 8.77f, 21.95f)
                lineTo(10.83f, 24f)
                lineTo(17.41f, 17.41f)
                curveTo(17.78f, 17.05f, 18f, 16.55f, 18f, 16.03f)
                verticalLineTo(5f)
                curveTo(18f, 3.9f, 17.1f, 3f, 16f, 3f)
                close()
                moveTo(20f, 3f)
                horizontalLineTo(24f)
                verticalLineTo(15f)
                horizontalLineTo(20f)
                close()
            }
        }.build()
    }

    /** Compact Wi-Fi glyph for the shared OpenPanel-style device header. */
    val Wifi: ImageVector by lazy {
        ImageVector.Builder(
            name = "Wifi",
            defaultWidth = 24.dp,
            defaultHeight = 24.dp,
            viewportWidth = 24f,
            viewportHeight = 24f,
        ).apply {
            path(fill = SolidColor(Color.White), pathFillType = PathFillType.NonZero) {
                moveTo(1f, 9f)
                lineTo(3f, 11f)
                curveTo(7.97f, 6.03f, 16.03f, 6.03f, 21f, 11f)
                lineTo(23f, 9f)
                curveTo(16.93f, 2.93f, 7.07f, 2.93f, 1f, 9f)
                close()
                moveTo(5f, 13f)
                lineTo(7f, 15f)
                curveTo(9.76f, 12.24f, 14.24f, 12.24f, 17f, 15f)
                lineTo(19f, 13f)
                curveTo(15.14f, 9.14f, 8.87f, 9.14f, 5f, 13f)
                close()
                moveTo(9f, 17f)
                lineTo(12f, 20f)
                lineTo(15f, 17f)
                curveTo(13.35f, 15.34f, 10.66f, 15.34f, 9f, 17f)
                close()
            }
        }.build()
    }

    /** Hard-drive glyph for NAS/storage surfaces. */
    val Storage: ImageVector by lazy {
        ImageVector.Builder(
            name = "Storage",
            defaultWidth = 24.dp,
            defaultHeight = 24.dp,
            viewportWidth = 24f,
            viewportHeight = 24f,
        ).apply {
            path(fill = SolidColor(Color.White), pathFillType = PathFillType.NonZero) {
                moveTo(4f, 6f)
                horizontalLineTo(20f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, 22f, 8f)
                verticalLineTo(16f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, 20f, 18f)
                horizontalLineTo(4f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, 2f, 16f)
                verticalLineTo(8f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, 4f, 6f)
                close()
                moveTo(17f, 13.5f)
                arcTo(1.5f, 1.5f, 0f, isMoreThanHalf = true, isPositiveArc = false, 17f, 10.5f)
                arcTo(1.5f, 1.5f, 0f, isMoreThanHalf = false, isPositiveArc = false, 17f, 13.5f)
                close()
            }
        }.build()
    }

    /** Broadcast antenna for the Live TV tab. */
    val Live: ImageVector by lazy {
        ImageVector.Builder(
            name = "Live",
            defaultWidth = 24.dp,
            defaultHeight = 24.dp,
            viewportWidth = 24f,
            viewportHeight = 24f,
        ).apply {
            path(fill = SolidColor(Color.White), pathFillType = PathFillType.NonZero) {
                moveTo(12f, 5f)
                curveTo(8.13f, 5f, 5f, 8.13f, 5f, 12f)
                horizontalLineTo(7f)
                curveTo(7f, 9.24f, 9.24f, 7f, 12f, 7f)
                reflectiveCurveTo(17f, 9.24f, 17f, 12f)
                horizontalLineTo(19f)
                curveTo(19f, 8.13f, 15.87f, 5f, 12f, 5f)
                close()
                moveTo(13f, 15.29f)
                curveTo(13.88f, 14.9f, 14.5f, 14.03f, 14.5f, 13f)
                curveTo(14.5f, 11.62f, 13.38f, 10.5f, 12f, 10.5f)
                reflectiveCurveTo(9.5f, 11.62f, 9.5f, 13f)
                curveTo(9.5f, 14.02f, 10.12f, 14.9f, 11f, 15.29f)
                verticalLineTo(18.59f)
                lineTo(7.59f, 21.41f)
                lineTo(9f, 22.82f)
                lineTo(12f, 19.82f)
                lineTo(15f, 22.82f)
                lineTo(16.41f, 21.41f)
                lineTo(13f, 18f)
                verticalLineTo(15.29f)
                close()
                moveTo(12f, 1f)
                curveTo(5.93f, 1f, 1f, 5.93f, 1f, 12f)
                horizontalLineTo(3f)
                curveTo(3f, 7.03f, 7.03f, 3f, 12f, 3f)
                reflectiveCurveTo(21f, 7.03f, 21f, 12f)
                horizontalLineTo(23f)
                curveTo(23f, 5.93f, 18.07f, 1f, 12f, 1f)
                close()
            }
        }.build()
    }

    /** Folder glyph for the NAS browser. */
    val Folder: ImageVector by lazy {
        ImageVector.Builder(
            name = "Folder",
            defaultWidth = 24.dp,
            defaultHeight = 24.dp,
            viewportWidth = 24f,
            viewportHeight = 24f,
        ).apply {
            path(fill = SolidColor(Color.White), pathFillType = PathFillType.NonZero) {
                moveTo(4f, 4f)
                horizontalLineTo(10f)
                lineTo(12f, 6f)
                horizontalLineTo(20f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, 22f, 8f)
                verticalLineTo(18f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, 20f, 20f)
                horizontalLineTo(4f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, 2f, 18f)
                verticalLineTo(6f)
                arcTo(2f, 2f, 0f, isMoreThanHalf = false, isPositiveArc = true, 4f, 4f)
                close()
            }
        }.build()
    }
}
