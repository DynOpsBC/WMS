package com.dynops.bcwms.feature

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.*
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test
import java.io.File

class TerminalPrinterShotTest {
    @get:Rule val compose = createComposeRule()

    @Test fun barAndScreenRender() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val oldLabel = getDefaultPrinter(context)
        val oldDoc = getDefaultPrinter(context, PRINTER_USAGE_DOCUMENT)
        try {
            setDefaultPrinter(context, "P0123456789ABCDEF")
            setDefaultPrinter(context, "PFEDCBA9876543210", PRINTER_USAGE_DOCUMENT)
            compose.setContent { MaterialTheme { Surface { Column {
                LabelPrinterBar(onOpenPrinters = {})
                TerminalPrintersScreen(onChange = {})
            } } } }
            compose.waitForIdle()
            Thread.sleep(1500)
            compose.onAllNodesWithText("Etiket yazıcısı").assertCountEquals(2)
            compose.onNodeWithText("Belge yazıcısı").assertExists()
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val file = File(context.getExternalFilesDir(null), "terminal-printers.png")
            file.outputStream().use { instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, it) }
            instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /sdcard/Download/terminal-printers.png").use {
                java.io.FileInputStream(it.fileDescriptor).use { input -> input.readBytes() }
            }
        } finally {
            setDefaultPrinter(context, oldLabel)
            setDefaultPrinter(context, oldDoc, PRINTER_USAGE_DOCUMENT)
        }
    }
}
