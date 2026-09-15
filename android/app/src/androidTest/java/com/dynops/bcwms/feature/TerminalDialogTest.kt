package com.dynops.bcwms.feature

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.dynops.bcwms.scanner.ScanBus
import com.dynops.bcwms.scanner.ScanEvent
import com.dynops.bcwms.ui.QuantityDialogSheet
import com.dynops.bcwms.ui.groupLines
import com.dynops.bcwms.ui.pickLineCapacity
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.Before
import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.BcApi

/** Offline UI tests: use the separate debug app without a BC login. */
class TerminalDialogTest {
    @get:Rule val compose = createComposeRule()

    @Before fun requireOfflineTestApp() {
        check(!BcApi.hasToken(InstrumentationRegistry.getInstrumentation().targetContext)) {
            "These tests require an offline debug app without a BC login."
        }
    }

    private fun evidence(name: String) {
        compose.onAllNodes(isRoot()).fetchSemanticsNodes().forEachIndexed { index, _ ->
            compose.onAllNodes(isRoot())[index].printToLog("WMS-Audit-$name")
        }
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val target = java.io.File(instrumentation.targetContext.getExternalFilesDir(null), "$name.png")
        target.outputStream().use {
            instrumentation.uiAutomation.takeScreenshot().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
        instrumentation.uiAutomation.executeShellCommand("cp ${target.absolutePath} /sdcard/Download/wms-audit-$name.png").use {
            java.io.FileInputStream(it.fileDescriptor).use { input -> input.readBytes() }
        }
    }

    private fun waitForText(text: String) {
        try {
            compose.waitUntil(15000) { compose.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty() }
        } catch (failure: Throwable) {
            evidence("missing-text")
            throw failure
        }
    }

    @Test fun quantityLimitExplainsDisabledConfirmationAndCanBeCorrectedWithKeyboardOpen() {
        var accepted: Double? = null
        compose.setContent {
            MaterialTheme { QuantityDialogSheet(
                title = "Toplama miktarı", itemNo = "AUDIT-ITEM", initialQty = 5.0,
                initialUom = "ADET", maximumQuantity = 5.0, showLotSerial = false,
                onConfirm = { accepted = it.quantity }, onDismiss = {},
            ) }
        }
        compose.onNodeWithText("Miktar").performClick().performTextReplacement("6")
        compose.onNodeWithText("Onayla").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("Miktar kalan 5 ADET değerini aşamaz.").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Miktar").performScrollTo().performTextReplacement("3")
        compose.onNodeWithText("Onayla").performScrollTo().assertIsDisplayed().assertIsEnabled().performClick()
        evidence("quantity-confirm")
        compose.runOnIdle { assertEquals(3.0, accepted!!, 0.00001) }
    }

    @Test fun failedPalletLookupStillShowsScannerAndNeverEnablesConfirmation() {
        val row = JSONObject("""{"no":"PI-AUDIT","lineNo":10000,"itemNo":"AUDIT-ITEM",
            "description":"Test ürünü","locationCode":"DEPO","binCode":"A-01",
            "lotNo":"LOT-A","unitOfMeasureCode":"ADET","qtyOutstanding":5}""")
        compose.setContent { MaterialTheme {
            PalletPickSheet("PI-AUDIT", groupLines(listOf(row), ::pickLineCapacity).single(), {}, {})
        } }
        waitForText("Toplama satırlarının tamamı alınamadı.")
        compose.onNodeWithText("Paletin QR kodunu okut").performScrollTo().assertIsDisplayed().assertIsFocused()
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.sendStringSync("LP000005")
        instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_ENTER)
        waitForText("LP000005 okutuldu;")
        compose.waitUntil(5000) {
            var keyboardVisible = true
            androidx.test.espresso.Espresso.onView(
                androidx.test.espresso.matcher.ViewMatchers.withContentDescription("Paletin QR kodunu okut"),
            ).check { view, error ->
                if (error != null) throw error
                val insets = androidx.core.view.ViewCompat.getRootWindowInsets(view)
                org.junit.Assert.assertNotNull(insets)
                keyboardVisible = insets!!.isVisible(androidx.core.view.WindowInsetsCompat.Type.ime())
            }
            !keyboardVisible
        }
        compose.onNodeWithText("LP000005 okutuldu;", substring = true).performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Okutulan Paletleri Onayla").performScrollTo().assertIsNotEnabled()
        evidence("pallet-failure")
    }

    @Test fun unavailableLotLookupCanBeRetriedWithoutLosingEnteredQuantity() {
        compose.setContent { MaterialTheme { QuantityDialogSheet(
            title = "Lot kontrolü", itemNo = "AUDIT-ITEM", initialQty = 3.0,
            autoDetectLotFromStock = true, onConfirm = {}, onDismiss = {},
        ) } }
        waitForText("Stoktaki lotlar doğrulanamadı.")
        compose.onNodeWithText("Lotları yeniden kontrol et").performScrollTo().assertIsEnabled().performClick()
        compose.waitForIdle()
        compose.onNodeWithText("Miktar").performScrollTo().assertTextContains("3")
        compose.onNodeWithText("Onayla").performScrollTo().assertIsNotEnabled()
        evidence("lot-retry")
    }

    @Test fun receiptMteLookupFailureKeepsPrintingDisabledAndAllowsLeavingPostedReceipt() {
        var dismissed = false
        compose.setContent { MaterialTheme {
            ReceiptMteSheet("MTE-TEST-RECEIPT", onDismiss = { dismissed = true })
        } }
        waitForText("LP listesi tamamlanamadı.")
        compose.onNodeWithText("Mal kabul kaydedildi · MTE").assertIsDisplayed()
        compose.onNodeWithText("Seçilen MTE'leri Yazdır (0)").assertIsDisplayed().assertIsNotEnabled()
        compose.onNodeWithText("Yenile").assertIsDisplayed().assertIsEnabled().performClick()
        waitForText("LP listesi tamamlanamadı.")
        compose.onNodeWithText("Seçilen MTE'leri Yazdır (0)").assertIsNotEnabled()
        evidence("receipt-mte-failure")
        compose.onNodeWithText("Devam Et").assertIsDisplayed().assertIsEnabled().performClick()
        compose.runOnIdle { org.junit.Assert.assertTrue(dismissed) }
    }
}
