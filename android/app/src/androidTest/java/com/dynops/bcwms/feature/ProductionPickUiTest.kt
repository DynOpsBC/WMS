package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.LocalNavigator
import org.json.JSONObject
import org.junit.Rule
import org.junit.Test

/** Real production composables, with fixture data and no BC writes or PIN bypass. */
class ProductionPickUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun releasedOrderShowsReadyLpActionAndOpensScanner() {
        check(!BcApi.hasToken(InstrumentationRegistry.getInstrumentation().targetContext)) {
            "This test requires an offline debug app."
        }
        val row = JSONObject("""{"prodOrderNo":"RLO.B100845","status":"Released",
            "prodOrderLineNo":10000,"componentLineNo":20000,"itemNo":"AB.00150",
            "description":"Üretim bileşeni","remainingQuantity":100,"quantity":100,
            "unitOfMeasureCode":"ADET","locationCode":"MERKEZDEPO","binCode":"DO.01",
            "producedItemNo":"TEST-URUN","producedItemDescription":"Test üretim emri",
            "productionQuantity":100,"dueDate":"2026-09-21"}""")
        compose.setContent {
            CompositionLocalProvider(LocalNavigator provides {}) {
                MaterialTheme { Surface(Modifier.fillMaxSize()) {
                    ConsumptionTab { _, _ -> BcApi.PagedItemsResult(listOf(row), complete = true) }
                } }
            }
        }
        compose.waitUntil(10000) {
            compose.onAllNodesWithText("RLO.B100845").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("RLO.B100845").performClick()
        compose.onNodeWithText("Hazır LP ile Ambar Çekme")
            .performScrollTo().assertIsDisplayed().assertIsEnabled()
        screenshot("production-ready-lp-button")
        compose.onNodeWithText("Hazır LP ile Ambar Çekme").performClick()
        compose.onNodeWithText("Üretim emri: RLO.B100845").assertIsDisplayed()
        compose.onNodeWithText("Hazırlanan LP").assertIsDisplayed()
        compose.onNodeWithText("LP İçeriğini Göster").assertIsNotEnabled()
        screenshot("production-ready-lp-scanner")
    }

    private fun screenshot(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val target = java.io.File(instrumentation.targetContext.getExternalFilesDir(null), "$name.png")
        target.outputStream().use {
            instrumentation.uiAutomation.takeScreenshot()
                .compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
    }
}
