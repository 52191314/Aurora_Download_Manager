pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven { url = uri("https://jitpack.io") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

// ---------------------------------------------------------------------------
// Build channel detection — single source of truth for every module.
// Computed HERE (settings evaluate before any project script) and stored on
// the Gradle object, readable from :app and the feature modules via
// `gradle.extensions.getExtraProperties().get("auroraBuildChannel")`.
//   Play   → on-demand dynamic-feature modules (:ffmpeg, :torrent, :mediakit)
//   Fdroid → 100% FOSS compliant; no dynamic features, no prebuilt .so
//   GitHub → fat builds; all prebuilts bundled in base APK.
// ---------------------------------------------------------------------------
fun getAuroraBuildChannel(): String {
    // 1. Env var (CI / shell): highest priority.
    val envChannel = System.getenv("AURORA_BUILD_CHANNEL")?.lowercase()
    if (envChannel == "play" || envChannel == "fdroid" || envChannel == "github") return envChannel

    // 2. --dart-define=AURORA_BUILD_CHANNEL=... — Flutter passes dart-defines
    //    to Gradle as `-Pdart-defines=<base64 comma-joined list>`.
    val definesProp = providers.gradleProperty("dart-defines").orNull
    if (definesProp != null) {
        val decodedDefines = definesProp.split(',').mapNotNull { raw ->
            runCatching {
                String(java.util.Base64.getDecoder().decode(raw))
            }.getOrNull()
        }
        for (define in decodedDefines) {
            if (define.startsWith("AURORA_BUILD_CHANNEL=")) {
                val value = define.substringAfter("AURORA_BUILD_CHANNEL=").lowercase()
                if (value.isNotEmpty()) return value
            }
        }
        if (definesProp.contains("QVVST1JBX0JVSUxEX0NIQU5ORUw9cGxheQ==")) return "play"
        if (definesProp.contains("QVVST1JBX0JVSUxEX0NIQU5ORUw9ZmRyb2lk")) return "fdroid"
        if (definesProp.contains("QVVST1JBX0JVSUxEX0NIQU5ORUw9Z2l0aHVi")) return "github"
    }

    // 3. Legacy single-encoded property, then the explicit -P property.
    val encodedProp = providers.gradleProperty("dart-defines-encoded").orNull
    val decoded = encodedProp?.let {
        runCatching { String(java.util.Base64.getDecoder().decode(it)) }.getOrNull()
    }
    if (decoded?.contains("AURORA_BUILD_CHANNEL=play") == true) return "play"
    if (decoded?.contains("AURORA_BUILD_CHANNEL=fdroid") == true) return "fdroid"
    if (decoded?.contains("AURORA_BUILD_CHANNEL=github") == true) return "github"

    val channelProp = providers.gradleProperty("auroraBuildChannel").orNull?.lowercase()
    if (channelProp == "play" || channelProp == "fdroid" || channelProp == "github") return channelProp

    return "github"
}

val auroraChannel = getAuroraBuildChannel()
val isPlay = auroraChannel == "play"
val isFdroid = auroraChannel == "fdroid"

gradle.extensions.getExtraProperties().set("auroraBuildChannel", auroraChannel)
gradle.extensions.getExtraProperties().set("auroraPlayChannel", isPlay)
gradle.extensions.getExtraProperties().set("auroraFdroidChannel", isFdroid)

include(":app")
if (!isFdroid) {
    include(":ffmpeg")
    include(":torrent")
    include(":mediakit")
}

if (isFdroid) {
    gradle.settingsEvaluated {
        findProject(":libtorrent_flutter")?.projectDir = file("stubs/libtorrent_flutter")
    }
}
