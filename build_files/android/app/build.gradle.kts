// SPDX-FileCopyrightText: 2026 Blender Authors
//
// SPDX-License-Identifier: GPL-2.0-or-later

// Packages a Blender build made with the Android NDK into an APK.
//
// Native code is NOT built by Gradle: Blender is far too large for `externalNativeBuild`.
// `build_android.sh` builds and installs it with CMake first, then this project picks up:
//   <blender.installDir>/libmain.so              -> lib/arm64-v8a/libmain.so
//   <blender.installDir>/lib/*.so (if any)       -> lib/arm64-v8a/
//   <blender.installDir>/<blender.version>/      -> assets/blender/<blender.version>/
// together with SDL3's Java glue code.

plugins {
    id("com.android.application")
}

val installDir = file(providers.gradleProperty("blender.installDir").get())
val sdlSourceDir = file(providers.gradleProperty("sdl.sourceDir").get())
val blenderVersion = providers.gradleProperty("blender.version").get()

val stagedJniLibs = layout.buildDirectory.dir("blender/jniLibs")
val stagedAssets = layout.buildDirectory.dir("blender/assets")

android {
    namespace = "org.blender.android"
    compileSdk = 35
    ndkVersion = "27.2.12479018"

    defaultConfig {
        applicationId = "org.blender.android"
        minSdk = 29 // Vulkan 1.1 + required extensions.
        targetSdk = 35
        versionCode = 504
        versionName = blenderVersion
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        buildConfigField("String", "BLENDER_VERSION", "\"$blenderVersion\"")
    }

    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // Replace with a real signing config for distribution.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDir(File(sdlSourceDir, "android-project/app/src/main/java"))
            jniLibs.srcDir(stagedJniLibs)
            assets.srcDir(stagedAssets)
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false // Keep .so uncompressed & page aligned in the APK.
        }
    }

    androidResources {
        // Blender's data files are read once on extraction, avoid double compression of .blend.
        noCompress += listOf("blend")
    }
}

val stageBlenderNative by tasks.registering(Copy::class) {
    description = "Copy libmain.so and bundled shared libraries from the Blender install."
    from(installDir) { include("libmain.so") }
    from(File(installDir, "lib")) { include("*.so") }
    into(stagedJniLibs.map { it.dir("arm64-v8a") })
    doFirst {
        if (!File(installDir, "libmain.so").exists()) {
            throw GradleException(
                "libmain.so not found in $installDir, run build_files/android/build_android.sh first."
            )
        }
    }
}

val stageBlenderAssets by tasks.registering(Copy::class) {
    description = "Copy Blender's data files (datafiles, scripts, python) into the APK assets."
    from(File(installDir, blenderVersion))
    into(stagedAssets.map { it.dir("blender/$blenderVersion") })
    exclude("**/__pycache__/**", "**/*.pyc", "**/tests/**")
}

tasks.named("preBuild") {
    dependsOn(stageBlenderNative, stageBlenderAssets)
}
