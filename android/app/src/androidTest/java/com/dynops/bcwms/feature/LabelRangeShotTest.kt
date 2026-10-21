package com.dynops.bcwms.feature

import android.graphics.Bitmap
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import java.io.File

/** Örnek (uydurma) verilerle sıra aralığı seçimli önizleme; müşteri listesi kullanılmaz. */
class LabelRangeShotTest {
    @get:Rule val compose = createComposeRule()

    private fun shoot(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val file = File(instrumentation.targetContext.getExternalFilesDir(null), "$name.png")
        file.outputStream().use { instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, it) }
        instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /sdcard/Download/$name.png").use {
            java.io.FileInputStream(it.fileDescriptor).use { input -> input.readBytes() }
        }
    }

    private val rows = (1..1535).map { ExcelLabelRow(it, "ÖRN-${1000 + it % 37}", "Örnek ürün ${it % 37}", "R.${(it - 1) / 20 + 1}.${(it - 1) % 20 + 1}") }

    @Test fun rangePreview() {
        var printed: List<Int> = emptyList()
        compose.setContent { MaterialTheme { Surface {
            ExcelLabelsPreview(rows, busy = false, source = "Hazır göz listesi.", resume = 501..1535,
                onDismiss = {}, onPrint = { printed = it.map { r -> r.order } })
        } } }
        compose.waitForIdle(); Thread.sleep(800)
        shoot("label-range-1-all")
        compose.onNodeWithTag("label-range-from").performTextReplacement("498")
        compose.onNodeWithTag("label-range-to").performTextReplacement("500")
        compose.waitForIdle(); Thread.sleep(500)
        compose.onNodeWithText("Yazdır (3)").assertExists()
        shoot("label-range-2-498-500")
        compose.onNodeWithTag("label-range-preset-501").performClick()
        compose.waitForIdle(); Thread.sleep(500)
        compose.onNodeWithText("Yazdır (200)").assertExists()
        shoot("label-range-5-preset")
        compose.onNodeWithTag("label-range-resume").performClick()
        compose.waitForIdle(); Thread.sleep(500)
        shoot("label-range-3-resume")
        compose.onNodeWithTag("label-range-from").performTextReplacement("600")
        compose.onNodeWithTag("label-range-to").performTextReplacement("500")
        compose.waitForIdle(); Thread.sleep(500)
        shoot("label-range-4-error")
        compose.onNodeWithTag("label-range-from").performTextReplacement("498")
        compose.onNodeWithTag("label-range-to").performTextReplacement("500")
        compose.onNodeWithTag("label-range-print").performClick()
        compose.runOnIdle { assertEquals(listOf(498, 499, 500), printed) }
    }
}
