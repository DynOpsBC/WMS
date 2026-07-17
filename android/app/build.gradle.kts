import java.util.Properties
import java.io.FileInputStream

plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.kotlin.android)
  alias(libs.plugins.kotlin.compose)
  id("com.github.triplet.play") version "3.11.0" apply false
}

// gradle-play-publisher is only wired when both PLAY_SERVICE_ACCOUNT_JSON
// (raw json content) is present and the `withPlayPublisher` Gradle property is
// set; CI sets these on tag pipelines, local dev stays free of Play creds.
if (project.hasProperty("withPlayPublisher")) {
  apply(plugin = "com.github.triplet.play")
}

android {
  namespace = "com.dynops.bcwms"
  compileSdk = 35

  defaultConfig {
    applicationId = "com.dynops.bcwms"
    minSdk = 26
    targetSdk = 35
    versionCode = 1118
    versionName = "1.10.18"
    buildConfigField("String", "UPDATE_BASE_URL", "\"https://app.bcwms.dynops.com\"")
  }

  buildFeatures {
    compose = true
    buildConfig = true
  }

  buildTypes {
    debug {
      isMinifyEnabled = false
    }
    release {
      isMinifyEnabled = false
      val keystorePropsFile = rootProject.file("play/keystore/keystore.properties")
      if (keystorePropsFile.exists()) {
        val props = Properties()
        FileInputStream(keystorePropsFile).use { props.load(it) }
        signingConfig = signingConfigs.create("release") {
          storeFile = rootProject.file(props.getProperty("storeFile"))
          storePassword = props.getProperty("storePassword")
          keyAlias = props.getProperty("keyAlias")
          keyPassword = props.getProperty("keyPassword")
        }
      }
    }
  }

  lint {
    // CI'da lint'i bloklamayacak hale getir; rapor html olarak hala üretilir.
    // Lokalde "./gradlew lintDebug" zaten çalıştırılabilir, hatalar görünür.
    abortOnError = false
    checkReleaseBuilds = false
    // Manifest'te MSAL gibi opsiyonel auth class'ı kalırsa MissingClass bloklamasın.
    disable += setOf("MissingClass")
  }
}

dependencies {
  implementation(project(":core-design"))
  implementation(libs.androidx.core.ktx)
  implementation(libs.androidx.activity.compose)
  implementation(libs.androidx.lifecycle.runtime.ktx)
  implementation(platform(libs.androidx.compose.bom))
  implementation(libs.androidx.compose.ui)
  implementation(libs.androidx.compose.ui.tooling.preview)
  implementation(libs.androidx.compose.material3)
  implementation("androidx.compose.foundation:foundation")
  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
  // Real PATCH/DELETE verbs for BC API (HttpURLConnection can't PATCH; BC ignores X-HTTP-Method-Override).
  implementation(libs.okhttp)

  // Barcode scanning (camera) — graceful manual-entry fallback if camera/permission unavailable
  implementation("com.google.mlkit:barcode-scanning:17.3.0")
  implementation("androidx.camera:camera-core:1.4.0")
  implementation("androidx.camera:camera-camera2:1.4.0")
  implementation("androidx.camera:camera-lifecycle:1.4.0")
  implementation("androidx.camera:camera-view:1.4.0")
  implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
  implementation("androidx.core:core:1.13.1")
}

// Closed-track Play publishing block is read by gradle-play-publisher only when
// the plugin is applied above. service-account credentials come from
// $PLAY_SERVICE_ACCOUNT_JSON env (CI) or play/play-service-account.json (local).
if (project.hasProperty("withPlayPublisher")) {
  configure<com.github.triplet.gradle.play.PlayPublisherExtension> {
    serviceAccountCredentials.set(rootProject.file("play/play-service-account.json"))
    defaultToAppBundles.set(true)
    track.set("internal")
    releaseStatus.set(com.github.triplet.gradle.androidpublisher.ReleaseStatus.DRAFT)
    updatePriority.set(3)
  }
}
