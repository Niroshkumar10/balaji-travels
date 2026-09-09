import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// FCM / Firebase:
//  1. add `id("com.google.gms.google-services") version "4.4.2" apply false`
//     to android/settings.gradle.kts pluginManagement plugins { } block,
//  2. add `id("com.google.gms.google-services")` to the plugins { } above,
//  3. drop google-services.json into android/app/.
// Until then PushService no-ops and the app builds without Firebase.

// Google Maps SDK key — read from android/local.properties (MAPS_API_KEY=...),
// falling back to the -PMAPS_API_KEY Gradle property, then empty. Never commit
// the real key; restrict it by package name + SHA-1 in the Cloud console.
val mapsApiKey: String = run {
    val props = Properties()
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { props.load(it) }
    (props.getProperty("MAPS_API_KEY")
        ?: (project.findProperty("MAPS_API_KEY") as String?)
        ?: "")
}

android {
    namespace = "com.redtaxi.redtaxi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.redtaxi.redtaxi"
        // flutter_local_notifications + geolocator background need 21+/23+;
        // firebase_messaging 15 needs 23.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    buildTypes {
        release {
            // TODO: real signing config before publishing.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
