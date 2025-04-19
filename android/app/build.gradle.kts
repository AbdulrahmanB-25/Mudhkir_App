plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mudhkir_app"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.mudhkir_app"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        manifestPlaceholders["ALARM_PERMISSION"] = true
    }

    buildTypes {
        getByName("release") {
            // Removed the debug signing configuration
        }
    }

    sourceSets {
        getByName("main") {
            res.srcDirs("src/main/res", "src/main/res/raw") // Ensure raw directory is included
        }
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-base:18.2.0") // Ensure Google Play Services is included
    implementation("com.google.android.gms:play-services-tasks:18.0.2") // Required for permissions
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.firebase:firebase-firestore-ktx:24.10.2") // Update Firestore
    implementation("com.google.firebase:firebase-firestore:24.10.2")
    implementation("androidx.work:work-runtime-ktx:2.8.1") // For background tasks
    implementation("com.google.android.gms:play-services-tasks:18.0.2") // For exact alarms
}

flutter {
    source = "../.."
}

