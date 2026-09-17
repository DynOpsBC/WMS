package com.dynops.bcwms.feature

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.ui.CompanyBrand
import com.dynops.bcwms.ui.CompanyLogo
import org.junit.Rule
import org.junit.Test
import java.io.File

class LogoShotTest {
    @get:Rule val compose = createComposeRule()

    @Test fun dkcLogoRenders() {
        compose.setContent { MaterialTheme { Surface { Column(Modifier.padding(16.dp)) {
            CompanyLogo(CompanyBrand.DKC, height = 28.dp)
            CompanyLogo(CompanyBrand.DKC, height = 48.dp)
            CompanyLogo(CompanyBrand.DKC, height = 96.dp)
        } } } }
        compose.waitForIdle()
        Thread.sleep(1500)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val file = File(instrumentation.targetContext.getExternalFilesDir(null), "logo-dkc.png")
        file.outputStream().use { instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, it) }
        instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /sdcard/Download/logo-dkc.png").use {
            java.io.FileInputStream(it.fileDescriptor).use { input -> input.readBytes() }
        }
    }
}
