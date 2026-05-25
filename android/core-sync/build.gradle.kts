plugins {
  alias(libs.plugins.android.library)
  alias(libs.plugins.kotlin.android)
}

android {
  namespace = "com.dynops.bcwms.sync"
  compileSdk = 35
  defaultConfig { minSdk = 26 }
}

dependencies {
  implementation(libs.work.runtime.ktx)
}

