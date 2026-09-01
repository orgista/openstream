package com.orgista.openstream.offline

import com.orgista.openstream.data.StremioStream
import kotlin.math.roundToLong

enum class OfflineVideoCodec { AVC, HEVC, AV1, UNKNOWN }

enum class OfflineDynamicRange { SDR, HDR10, HDR10_PLUS, HLG, DOLBY_VISION }

data class OfflineDecodeSize(val width: Int, val height: Int)

data class OfflineDeviceProfile(
    val maxWidth: Int,
    val maxHeight: Int,
    val codecs: Set<OfflineVideoCodec>,
    val dynamicRanges: Set<OfflineDynamicRange>,
    val dolbyAtmos: Boolean,
    val dolbyVisionProfiles: Set<Int> = emptySet(),
    val maxDecodeWidth: Int = maxWidth,
    val maxDecodeHeight: Int = maxHeight,
    val codecDecodeSizes: Map<OfflineVideoCodec, OfflineDecodeSize> = emptyMap(),
)

data class OfflineStreamDescriptor(
    val stream: StremioStream,
    val width: Int?,
    val height: Int?,
    val codec: OfflineVideoCodec,
    val dynamicRange: OfflineDynamicRange,
    val dolbyAtmos: Boolean,
    val sizeBytes: Long,
    val dolbyVisionProfile: Int? = null,
    /** Null means the route has not been probed; false means MediaCodec rejected this exact extracted format. */
    val hardwareDecodeSupported: Boolean? = null,
) {
    val qualityLabel: String
        get() = buildList {
            height?.let { add(if (it >= 2160) "4K" else "${it}p") }
            if (dynamicRange != OfflineDynamicRange.SDR) {
                add(
                    when (dynamicRange) {
                        OfflineDynamicRange.DOLBY_VISION -> "Dolby Vision"
                        OfflineDynamicRange.HDR10_PLUS -> "HDR10+"
                        OfflineDynamicRange.HDR10 -> "HDR10"
                        OfflineDynamicRange.HLG -> "HLG"
                        OfflineDynamicRange.SDR -> "SDR"
                    },
                )
            }
            if (codec != OfflineVideoCodec.UNKNOWN) add(codec.name)
            if (dolbyAtmos) add("Dolby Atmos")
        }.ifEmpty { listOf("Best available") }.joinToString(" · ")

    companion object {
        private val sizePattern = Regex("(?i)(\\d+(?:\\.\\d+)?)\\s*(TB|GB|MB)")

        fun parse(stream: StremioStream): OfflineStreamDescriptor {
            val text = stream.title
            val explicitResolution = Regex("(?i)\\b(\\d{3,5})\\s*x\\s*(\\d{3,5})\\b")
                .find(text)
                ?.let { match ->
                    val width = match.groupValues[1].toIntOrNull()
                    val height = match.groupValues[2].toIntOrNull()
                    if (width != null && height != null) width to height else null
                }
            val height = explicitResolution?.second ?: when {
                Regex("(?i)(?:2160p|\\b4k\\b)").containsMatchIn(text) -> 2160
                Regex("(?i)1440p").containsMatchIn(text) -> 1440
                Regex("(?i)1080p").containsMatchIn(text) -> 1080
                Regex("(?i)720p").containsMatchIn(text) -> 720
                Regex("(?i)576p").containsMatchIn(text) -> 576
                Regex("(?i)480p").containsMatchIn(text) -> 480
                else -> null
            }
            val width = explicitResolution?.first ?: when (height) {
                2160 -> 3840
                1440 -> 2560
                1080 -> 1920
                720 -> 1280
                576 -> 1024
                480 -> 854
                else -> null
            }
            val codec = when {
                Regex("(?i)(?:\\bav1\\b|av01)").containsMatchIn(text) -> OfflineVideoCodec.AV1
                Regex("(?i)(?:\\bhevc\\b|h[ .]?265|x265|hev1|hvc1)").containsMatchIn(text) -> OfflineVideoCodec.HEVC
                Regex("(?i)(?:\\bavc\\b|h[ .]?264|x264|avc1)").containsMatchIn(text) -> OfflineVideoCodec.AVC
                else -> OfflineVideoCodec.UNKNOWN
            }
            val range = when {
                Regex("(?i)(?:dolby[ ._-]*vision|\\bdv\\b|dvhe|dvh1)").containsMatchIn(text) ->
                    OfflineDynamicRange.DOLBY_VISION
                Regex("(?i)hdr[ ._-]*10\\+").containsMatchIn(text) -> OfflineDynamicRange.HDR10_PLUS
                Regex("(?i)hdr[ ._-]*10|\\bhdr\\b").containsMatchIn(text) -> OfflineDynamicRange.HDR10
                Regex("(?i)\\bhlg\\b").containsMatchIn(text) -> OfflineDynamicRange.HLG
                else -> OfflineDynamicRange.SDR
            }
            val atmos = Regex("(?i)(?:dolby[ ._-]*atmos|\\batmos\\b|eac3[ ._-]*joc)").containsMatchIn(text)
            val dolbyVisionProfile = Regex(
                "(?i)(?:dolby[ ._-]*vision|dovi|\\bdv\\b)[ ._-]*(?:p(?:rofile)?[ ._-]*)?(\\d{1,2})",
            ).find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()
            val size = sizePattern.find(text)?.let { match ->
                val value = match.groupValues[1].toDoubleOrNull() ?: return@let 0L
                val multiplier = when (match.groupValues[2].uppercase()) {
                    "TB" -> 1024.0 * 1024.0 * 1024.0 * 1024.0
                    "GB" -> 1024.0 * 1024.0 * 1024.0
                    else -> 1024.0 * 1024.0
                }
                (value * multiplier).roundToLong()
            } ?: 0L
            return OfflineStreamDescriptor(stream, width, height, codec, range, atmos, size, dolbyVisionProfile)
        }

        fun fromProbe(stream: StremioStream, probe: OfflineMediaProbe): OfflineStreamDescriptor {
            val fallback = parse(stream)
            return OfflineStreamDescriptor(
                stream = stream,
                width = probe.width ?: fallback.width,
                height = probe.height ?: fallback.height,
                codec = probe.videoCodec.takeUnless { it == OfflineVideoCodec.UNKNOWN } ?: fallback.codec,
                dynamicRange = probe.dynamicRange ?: fallback.dynamicRange,
                dolbyAtmos = probe.dolbyAtmos || fallback.dolbyAtmos,
                sizeBytes = probe.sizeBytes?.takeIf { it > 0 } ?: fallback.sizeBytes,
                dolbyVisionProfile = probe.dolbyVisionProfile ?: fallback.dolbyVisionProfile,
                hardwareDecodeSupported = probe.hardwareDecodeSupported,
            )
        }
    }
}

