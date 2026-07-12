import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("rust")
}

val tauriProperties = Properties().apply {
    val propFile = file("tauri.properties")
    if (propFile.exists()) {
        propFile.inputStream().use { load(it) }
    }
}

android {
    compileSdk = 36
    namespace = "de.tobiaskneidl.nia_todo"

    signingConfigs {
        create("ciRelease") {
            storeFile = file(System.getProperty("user.home") + "/ci-keystore.jks")
            storePassword = "nia-todo-ci"
            keyAlias = "ci-key"
            keyPassword = "nia-todo-ci"
        }
    }

    defaultConfig {
        manifestPlaceholders["usesCleartextTraffic"] = "false"
        applicationId = "de.tobiaskneidl.nia_todo"
        minSdk = 24
        targetSdk = 36
        versionCode = tauriProperties.getProperty("tauri.android.versionCode", "1").toInt()
        versionName = tauriProperties.getProperty("tauri.android.versionName", "1.0")
        ndk {
            abiFilters += setOf("arm64-v8a")
        }
    }

    buildTypes {
        getByName("debug") {
            manifestPlaceholders["usesCleartextTraffic"] = "true"
            isDebuggable = true
            isJniDebuggable = true
            isMinifyEnabled = false
        }
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("ciRelease")
            proguardFiles(
                *fileTree(".") { include("**/*.pro") }
                    .plus(getDefaultProguardFile("proguard-android-optimize.txt"))
                    .toList().toTypedArray()
            )
        }
    }

    packaging {
        jniLibs {
            excludes.add("lib/x86/**")
            excludes.add("lib/x86_64/**")
            excludes.add("lib/armeabi-v7a/**")
        }
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }
    buildFeatures {
        buildConfig = true
    }
}

rust {
    rootDirRel = "../../../"
}

tasks.register("patchTauriWebChromeMicrophonePermission") {
    val webChromeClient = file("src/main/java/de/tobiaskneidl/nia_todo/generated/RustWebChromeClient.kt")
    doLast {
        if (!webChromeClient.exists()) return@doLast
        val source = webChromeClient.readText()
        val patched = source.replace(
            "      permissionList.add(Manifest.permission.MODIFY_AUDIO_SETTINGS)\n      permissionList.add(Manifest.permission.RECORD_AUDIO)",
            "      permissionList.add(Manifest.permission.RECORD_AUDIO)"
        )
        if (patched != source) {
            webChromeClient.writeText(patched)
            println("Patched Tauri WebView microphone permission request to RECORD_AUDIO only")
        }
    }
}

tasks.matching { it.name.startsWith("compile") && it.name.endsWith("Kotlin") }.configureEach {
    dependsOn("patchTauriWebChromeMicrophonePermission")
}

dependencies {
    implementation("androidx.webkit:webkit:1.14.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("androidx.credentials:credentials:1.5.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.5.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("com.google.android.gms:play-services-location:21.3.0")
    implementation("androidx.lifecycle:lifecycle-process:2.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.10.0")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.4")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.0")
}

apply(from = "tauri.build.gradle.kts")
