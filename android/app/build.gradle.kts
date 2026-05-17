import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    // Path to key.properties is provided via BTC_KEYSTORE_PROPERTIES so no
    // signing secrets live in the repo. Unset = debug signing fallback below.
    System.getenv("BTC_KEYSTORE_PROPERTIES")?.let { path ->
        val f = File(path)
        if (f.exists()) f.inputStream().use { load(it) }
    }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile")?.isNotBlank() == true

android {
    namespace = "com.openbitcointracker.open_bitcoin_tracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.openbitcointracker.open_bitcoin_tracker"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Use the real release key when android/key.properties is present
            // (required for Play Store uploads). Falls back to debug signing so
            // `flutter run --release` still works locally without a keystore.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Ship only ARM ABIs in release. x86_64 in an Android bundle targets
            // emulators and a handful of Intel-based Android devices — not Linux
            // desktops (those use a separate Flutter desktop build). Scoped to
            // `release` only so debug runs on x86_64 emulators still work.
            // This filter only covers plugin .so files; the Flutter engine
            // itself is gated by the build CLI flag, so the upload command is:
            //   flutter build appbundle --release \
            //     --target-platform android-arm,android-arm64
            ndk {
                abiFilters += listOf("armeabi-v7a", "arm64-v8a")
            }
        }
    }
}

flutter {
    source = "../.."
}
