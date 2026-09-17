package com.dynops.bcwms.feature

import android.graphics.Bitmap
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test
import java.io.File

class LabelsScreenShotTest {
    @get:Rule val compose = createComposeRule()

    private fun shoot(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val file = File(context.getExternalFilesDir(null), "$name.png")
        file.outputStream().use { instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, it) }
        instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /sdcard/Download/$name.png").use {
            java.io.FileInputStream(it.fileDescriptor).use { input -> input.readBytes() }
        }
    }

    @Test fun labelsScreens() {
        compose.setContent { MaterialTheme { Surface { LabelsModule() } } }
        compose.waitForIdle()
        Thread.sleep(1500)
        shoot("labels-bin")
        compose.onNodeWithText("Ürün Etiketi").performClick()
        compose.waitForIdle()
        Thread.sleep(800)
        shoot("labels-item")
    }
}
