plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

providers.environmentVariable("OPENSTREAM_GOOGLE_TV_BUILD_DIR").orNull?.let { requestedBuildDir ->
    val localBuildDir = file(requestedBuildDir)
    require(localBuildDir.isAbsolute) { "OPENSTREAM_GOOGLE_TV_BUILD_DIR must be absolute" }
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
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Cloudflare's public download endpoint for the pre-playback speed probe;
        // host-overridable (or blankable to disable) without a code change.
        buildConfigField("String", "SPEED_TEST_URL", "\"https://speed.cloudflare.com/__down\"")
        ndk { abiFilters += "arm64-v8a" }
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
            buildConfigField("String", "WEB_XR_URL", "\"http://127.0.0.1:5173/xr/viewer\"")
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // TODO: set the production WebXR viewer URL before shipping a release
            // build. Empty here means WebXrBackend disables the immersive launch
            // and playback falls back to the flat player (no localhost loopback).
            buildConfigField("String", "WEB_XR_URL", "\"\"")
        }
    }

    sourceSets {
        getByName("main") {
            java.directories.apply {
                clear()
                add("../../android-xr/app/src/main/java")
            }
            kotlin.directories.apply {
                clear()
                add("../../android-xr/app/src/main/java")
            }
            res.directories.apply {
                clear()
                add("src/main/res")
                add("../../android-xr/app/src/main/res")
            }
            assets.directories.apply {
                clear()
                add("../../android-xr/app/src/main/assets")
            }
        }
        getByName("test") {
            java.directories.apply {
                clear()
                add("../../android-xr/app/src/test/java")
            }
            kotlin.directories.apply {
                clear()
                add("../../android-xr/app/src/test/java")
            }
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
    testOptions { unitTests.all { it.useJUnit() } }
}

dependencies {
    val media3Version = "1.10.1"

    implementation(platform("androidx.compose:compose-bom:2026.06.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core-ktx:1.19.0")

    // Current stable TV-native focus, glow, card, and navigation primitives.
    implementation("androidx.tv:tv-material:1.1.0")
    implementation("androidx.tv:tv-foundation:1.0.0")

    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-exoplayer-dash:$media3Version")
    implementation("androidx.media3:media3-exoplayer-hls:$media3Version")
    implementation("androidx.media3:media3-ui:$media3Version")
    implementation("androidx.media3:media3-session:$media3Version")
    implementation("io.github.anilbeesetti:nextlib-media3ext:1.10.1-0.13.0")
    implementation("eu.agno3.jcifs:jcifs-ng:2.1.10")
    implementation("com.google.zxing:core:3.5.4")
    implementation("io.coil-kt:coil-compose:2.7.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20260719")
}
