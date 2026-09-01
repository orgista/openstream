package com.orgista.openstream.storage

import android.content.Context
import coil.annotation.ExperimentalCoilApi
import coil.imageLoader
import java.io.File
import java.util.Locale

data class AppStorageUsage(
    val cacheBytes: Long,
    val metadataBytes: Long,
) {
    companion object {
        val EMPTY = AppStorageUsage(cacheBytes = 0L, metadataBytes = 0L)
    }
}

/** Exact, testable cleanup boundaries for temporary files and catalog metadata. */
object StorageCleanupPolicy {
    private val metadataFileNames = setOf(
        "library-cache.json",
        "stremio-catalog-v1.json",
    )

    fun directorySize(target: File): Long = when {
        !target.exists() -> 0L
        target.isFile -> target.length()
        else -> target.listFiles().orEmpty().sumOf(::directorySize)
    }

    fun metadataSize(filesDir: File): Long = metadataFiles(filesDir).sumOf(::directorySize)

    fun formatBytes(bytes: Long): String {
        val safe = bytes.coerceAtLeast(0L).toDouble()
        val kib = 1024.0
        val mib = kib * 1024.0
        val gib = mib * 1024.0
        return when {
            safe >= gib -> String.format(Locale.US, "%.1f GB", safe / gib)
            safe >= mib -> String.format(Locale.US, "%.1f MB", safe / mib)
            safe >= kib -> String.format(Locale.US, "%.0f KB", safe / kib)
            else -> "${safe.toLong()} B"
        }
    }

    fun clearChildren(directory: File) {
        directory.listFiles().orEmpty().forEach(File::deleteRecursively)
    }

    fun clearMetadata(filesDir: File) {
        metadataFiles(filesDir).forEach(File::deleteRecursively)
    }

    private fun metadataFiles(filesDir: File): List<File> =
        metadataFileNames.map(filesDir::resolve)
}

/** Measures and clears app-owned caches without touching downloads, history, or credentials. */
object AppStorageManager {
    fun usage(context: Context): AppStorageUsage = AppStorageUsage(
        cacheBytes = StorageCleanupPolicy.directorySize(context.cacheDir),
        metadataBytes = StorageCleanupPolicy.metadataSize(context.filesDir),
    )

    @OptIn(ExperimentalCoilApi::class)
    fun trimMemoryForPlayback(context: Context) {
        // Keep the disk cache warm for fast back navigation, but release
        // decoded posters before MediaCodec allocates its output buffers.
        runCatching { context.imageLoader.memoryCache?.clear() }
    }

    @OptIn(ExperimentalCoilApi::class)
    fun clearCache(context: Context): AppStorageUsage {
        runCatching { context.imageLoader.memoryCache?.clear() }
        runCatching { context.imageLoader.diskCache?.clear() }
        StorageCleanupPolicy.clearChildren(context.cacheDir)
        return usage(context)
    }

    fun clearMetadata(context: Context): AppStorageUsage {
        StorageCleanupPolicy.clearMetadata(context.filesDir)
        return usage(context)
    }
}
