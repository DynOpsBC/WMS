package com.dynops.bcwms

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.Surface
import com.dynops.bcwms.scanner.ScanBus
import com.dynops.bcwms.ui.BcwmsTheme

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    enableEdgeToEdge()
    // Cold-start: app launched directly by a DataWedge tarama intent'i.
    ScanBus.dispatch(intent)
    setContent {
      BcwmsTheme {
        Surface {
          AppRoot()
        }
      }
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    // Warm intent: app zaten foreground'da, Zebra sarı tetik tarayan
    // operatörün barkodunu ScanBus üzerinden aktif ekrana ulaştır.
    ScanBus.dispatch(intent)
  }
}
