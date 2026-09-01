package com.orgista.openstream.offline

import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodecList
import android.os.Build
import android.view.WindowManager
import com.orgista.openstream.media.HdrCapabilityProbe
import com.orgista.openstream.media.MediaCapabilityReport
import com.orgista.openstream.media.SupportState

object OfflineDeviceCapabilities {
    fun inspect(context: Context): OfflineDeviceProfile {
        val mode = runCatching {
            val display = if (Build.VERSION.SDK_INT >= 30) {
                context.display
            } else {
                @Suppress("DEPRECATION")
                (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay
            }
            display?.mode
        }.getOrNull()
        val physicalWidth = mode?.physicalWidth ?: context.resources.displayMetrics.widthPixels
        val physicalHeight = mode?.physicalHeight ?: context.resources.displayMetrics.heightPixels
        val maxWidth = maxOf(physicalWidth, physicalHeight)
        val maxHeight = minOf(physicalWidth, physicalHeight)

        val codecInfos = runCatching {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .asSequence()
                .filterNot { it.isEncoder }
                .filter { Build.VERSION.SDK_INT < 29 || it.isHardwareAccelerated }
                .toList()
        }.getOrDefault(emptyList())
        val codecs = runCatching {
            buildSet {
                add(OfflineVideoCodec.AVC)
                codecInfos
                    .asSequence()
                    .flatMap { it.supportedTypes.asSequence() }
                    .forEach { type ->
                        when (type.lowercase()) {
                            "video/hevc" -> add(OfflineVideoCodec.HEVC)
                            "video/av01" -> add(OfflineVideoCodec.AV1)
                        }
                }
            }
        }.getOrDefault(setOf(OfflineVideoCodec.AVC))

        fun maxDecodeFor(mimeType: String): OfflineDecodeSize? =
            listOf(3840 to 2160, 2560 to 1440, 1920 to 1080, 1280 to 720).firstOrNull { (width, height) ->
                codecInfos.any { codec ->
                    codec.supportedTypes.any { type ->
                        type.equals(mimeType, ignoreCase = true) && runCatching {
                            codec.getCapabilitiesForType(type).videoCapabilities?.isSizeSupported(width, height) == true
                        }.getOrDefault(false)
                    }
                }
            }?.let { (width, height) -> OfflineDecodeSize(width, height) }
        val codecDecodeSizes = buildMap {
            maxDecodeFor("video/avc")?.let { put(OfflineVideoCodec.AVC, it) }
            maxDecodeFor("video/hevc")?.let { put(OfflineVideoCodec.HEVC, it) }
            maxDecodeFor("video/av01")?.let { put(OfflineVideoCodec.AV1, it) }
        }
        val maxDecodeWidth = maxOf(maxWidth, codecDecodeSizes.values.maxOfOrNull { it.width } ?: maxWidth)
        val maxDecodeHeight = maxOf(maxHeight, codecDecodeSizes.values.maxOfOrNull { it.height } ?: maxHeight)

        val mediaReport = runCatching { HdrCapabilityProbe.inspect(context) }.getOrNull()
        val ranges = buildSet {
            add(OfflineDynamicRange.SDR)
            val report = mediaReport ?: return@buildSet
            fun addIfPlayable(
                reportRange: MediaCapabilityReport.DynamicRange,
                offlineRange: OfflineDynamicRange,
            ) {
                if (report.playableState(reportRange) == SupportState.SUPPORTED) add(offlineRange)
            }
            addIfPlayable(MediaCapabilityReport.DynamicRange.HDR10, OfflineDynamicRange.HDR10)
            addIfPlayable(MediaCapabilityReport.DynamicRange.HDR10_PLUS, OfflineDynamicRange.HDR10_PLUS)
            addIfPlayable(MediaCapabilityReport.DynamicRange.HLG, OfflineDynamicRange.HLG)
            addIfPlayable(MediaCapabilityReport.DynamicRange.DOLBY_VISION, OfflineDynamicRange.DOLBY_VISION)
        }

        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val atmos = if (Build.VERSION.SDK_INT >= 23) {
            runCatching {
                audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { output ->
                    output.encodings.any { encoding ->
                        encoding == AudioFormat.ENCODING_E_AC3_JOC || encoding == AudioFormat.ENCODING_DOLBY_TRUEHD
                    }
                }
            }.getOrDefault(false)
        } else {
            false
        }
        return OfflineDeviceProfile(
            maxWidth = maxWidth,
            maxHeight = maxHeight,
            codecs = codecs,
            dynamicRanges = ranges,
            dolbyAtmos = atmos,
            dolbyVisionProfiles = mediaReport?.dolbyVisionBitstreamProfiles()?.toSet().orEmpty(),
            maxDecodeWidth = maxDecodeWidth,
            maxDecodeHeight = maxDecodeHeight,
            codecDecodeSizes = codecDecodeSizes,
        )
    }
}