/**
 * Exact media facts learned by asking Media3's extractors to inspect a route.
 * This is intentionally smaller than a full ffprobe dump; it stores only the
 * fields needed to decide direct-play compatibility and present useful labels.
 */
data class OfflineMediaProbe(
    val videoMimeType: String?,
    val videoCodecString: String?,
    val videoCodec: OfflineVideoCodec,
    val videoProfile: String? = null,
    val width: Int?,
    val height: Int?,
    val frameRate: Float?,
    val bitrate: Int?,
    val bitDepth: Int?,
    val dynamicRange: OfflineDynamicRange?,
    val dolbyVisionProfile: Int? = null,
    val audioMimeType: String? = null,
    val audioCodecString: String? = null,
    val audioChannels: Int? = null,
    val audioBitrate: Int? = null,
    val dolbyAtmos: Boolean = false,
    val durationMs: Long? = null,
    val sizeBytes: Long? = null,
    val hardwareDecodeSupported: Boolean? = null,
    val probedAtEpochMillis: Long = System.currentTimeMillis(),
) {
    val conciseLabel: String
        get() = buildList {
            height?.let { add(if (it >= 2160) "4K" else "${it}p") }
            if (dynamicRange != null && dynamicRange != OfflineDynamicRange.SDR) {
                add(
                    when (dynamicRange) {
                        OfflineDynamicRange.DOLBY_VISION -> "Dolby Vision"
                        OfflineDynamicRange.HDR10_PLUS -> "HDR10+"
                        OfflineDynamicRange.HDR10 -> "HDR10"
                        OfflineDynamicRange.HLG -> "HLG"
                        OfflineDynamicRange.SDR -> "SDR"
                    },
                )
            }
            if (videoCodec != OfflineVideoCodec.UNKNOWN) {
                add(listOfNotNull(videoCodec.name, videoProfile).joinToString(" "))
            }
            bitDepth?.takeIf { it > 0 }?.let { add("${it}-bit") }
            if (dolbyAtmos) add("Dolby Atmos")
        }.ifEmpty { listOf("Format verified") }.joinToString(" · ")
}

