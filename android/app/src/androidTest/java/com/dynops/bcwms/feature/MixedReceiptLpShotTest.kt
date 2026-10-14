package com.dynops.bcwms.feature

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.json.JSONObject
import org.junit.Rule
import org.junit.Test

/** Karma palet ekranının görüntüleri (kullanım dokümanı / saha anlatımı için). */
class MixedReceiptLpShotTest {
    @get:Rule val compose = createComposeRule()

    private fun screenshot(name: String) {
        val instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        // Yazılım klavyesi görüntüyü kapatmasın (sahadaki Zebra'da donanım tuşları var).
        instrumentation.uiAutomation.executeShellCommand("input keyevent 111").close()
        compose.waitForIdle()
        Thread.sleep(1500)
        // Dialog / bottom sheet ayrı pencere; ekranın tamamı UiAutomation ile alınır.
        val bitmap = instrumentation.uiAutomation.takeScreenshot()
        val file = java.io.File(instrumentation.targetContext.getExternalFilesDir(null), name)
        file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun line(lineNo: Int, item: String, description: String) = JSONObject()
        .put("lineNo", lineNo).put("itemNo", item).put("description", description)
        .put("unitOfMeasureCode", "ADET").put("quantity", 20020).put("qtyReceived", 0)
        .put("lotRequired", true).put("bulkLpCount", 0)

    @Test fun mixedPalletScreens() {
        val lines = listOf(line(10000, "AB.02316", "Kutu A"), line(20000, "AB.02317", "Kutu B"), line(30000, "AB.02092", "Kutu C"))
        compose.setContent { MaterialTheme { MixedReceiptLinePicker(lines, onDismiss = {}) {} } }
        compose.onNodeWithTag("mixed-pick-10000").performClick()
        compose.onNodeWithTag("mixed-pick-20000").performClick()
        screenshot("karma-1-urun-secimi.png")
    }

    @Test fun mixedPalletSheet() {
        val lines = listOf(line(10000, "AB.02316", "Kutu A"), line(20000, "AB.02317", "Kutu B"))
        compose.setContent { MaterialTheme { MixedReceiptLpSheet(lines, onDismiss = {}) { _, _, _ -> } } }
        compose.onNodeWithTag("mixed-lot-10000").performScrollTo().performTextInput("A102600")
        compose.onNodeWithTag("mixed-lot-20000").performScrollTo().performTextInput("A102601")
        compose.onNodeWithTag("mixed-pallet-count").performScrollTo().performTextInput("4")
        compose.onNodeWithTag("mixed-split").performScrollTo().performClick()
        compose.onNodeWithText("Karma Palet LP'leri").performScrollTo()
        screenshot("karma-2-urunler-ve-lotlar.png")
        compose.onNodeWithTag("mixed-qty-0-10000").performScrollTo()
        screenshot("karma-3-paletler.png")
        compose.onNodeWithTag("mixed-submit").performScrollTo()
        screenshot("karma-4-ozet.png")
    }
}
