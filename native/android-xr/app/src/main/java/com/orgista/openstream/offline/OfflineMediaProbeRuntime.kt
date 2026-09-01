package com.orgista.openstream.offline

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.ColorInfo
import androidx.media3.common.Format
import androidx.media3.common.MediaItem as Media3Item
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import com.orgista.openstream.Logs
import com.orgista.openstream.media.DolbyVisionCodecString
import io.github.anilbeesetti.nextlib.media3ext.ffdecoder.NextRenderersFactory
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Lightweight runtime inspection for local/NAS media. It prepares the same
 * Media3 source graph used by playback and releases it as soon as track
 * formats are known; it does not decode or download the whole file.
 */
@OptIn(UnstableApi::class)
object OfflineMediaProbeRuntime {
    private const val PROBE_TIMEOUT_MS = 18_000L

    suspend fun probe(context: Context, uri: String): OfflineMediaProbe =
        withContext(Dispatchers.Main.immediate) {
            withTimeout(PROBE_TIMEOUT_MS) {
                suspendCancellableCoroutine { continuation ->
                    val appContext = context.applicationContext
                    val item = Media3Item.Builder().setUri(Uri.parse(uri)).build()
                    val dataSourceFactory = SchemeRoutingDataSource.Factory(appContext)
                    val player = ExoPlayer.Builder(
                        appContext,
                        NextRenderersFactory(appContext)
                            .setExtensionRendererMode(androidx.media3.exoplayer.DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
                            .setEnableDecoderFallback(true),
                    )
                        .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
                        .build()
                    fun release() = runCatching { player.release() }
                    fun completeFromTracks(tracks: Tracks) {
                        if (tracks.isEmpty()) return
                        if (!continuation.isActive) return
                        try {
                            val probe = extract(appContext, tracks)
                            Logs.event(
                                "media probe ok: ${probe.conciseLabel} " +
                                    "hardware=${probe.hardwareDecodeSupported ?: "unknown"}",
                            )
                            continuation.resume(probe)
                        } catch (error: Throwable) {
                            continuation.resumeWithException(error)
                        } finally {
                            release()
                        }
                    }
                    continuation.invokeOnCancellation { release() }
                    player.addListener(
                        object : Player.Listener {
                            override fun onTracksChanged(tracks: Tracks) {
                                completeFromTracks(tracks)
                            }

                            override fun onPlaybackStateChanged(playbackState: Int) {
                                if (playbackState == Player.STATE_READY) {
                                    completeFromTracks(player.currentTracks)
                                }
                            }

                            override fun onPlayerError(error: PlaybackException) {
                                release()
                                if (continuation.isActive) continuation.resumeWithException(error)
                            }
                        },
                    )
                    try {
                        player.setMediaItem(item)
                        player.playWhenReady = false
                        player.prepare()
                    } catch (error: Throwable) {
                        release()
                        if (continuation.isActive) continuation.resumeWithException(error)
                    }
                }
            }
        }

    private fun extract(context: Context, tracks: Tracks): OfflineMediaProbe {
        var selectedVideo: Format? = null
        var selectedAudio: Format? = null
        for (group in tracks.groups) {
            for (trackIndex in 0 until group.length) {
                val format = group.getTrackFormat(trackIndex)
                val sampleMimeType = format.sampleMimeType
                when {
                    group.type == C.TRACK_TYPE_VIDEO || MimeTypes.isVideo(sampleMimeType) -> {
                        if (selectedVideo == null || pixelCount(format) > pixelCount(selectedVideo)) {
                            selectedVideo = format
                        }
                    }
                    group.type == C.TRACK_TYPE_AUDIO || MimeTypes.isAudio(sampleMimeType) -> {
                        if (selectedAudio == null || audioScore(format) > audioScore(selectedAudio)) {
                            selectedAudio = format
                        }
                    }
                }
            }
        }
        val video = selectedVideo ?: throw IOException("No video track was found.")
        val audio = selectedAudio
        val codecString = video.codecs
        val videoMimeType = video.sampleMimeType
        val audioCodecString = audio?.codecs
        val dynamicRange = dynamicRange(video)
        val dolbyVisionProfile = DolbyVisionCodecString.parse(codecString).orElse(null)?.profile()
        val codec = videoCodec(videoMimeType, codecString)
        val videoProfile = videoProfile(videoMimeType, codecString, dolbyVisionProfile)
        val audioMimeType = audio?.sampleMimeType
        return OfflineMediaProbe(
            videoMimeType = videoMimeType,
            videoCodecString = codecString,
            videoCodec = codec,
            videoProfile = videoProfile,
            width = positive(video.width),
            height = positive(video.height),
            frameRate = positiveRate(video.frameRate),
            bitrate = positive(maxOf(video.bitrate, video.averageBitrate, video.peakBitrate)),
            bitDepth = video.colorInfo
                ?.let { maxOf(it.lumaBitdepth, it.chromaBitdepth) }
                ?.takeIf { it > 0 }
                ?: inferredBitDepth(codec, codecString, dolbyVisionProfile),
            dynamicRange = dynamicRange,
            dolbyVisionProfile = dolbyVisionProfile,
            audioMimeType = audioMimeType,
            audioCodecString = audioCodecString,
            audioChannels = audio?.channelCount?.let(::positive),
            audioBitrate = audio?.let { positive(maxOf(it.bitrate, it.averageBitrate, it.peakBitrate)) },
            dolbyAtmos = isAtmos(audioMimeType, audioCodecString),
            hardwareDecodeSupported = hardwareSupports(context, video),
        )
    }

    private fun hardwareSupports(context: Context, video: Format): Boolean? = runCatching {
        val mimeType = video.sampleMimeType ?: MimeTypes.getVideoMediaMimeType(video.codecs) ?: return@runCatching null
        MediaCodecUtil.getDecoderInfos(mimeType, false, false)
            .asSequence()
            .filter { it.hardwareAccelerated }
            .any { it.isFormatSupported(context, video) }
    }.onFailure { error ->
        Logs.warn("media probe hardware support check failed", error)
    }.getOrNull()

    private fun videoCodec(sampleMimeType: String?, codecs: String?): OfflineVideoCodec {
        val normalized = listOfNotNull(sampleMimeType, codecs).joinToString(" ").lowercase()
        return when {
            sampleMimeType == MimeTypes.VIDEO_AV1 || "av01" in normalized || "av1" in normalized ->
                OfflineVideoCodec.AV1
            sampleMimeType == MimeTypes.VIDEO_H265 ||
                sampleMimeType == MimeTypes.VIDEO_DOLBY_VISION ||
                "hvc1" in normalized || "hev1" in normalized || "hevc" in normalized || "h265" in normalized ->
                OfflineVideoCodec.HEVC
            sampleMimeType == MimeTypes.VIDEO_H264 || "avc1" in normalized || "avc3" in normalized ||
                "h264" in normalized || "x264" in normalized ->
                OfflineVideoCodec.AVC
            else -> OfflineVideoCodec.UNKNOWN
        }
    }

    private fun videoProfile(sampleMimeType: String?, codecs: String?, dolbyVisionProfile: Int?): String? {
        if (sampleMimeType == MimeTypes.VIDEO_DOLBY_VISION || dolbyVisionProfile != null) {
            return dolbyVisionProfile?.let { "Profile $it" } ?: "Dolby Vision"
        }
        val codec = codecs.orEmpty()
        parseHevcProfile(codec)?.let { return it }
        parseAvcProfile(codec)?.let { return it }
        parseAv1Profile(codec)?.let { return it }
        return null
    }

    private fun inferredBitDepth(
        codec: OfflineVideoCodec,
        codecs: String?,
        dolbyVisionProfile: Int?,
    ): Int? = when (codec) {
        OfflineVideoCodec.HEVC -> {
            val profile = parseHevcProfileIdc(codecs)
            when {
                dolbyVisionProfile != null -> 10
                profile == 2 -> 10
                profile == 1 -> 8
                else -> null
            }
        }
        OfflineVideoCodec.AVC -> {
            when (parseAvcProfileIdc(codecs)) {
                110 -> 10
                122 -> 10
                244 -> 10
                null -> null
                else -> 8
            }
        }
        OfflineVideoCodec.AV1 -> {
            parseAv1BitDepth(codecs)
        }
        OfflineVideoCodec.UNKNOWN -> null
    }

    private fun parseHevcProfile(codecs: String?): String? = when (parseHevcProfileIdc(codecs)) {
        1 -> "Main"
        2 -> "Main 10"
        3 -> "Main Still Picture"
        else -> null
    }

    private fun parseHevcProfileIdc(codecs: String?): Int? {
        val match = Regex("(?i)(?:hvc1|hev1)\\.([A-Z]?)(\\d{1,2})\\.").find(codecs.orEmpty()) ?: return null
        return match.groupValues.getOrNull(2)?.toIntOrNull()
    }

    private fun parseAvcProfile(codecs: String?): String? = when (parseAvcProfileIdc(codecs)) {
        66 -> "Baseline"
        77 -> "Main"
        88 -> "Extended"
        100 -> "High"
        110 -> "High 10"
        122 -> "High 4:2:2"
        244 -> "High 4:4:4"
        else -> null
    }

    private fun parseAvcProfileIdc(codecs: String?): Int? {
        val match = Regex("(?i)avc[13]\\.([0-9a-f]{6})").find(codecs.orEmpty()) ?: return null
        return match.groupValues[1].substring(0, 2).toIntOrNull(16)
    }

    private fun parseAv1Profile(codecs: String?): String? = when (parseAv1ProfileId(codecs)) {
        0 -> "Main"
        1 -> "High"
        2 -> "Professional"
        else -> null
    }

    private fun parseAv1ProfileId(codecs: String?): Int? =
        Regex("(?i)av01\\.(\\d)").find(codecs.orEmpty())?.groupValues?.getOrNull(1)?.toIntOrNull()

    private fun parseAv1BitDepth(codecs: String?): Int? {
        val parts = Regex("(?i)av01\\.[^.]+\\.[^.]+\\.(\\d{2})").find(codecs.orEmpty()) ?: return null
        return parts.groupValues[1].toIntOrNull()
    }

    private fun dynamicRange(video: Format): OfflineDynamicRange? {
        val codecs = video.codecs.orEmpty().lowercase()
        if (video.sampleMimeType == MimeTypes.VIDEO_DOLBY_VISION || DolbyVisionCodecString.parse(video.codecs).isPresent) {
            return OfflineDynamicRange.DOLBY_VISION
        }
        if ("hdr10+" in codecs || "hdr10plus" in codecs) return OfflineDynamicRange.HDR10_PLUS
        val colorInfo: ColorInfo = video.colorInfo ?: return null
        return when (colorInfo.colorTransfer) {
            C.COLOR_TRANSFER_ST2084 -> OfflineDynamicRange.HDR10
            C.COLOR_TRANSFER_HLG -> OfflineDynamicRange.HLG
            C.COLOR_TRANSFER_SDR,
            C.COLOR_TRANSFER_SRGB,
            C.COLOR_TRANSFER_GAMMA_2_2,
            C.COLOR_TRANSFER_LINEAR,
            -> OfflineDynamicRange.SDR
            else -> null
        }
    }

    private fun isAtmos(sampleMimeType: String?, codecs: String?): Boolean {
        val normalized = listOfNotNull(sampleMimeType, codecs).joinToString(" ").lowercase()
        return sampleMimeType == MimeTypes.AUDIO_E_AC3_JOC ||
            MimeTypes.CODEC_E_AC3_JOC.lowercase() in normalized ||
            "eac3-joc" in normalized ||
            "atmos" in normalized
    }

    private fun pixelCount(format: Format?): Long {
        if (format == null) return 0L
        return (positive(format.width) ?: 0).toLong() * (positive(format.height) ?: 0).toLong()
    }

    private fun audioScore(format: Format?): Int {
        if (format == null) return 0
        val atmos = if (isAtmos(format.sampleMimeType, format.codecs)) 100_000 else 0
        return atmos + (positive(format.channelCount) ?: 0) * 1000 + (positive(format.bitrate) ?: 0) / 1000
    }

    private fun positive(value: Int): Int? =
        value.takeIf { it != Format.NO_VALUE && it > 0 }

    private fun positiveRate(value: Float): Float? =
        value.takeIf { it > 0f && it != Format.NO_VALUE.toFloat() }
}
