package com.cyberbanksy.openstream.xr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SceneCoreVideoPolicyTest {
    @Test
    fun mapsStandardSpatialSurfaces() {
        assertEquals(SceneSurfaceShape.QUAD, plan(Projection.FLAT).shape)
        assertEquals(SceneSurfaceShape.HEMISPHERE, plan(Projection.EQUIRECTANGULAR_180).shape)
        assertEquals(SceneSurfaceShape.SPHERE, plan(Projection.EQUIRECTANGULAR_360).shape)
        assertTrue(plan(Projection.EQUIRECTANGULAR_360).directlyRenderable)
    }

    @Test
    fun routesProjectionSpecificUvFormatsToNativeMeshRenderer() {
        assertFalse(plan(Projection.FISHEYE_180).directlyRenderable)
        assertFalse(plan(Projection.CUBEMAP_360).directlyRenderable)
        assertEquals(SceneSurfaceShape.CUSTOM_MESH, plan(Projection.CUBEMAP_360).shape)
    }

    @Test
    fun classifiesPackedAndMultiviewLayouts() {
        assertEquals(StereoLayout.SIDE_BY_SIDE, ImmersiveMediaClassifier.stereo("movie sbs 3d"))
        assertEquals(StereoLayout.TOP_BOTTOM, ImmersiveMediaClassifier.stereo("movie over-under"))
        assertEquals(
            StereoLayout.MULTIVIEW_LEFT_PRIMARY,
            ImmersiveMediaClassifier.stereo("spatial mv-hevc"),
        )
    }

    @Test
    fun validatesIntentSchemeAllowlist() {
        assertTrue(MainActivity.isAllowedScheme("content"))
        assertTrue(MainActivity.isAllowedScheme("file"))
        assertTrue(MainActivity.isAllowedScheme("http"))
        assertTrue(MainActivity.isAllowedScheme("https"))
        assertTrue(MainActivity.isAllowedScheme("HTTPS"))

        assertFalse(MainActivity.isAllowedScheme("javascript"))
        assertFalse(MainActivity.isAllowedScheme("smb"))
        assertFalse(MainActivity.isAllowedScheme("data"))
        assertFalse(MainActivity.isAllowedScheme("ftp"))
        assertFalse(MainActivity.isAllowedScheme("intent"))
        assertFalse(MainActivity.isAllowedScheme(null))
        assertFalse(MainActivity.isAllowedScheme(""))
    }

    @Test
    fun classifiesDynamicRangeSignals() {
        assertEquals(DynamicRange.DOLBY_VISION, ImmersiveMediaClassifier.dynamicRange("Dolby Vision Profile 8"))
        assertEquals(DynamicRange.HDR10_PLUS, ImmersiveMediaClassifier.dynamicRange("HDR10+ master"))
        assertEquals(DynamicRange.HLG, ImmersiveMediaClassifier.dynamicRange("Broadcast HLG"))
        assertEquals(DynamicRange.HDR10, ImmersiveMediaClassifier.dynamicRange("HDR10"))
        assertEquals(DynamicRange.SDR, ImmersiveMediaClassifier.dynamicRange("Standard Dynamic Range"))
    }

    private fun plan(projection: Projection): SceneCoreVideoPlan = SceneCoreVideoPolicy.plan(
        ImmersiveMedia(
            uri = null,
            projection = projection,
            stereoLayout = StereoLayout.MONO,
            dynamicRange = DynamicRange.SDR,
        )
    )
}
