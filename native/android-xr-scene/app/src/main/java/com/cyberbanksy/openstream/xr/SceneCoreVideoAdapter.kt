@file:Suppress("RestrictedApi", "DEPRECATION")

package com.cyberbanksy.openstream.xr

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.xr.runtime.Session
import androidx.xr.runtime.math.FloatSize2d
import androidx.xr.runtime.math.Pose
import androidx.xr.runtime.math.Vector3
import androidx.xr.scenecore.SurfaceEntity
import androidx.xr.scenecore.scene

class SceneCoreVideoAdapter(
    private val context: Context,
    private val session: Session,
    private val onStatus: (String) -> Unit,
) : AutoCloseable {
    private var player: ExoPlayer? = null
    private var surfaceEntity: SurfaceEntity? = null

    fun play(media: ImmersiveMedia): Boolean {
        releasePlayback()
        val sourceUri = media.uri ?: run {
            onStatus("Choose a valid video source.")
            return false
        }
        val plan = SceneCoreVideoPolicy.plan(media)
        if (!plan.directlyRenderable) {
            onStatus(plan.unsupportedReason.orEmpty())
            return false
        }

        val shape = when (plan.shape) {
            SceneSurfaceShape.QUAD ->
                SurfaceEntity.Shape.Quad(FloatSize2d(plan.widthMeters, plan.heightMeters))
            SceneSurfaceShape.HEMISPHERE -> SurfaceEntity.Shape.Hemisphere(plan.radiusMeters)
            SceneSurfaceShape.SPHERE -> SurfaceEntity.Shape.Sphere(plan.radiusMeters)
            SceneSurfaceShape.CUSTOM_MESH -> error("Custom mesh was rejected by policy")
        }
        val stereoMode = when (plan.stereoLayout) {
            StereoLayout.MONO -> SurfaceEntity.StereoMode.MONO
            StereoLayout.SIDE_BY_SIDE -> SurfaceEntity.StereoMode.SIDE_BY_SIDE
            StereoLayout.TOP_BOTTOM -> SurfaceEntity.StereoMode.TOP_BOTTOM
            StereoLayout.MULTIVIEW_LEFT_PRIMARY -> SurfaceEntity.StereoMode.MULTIVIEW_LEFT_PRIMARY
        }
        val pose = if (plan.shape == SceneSurfaceShape.QUAD) {
            Pose(Vector3(0.0f, 0.0f, -2.2f))
        } else {
            Pose()
        }
        val entity = SurfaceEntity.create(
            session = session,
            stereoMode = stereoMode,
            pose = pose,
            shape = shape,
            parent = session.scene.activitySpace,
        )
        applyDynamicRange(entity, plan.dynamicRange)

        val exoPlayer = try {
            ExoPlayer.Builder(context).build().also { created ->
                created.addListener(
                    object : Player.Listener {
                        override fun onPlaybackStateChanged(playbackState: Int) {
                            when (playbackState) {
                                Player.STATE_BUFFERING -> onStatus("Preparing immersive video…")
                                Player.STATE_READY -> onStatus("Playing in full space")
                                Player.STATE_ENDED -> onStatus("Playback complete")
                                Player.STATE_IDLE -> Unit
                            }
                        }

                        override fun onPlayerError(error: PlaybackException) {
                            onStatus("This video could not be played on the current XR runtime.")
                        }
                    }
                )
                created.setVideoSurface(entity.getSurface())
                created.setMediaItem(MediaItem.fromUri(sourceUri))
                created.prepare()
                created.playWhenReady = true
            }
        } catch (error: Throwable) {
            entity.parent = null
            entity.dispose()
            onStatus("This video could not be initialized on the current XR runtime.")
            return false
        }
        surfaceEntity = entity
        player = exoPlayer
        return true
    }

    fun pause() {
        player?.pause()
    }

    fun resume() {
        player?.play()
    }

    private fun applyDynamicRange(entity: SurfaceEntity, range: DynamicRange) {
        val transfer = when (range) {
            DynamicRange.HLG -> SurfaceEntity.ContentColorMetadata.ColorTransfer.HLG
            DynamicRange.HDR10,
            DynamicRange.HDR10_PLUS,
            DynamicRange.DOLBY_VISION,
            -> SurfaceEntity.ContentColorMetadata.ColorTransfer.ST2084
            DynamicRange.SDR -> return
        }
        entity.contentColorMetadata = SurfaceEntity.ContentColorMetadata(
            colorSpace = SurfaceEntity.ContentColorMetadata.ColorSpace.BT2020,
            colorTransfer = transfer,
            colorRange = SurfaceEntity.ContentColorMetadata.ColorRange.LIMITED,
            maxContentLightLevel = 1000,
        )
    }

    private fun releasePlayback() {
        player?.clearVideoSurface()
        player?.release()
        player = null
        surfaceEntity?.parent = null
        surfaceEntity?.dispose()
        surfaceEntity = null
    }

    override fun close() {
        releasePlayback()
    }
}