object OfflineQualityPolicy {
    fun select(
        streams: List<StremioStream>,
        profile: OfflineDeviceProfile,
        availableBytes: Long,
    ): OfflineStreamDescriptor? = compatible(streams, profile, availableBytes)
        .maxByOrNull { qualityScore(it, profile) }

    fun selectDescriptors(
        descriptors: List<OfflineStreamDescriptor>,
        profile: OfflineDeviceProfile,
        availableBytes: Long,
    ): OfflineStreamDescriptor? = compatibleDescriptors(descriptors, profile, availableBytes)
        .maxByOrNull { qualityScore(it, profile) }

    fun compatible(
        streams: List<StremioStream>,
        profile: OfflineDeviceProfile,
        availableBytes: Long,
    ): List<OfflineStreamDescriptor> = compatibleDescriptors(
        streams.map(OfflineStreamDescriptor::parse),
        profile,
        availableBytes,
    )

    fun compatibleDescriptors(
        descriptors: List<OfflineStreamDescriptor>,
        profile: OfflineDeviceProfile,
        availableBytes: Long,
    ): List<OfflineStreamDescriptor> = descriptors
        .asSequence()
        .filter { it.hardwareDecodeSupported != false }
        .filter { it.sizeBytes <= 0L || it.sizeBytes <= availableBytes }
        .filter { candidate ->
            val decodeSize = profile.decodeSizeFor(candidate.codec)
            (candidate.width == null || candidate.width <= decodeSize.width) &&
                (candidate.height == null || candidate.height <= decodeSize.height)
        }
        .filter { it.codec == OfflineVideoCodec.UNKNOWN || it.codec in profile.codecs }
        .filter { it.dynamicRange in profile.dynamicRanges }
        .filter { candidate ->
            candidate.dynamicRange != OfflineDynamicRange.DOLBY_VISION ||
                candidate.dolbyVisionProfile == null ||
                profile.dolbyVisionProfiles.isEmpty() ||
                candidate.dolbyVisionProfile in profile.dolbyVisionProfiles
        }
        .toList()

    private fun OfflineDeviceProfile.decodeSizeFor(codec: OfflineVideoCodec): OfflineDecodeSize =
        if (codec == OfflineVideoCodec.UNKNOWN) {
            OfflineDecodeSize(maxDecodeWidth, maxDecodeHeight)
        } else {
            codecDecodeSizes[codec] ?: OfflineDecodeSize(maxDecodeWidth, maxDecodeHeight)
        }

    fun qualityScore(candidate: OfflineStreamDescriptor, profile: OfflineDeviceProfile): Long {
        val resolution = candidate.height?.let { height ->
            minOf(height, profile.maxHeight).toLong() * 10_000L
        } ?: 1L
        val range = when (candidate.dynamicRange) {
            OfflineDynamicRange.DOLBY_VISION -> 900L
            OfflineDynamicRange.HDR10_PLUS -> 800L
            OfflineDynamicRange.HDR10 -> 700L
            OfflineDynamicRange.HLG -> 600L
            OfflineDynamicRange.SDR -> 100L
        }
        val codec = when (candidate.codec) {
            OfflineVideoCodec.AV1 -> 90L
            OfflineVideoCodec.HEVC -> 80L
            OfflineVideoCodec.AVC -> 60L
            OfflineVideoCodec.UNKNOWN -> 0L
        }
        val audio = if (candidate.dolbyAtmos && profile.dolbyAtmos) 50L else 0L
        return resolution + range + codec + audio
    }
}
