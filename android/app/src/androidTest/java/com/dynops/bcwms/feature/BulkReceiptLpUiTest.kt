package com.dynops.bcwms.feature

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class BulkReceiptLpUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun operatorPrepares400And600WithSeparateLotsInOneSubmission() {
        var submitted: List<BulkReceiptLpRow> = emptyList()
        var submittedQuantity = 0.0
        compose.setContent { MaterialTheme {
            BulkReceiptLpSheet("AB.00005", "ADET", 1000.0, "A102370", "", "",
                lotRequired = true, allowLotGroups = true, expiryEnabled = false, expiryRequired = false,
                onDismiss = {}, onSubmit = { qty, rows -> submittedQuantity = qty; submitted = rows })
        } }
        compose.onNodeWithTag("receipt-supplier-RECEIPT").performScrollTo().performTextInput("SUP-400")
        compose.onNodeWithTag("receipt-lp-1-quantity").performScrollTo().performTextInput("400")
        compose.onNodeWithText("+ Lot Grubu Ekle").performScrollTo().performClick()
        compose.onNodeWithTag("receipt-lot-LOT-2").performScrollTo().performTextInput("A102371")
        compose.onNodeWithTag("receipt-supplier-LOT-2").performScrollTo().performTextInput("SUP-600")
        compose.onNodeWithText("+ LP Ekle").performScrollTo().performClick()
        compose.onNodeWithTag("receipt-lp-2-quantity").performScrollTo().performTextInput("600")
        compose.onNodeWithText("2 LP Taslağı Hazırla").performScrollTo().assertIsEnabled().performClick()
        compose.runOnIdle {
            assertEquals(1000.0, submittedQuantity, 0.0)
            assertEquals(listOf(400.0, 600.0), submitted.map { it.quantity })
            assertEquals(listOf("A102370", "A102371"), submitted.map { it.lotNo })
            assertEquals(listOf("SUP-400", "SUP-600"), submitted.map { it.supplierLotNo })
        }
    }

    @Test fun reloadedPlanShowsEveryLotAndPalletQuantity() {
        val rows = listOf(
            JSONObject().put("lpNo", "LP-1").put("quantity", 400).put("lotNo", "A102370").put("supplierLotNo", "SUP-400"),
            JSONObject().put("lpNo", "LP-2").put("quantity", 600).put("lotNo", "A102371").put("supplierLotNo", "SUP-600"),
        )
        compose.setContent { MaterialTheme { ReceiptLpPlanSheet("AB.00005", "ADET", rows) {} } }
        compose.onNodeWithText("LP-1 · 400 ADET").assertExists()
        compose.onNodeWithText("İç lot: A102370").assertExists()
        compose.onNodeWithText("LP-2 · 600 ADET").assertExists()
        compose.onNodeWithText("İç lot: A102371").assertExists()
    }

    @Test fun olderServerKeepsCommonLotFlowAvailable() {
        compose.setContent { MaterialTheme {
            BulkReceiptLpSheet("AB.00005", "ADET", 1000.0, "A102370", "", "",
                lotRequired = true, allowLotGroups = false, expiryEnabled = false, expiryRequired = false,
                onDismiss = {}, onSubmit = { _, _ -> })
        } }
        compose.onNodeWithText("+ Lot Grubu Ekle").assertDoesNotExist()
        compose.onNodeWithText("Eşit Böl ve 1 LP Hazırla").performScrollTo().performClick()
        compose.onNodeWithText("1 LP Taslağı Hazırla").performScrollTo().assertIsEnabled()
    }
}
