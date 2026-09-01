plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

// APFS/exFAT external workspaces can occasionally refuse AGP's atomic temp
// directory cleanup. CI and local verification may opt into a local build
// directory without changing where source or final checked-in files live.
providers.environmentVariable("OPENSTREAM_ANDROID_BUILD_DIR").orNull?.let { requestedBuildDir ->
    val localBuildDir = file(requestedBuildDir)
    require(localBuildDir.isAbsolute) { "OPENSTREAM_ANDROID_BUILD_DIR must be absolute" }
    layout.buildDirectory.set(localBuildDir)
}

val openStreamKeystoreFile = providers.environmentVariable("OPENSTREAM_KEYSTORE_FILE")
val openStreamKeystorePass = providers.environmentVariable("OPENSTREAM_KEYSTORE_PASS")
val openStreamKeyAlias = providers.environmentVariable("OPENSTREAM_KEY_ALIAS")
val openStreamKeyPass = providers.environmentVariable("OPENSTREAM_KEY_PASS")

android {
    namespace = "com.orgista.openstream"
    compileSdk {
        version = release(37) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "com.orgista.openstream"
        minSdk = 26
        targetSdk = 37
        // One Play listing serves TV and mobile with two artifacts: the
        // google-tv AAB owns versionCode 1, this mobile/tablet AAB ships as 2.
        // Keep the offset (TV = N, mobile = N+1) when bumping releases.
        versionCode = 2
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // Cloudflare's public download endpoint powers the pre-playback speed
        // probe. Kept here (a real, shippable URL) so it can be pointed at a
        // different host — or blanked to disable the probe — without a code
        // change. WebXrBackend's viewer URL is per-build-type below, since the
        // dev value is a localhost loopback that must never ship.
        buildConfigField(
            "String",
            "SPEED_TEST_URL",
            "\"https://speed.cloudflare.com/__down\""
        )

        // FFmpeg software decoders ship native libs per ABI; the target
        // devices are 64-bit ARM, so ship only that to keep the APK lean.
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    signingConfigs {
        create("release") {
            val keystorePath = openStreamKeystoreFile.orNull
            if (!keystorePath.isNullOrBlank()) {
                storeFile = file(keystorePath)
                storePassword = openStreamKeystorePass.orNull
                keyAlias = openStreamKeyAlias.orNull
                keyPassword = openStreamKeyPass.orNull
            }
        }
    }

    buildTypes {
        getByName("debug") {
            // Local Vite dev server for the standards-based WebXR viewer.
            buildConfigField(
                "String",
                "WEB_XR_URL",
                "\"http://127.0.0.1:5173/xr/viewer\""
            )
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // TODO: set the production WebXR viewer URL before shipping a
            // release build. While this is empty, WebXrBackend reports the
            // immersive launch as unavailable and playback falls back to the
            // flat player, so no dead localhost loopback is ever opened.
            buildConfigField("String", "WEB_XR_URL", "\"\"")
        }
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.all {
            it.useJUnit()
        }
    }
}

dependencies {
    // Pinned to 1.10.1 to exactly match the NextLib FFmpeg extension build
    // (its version scheme is <media3>-<nextlib>), guaranteeing decoder ABI
    // compatibility.
    val media3Version = "1.10.1"

    implementation(platform("androidx.compose:compose-bom:2026.06.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core-ktx:1.19.0")

    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-exoplayer-dash:$media3Version")
    implementation("androidx.media3:media3-exoplayer-hls:$media3Version")
    implementation("androidx.media3:media3-ui:$media3Version")

    // FFmpeg software decoders for Media3 (the Jellyfin/Findroid approach):
    // decode codecs the hardware can't — TrueHD, DTS, E-AC3, FLAC, etc. — on
    // device in real time. This is Infuse's model: direct play with a
    // software-decode fallback, not server-style re-encoding.
    implementation("io.github.anilbeesetti:nextlib-media3ext:1.10.1-0.13.0")

    // Pure-Java SMB2/3 client for direct NAS access; no gateway required.
    implementation("eu.agno3.jcifs:jcifs-ng:2.1.10")

    // Async image loading for remote TMDB posters/backdrops.
    implementation("io.coil-kt:coil-compose:2.7.0")

    // Small, on-device QR encoder for the temporary LAN setup URL. The
    // payload never leaves the device and the one-time code is not embedded.
    implementation("com.google.zxing:core:3.5.4")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20260719")
}
