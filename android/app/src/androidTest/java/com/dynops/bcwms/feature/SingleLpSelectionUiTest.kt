package com.dynops.bcwms.feature

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.BcApi
import org.json.JSONObject
import org.junit.Rule
import org.junit.Test

/** Exercises the actual sheet without credentials or warehouse writes. */
class SingleLpSelectionUiTest {
    @get:Rule val compose = createComposeRule()

    private fun open(supported: Boolean) {
        check(!BcApi.hasToken(InstrumentationRegistry.getInstrumentation().targetContext))
        fun entry(no: Int, qty: Int) = JSONObject()
            .put("entryNo", no).put("itemNo", "AB.00102").put("lotNo", if (no == 12435) "A100896" else "A100897")
            .put("locationCode", "MERKEZDEPO").put("baseUnitOfMeasure", "ADET")
            .put("lpAllocatableQuantity", qty)
        compose.setContent { MaterialTheme {
            BulkLpBuildSheet(
                singleLpMode = true,
                loadCapabilities = { BcApi.LpScanCapabilities(
                    metadataLoaded = true, pickLineSources = true,
                    putAwayPlacementFromLp = true, bulkLpPlan = true,
                    httpCode = 200, multiEntrySingleLp = supported,
                ) },
                loadStockPage = { _, path -> BcApi.PagedItemsResult(
                    if (path.startsWith("licensePlateTemplates")) emptyList()
                    else listOf(entry(12435, 2330), entry(1042, 6030)), complete = true,
                ) },
                onDismiss = {}, onBuilt = {},
            )
        } }
        compose.onNodeWithText("Ürün No / Stok Kayıt No / Lot No").performTextInput("AB.00102")
        compose.onNodeWithText("Stokları Getir").performClick()
        compose.waitUntil(10000) {
            compose.onAllNodesWithText("#12435 · AB.00102").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("#12435 · AB.00102").performScrollTo().performClick()
        compose.onNodeWithText("#1042 · AB.00102").performScrollTo().performClick()
        compose.onNodeWithText("Kullanılacak Stok Kayıtları (2 seçili)").assertExists()
        compose.onNodeWithText("LP Şablonu").performScrollTo().performTextInput("PALET")
    }

    @Test fun differentLotsRemainSelectedAndCreateOneLp() {
        open(true)
        compose.onNodeWithText("Tekli LP'yi Oluştur").performScrollTo().assertIsEnabled()
        compose.onNodeWithText("#12435 · AB.00102").performScrollTo().performClick()
        compose.onNodeWithText("Kullanılacak Stok Kayıtları (1 seçili)").assertExists()
    }

    @Test fun unsupportedServerExplainsAndBlocksMultiEntrySubmission() {
        open(false)
        compose.onNodeWithText("Bu BC ortamındaki paket çoklu stok girişini desteklemiyor.", substring = true).assertExists()
        compose.onNodeWithText("Tekli LP'yi Oluştur").performScrollTo().assertIsNotEnabled()
    }
}
