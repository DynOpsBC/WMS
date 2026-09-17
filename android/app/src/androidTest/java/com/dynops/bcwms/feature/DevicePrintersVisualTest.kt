package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.assertEquals
import java.io.File

class DevicePrintersVisualTest {
    @get:Rule val compose = createComposeRule()
    @Test fun deviceTargetsUpdateIndependentlyAndPersist() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val oldLabel = getDefaultPrinter(context)
        val oldDoc = getDefaultPrinter(context, PRINTER_USAGE_DOCUMENT)
        try {
            setDefaultPrinter(context, "DEPO-ZEBRA")
            setDefaultPrinter(context, "OFIS-LASER", PRINTER_USAGE_DOCUMENT)
            compose.setContent { MaterialTheme { DevicePrintersDialog {} } }
            compose.onNodeWithText("DEPO-ZEBRA").assertExists()
            compose.onNodeWithText("OFIS-LASER").assertExists()
            compose.runOnIdle { setDefaultPrinter(context, "PAKETLEME-ZEBRA") }
            compose.onNodeWithText("PAKETLEME-ZEBRA").assertExists()
            compose.onNodeWithText("OFIS-LASER").assertExists()
            assertEquals("PAKETLEME-ZEBRA", getDefaultPrinter(context))
            assertEquals("OFIS-LASER", getDefaultPrinter(context, PRINTER_USAGE_DOCUMENT))
            val file = File(context.getExternalFilesDir(null), "device-printers.png")
            file.outputStream().use { instrumentation.uiAutomation.takeScreenshot().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /sdcard/Download/device-printers.png").use {
                java.io.FileInputStream(it.fileDescriptor).use { input -> input.readBytes() }
            }
        } finally {
            setDefaultPrinter(context, oldLabel)
            setDefaultPrinter(context, oldDoc, PRINTER_USAGE_DOCUMENT)
        }
    }
}
