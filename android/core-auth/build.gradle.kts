plugins {
  alias(libs.plugins.android.library)
  alias(libs.plugins.kotlin.android)
}

android {
  namespace = "com.dynops.bcwms.core.auth"
  compileSdk = 35
  defaultConfig { minSdk = 26 }
}

dependencies {
  implementation(libs.msal)
  implementation(libs.security.crypto)
}

