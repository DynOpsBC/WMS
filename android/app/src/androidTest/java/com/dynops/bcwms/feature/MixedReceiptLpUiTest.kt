package com.dynops.bcwms.feature

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** BADE canlı senaryosu (14 Eki 2026): AB.02316 + AB.02317, 20020'şer adet, aynı 4 palette. */
class MixedReceiptLpUiTest {
    @get:Rule val compose = createComposeRule()

    private fun line(lineNo: Int, item: String) = JSONObject()
        .put("lineNo", lineNo).put("itemNo", item).put("description", "$item kutu")
        .put("unitOfMeasureCode", "ADET").put("quantity", 20020).put("qtyReceived", 0)
        .put("lotRequired", true).put("bulkLpCount", 0)

    @Test fun operatorSplitsTwoProductsOverFourPalletsWithOwnLots() {
        var submittedJson = ""
        var submittedLines: List<Int> = emptyList()
        var submittedPallets = 0
        compose.setContent { MaterialTheme {
            MixedReceiptLpSheet(listOf(line(10000, "AB.02316"), line(20000, "AB.02317")), onDismiss = {}) { json, lineNos, count ->
                submittedJson = json; submittedLines = lineNos; submittedPallets = count
            }
        } }
        compose.onNodeWithTag("mixed-lot-10000").performScrollTo().performTextInput("A102600")
        compose.onNodeWithTag("mixed-lot-20000").performScrollTo().performTextInput("A102601")
        compose.onNodeWithTag("mixed-pallet-count").performScrollTo().performTextInput("4")
        compose.onNodeWithTag("mixed-split").performScrollTo().performClick()
        compose.onNodeWithText("AB.02316: paletlerde 20020 / 20020 ADET").assertExists()
        compose.onNodeWithTag("mixed-submit").performScrollTo().assertIsEnabled().performClick()
        compose.runOnIdle {
            assertEquals(listOf(10000, 20000), submittedLines)
            assertEquals(4, submittedPallets)
            val root = JSONObject(submittedJson)
            assertEquals("A102600", root.getJSONArray("lines").getJSONObject(0).getString("lotNo"))
            assertEquals("A102601", root.getJSONArray("lines").getJSONObject(1).getString("lotNo"))
            val pallets = root.getJSONArray("pallets")
            assertEquals(4, pallets.length())
            for (i in 0 until 4) {
                val items = pallets.getJSONObject(i).getJSONArray("items")
                assertEquals(2, items.length())
                assertEquals(5005.0, items.getJSONObject(0).getDouble("quantity"), 0.0)
                assertEquals(5005.0, items.getJSONObject(1).getDouble("quantity"), 0.0)
            }
        }
    }

    @Test fun editedPalletQuantityMustStillMatchTheProductTotal() {
        compose.setContent { MaterialTheme {
            MixedReceiptLpSheet(listOf(line(10000, "AB.02316"), line(20000, "AB.02317")), onDismiss = {}) { _, _, _ -> }
        } }
        compose.onNodeWithTag("mixed-pallet-count").performScrollTo().performTextInput("4")
        compose.onNodeWithTag("mixed-split").performScrollTo().performClick()
        compose.onNodeWithTag("mixed-qty-0-10000").performScrollTo().performTextReplacement("5000")
        compose.onNodeWithText("AB.02316: paletlerde 20015 / 20020 ADET").assertExists()
        compose.onNodeWithTag("mixed-submit").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("mixed-qty-1-10000").performScrollTo().performTextReplacement("5010")
        compose.onNodeWithTag("mixed-submit").performScrollTo().assertIsEnabled()
    }

    @Test fun preparedMixedPlanShowsPalletMatesAndCanBeCancelled() {
        var cancelled = false
        val rows = listOf(
            JSONObject().put("lpNo", "LP000901").put("quantity", 5005).put("lotNo", "A102600")
                .put("mixed", true).put("palletNo", 1).put("otherItems", "AB.02317"),
            JSONObject().put("lpNo", "LP000902").put("quantity", 5005).put("lotNo", "A102600")
                .put("mixed", true).put("palletNo", 2).put("otherItems", "AB.02317"),
        )
        compose.setContent { MaterialTheme {
            ReceiptLpPlanSheet("AB.02316", "ADET", rows, onDismiss = {}, onCancelDistribution = { cancelled = true })
        } }
        compose.onNodeWithText("Karma palet 1 · birlikte: AB.02317").assertExists()
        compose.onNodeWithTag("receipt-plan-cancel").performScrollTo().performClick()
        compose.onNodeWithText("Geri Al").performClick()
        compose.runOnIdle { assertEquals(true, cancelled) }
    }

    @Test fun pickerNeedsAtLeastTwoProducts() {
        var picked: List<Int> = emptyList()
        compose.setContent { MaterialTheme {
            MixedReceiptLinePicker(listOf(line(10000, "AB.02316"), line(20000, "AB.02317"), line(30000, "AB.02092")), onDismiss = {}) {
                picked = it.map { l -> l.optInt("lineNo") }
            }
        } }
        compose.onNodeWithTag("mixed-pick-10000").performClick()
        compose.onNodeWithText("Devam (1)").assertIsNotEnabled()
        compose.onNodeWithTag("mixed-pick-20000").performClick()
        compose.onNodeWithText("Devam (2)").assertIsEnabled().performClick()
        compose.runOnIdle { assertEquals(listOf(10000, 20000), picked) }
    }
}
