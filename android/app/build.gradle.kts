plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.mebn.reader"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.mebn.reader"
        // PDF text, for selecting and highlighting, arrived in Android 15.
        minSdk = 35
        targetSdk = 37
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        // The sync server, fixed at build time like the desktop's VITE_SERVER_URL and iOS's
        // READER_SERVER_URL. 10.0.2.2 is the emulator's address for the host's localhost.
        debug {
            buildConfigField("String", "SERVER_URL", "\"http://10.0.2.2:8080\"")
        }
        release {
            buildConfigField("String", "SERVER_URL", "\"https://reader.marnil.dev\"")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.browser)
    implementation(libs.androidx.compose.material.icons)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)
    // Only for PDF metadata and outlines, which PdfRenderer doesn't read.
    implementation(libs.pdfbox)
    debugImplementation(libs.androidx.compose.ui.tooling)
}
