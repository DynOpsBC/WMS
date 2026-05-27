plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.kotlin.android)
  alias(libs.plugins.kotlin.compose)
}

android {
  namespace = "com.dynops.bcwms"
  compileSdk = 35

  defaultConfig {
    applicationId = "com.dynops.bcwms"
    minSdk = 26
    targetSdk = 35
    versionCode = 2
    versionName = "1.1.0"
  }

  buildFeatures {
    compose = true
  }

  buildTypes {
    debug {
      isMinifyEnabled = false
    }
    release {
      isMinifyEnabled = false
    }
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
}
