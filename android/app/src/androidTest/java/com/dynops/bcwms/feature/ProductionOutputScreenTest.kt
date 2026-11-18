package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.Screen
import com.dynops.bcwms.operatorHomeScreens
import com.dynops.bcwms.ui.BcwmsTheme
import org.json.JSONObject
import org.junit.After
import org.junit.Before
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Device UI checks with isolated saved receipts; never sends output or print requests. */
class ProductionOutputScreenTest {
    @get:Rule val compose = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val prefs get() = context.getSharedPreferences("production_output_pending_v1", Context.MODE_PRIVATE)
    private val order = "UI-VERIFY-OUTPUT"
    private val id = "b68bf0d2-2a97-44db-b29d-8791fcaa7381"
    private val key get() = listOf(BcApi.getTenant(context).lowercase(), BcApi.getEnvironment(context).lowercase(),
        BcApi.getCompanyId(context).lowercase(), order, "10000").joinToString("|")
    private fun line() = JSONObject().put("prodOrderNo", order).put("lineNo", 10000).put("itemNo", "UI-FG")
        .put("status", "Released").put("remainingQuantity", 5000).put("unitOfMeasureCode", "ADET")
        .put("lotRequired", true).put("serialRequired", false).put("expirationRequired", false)
        .put("workDate", "2026-11-18").put("binCode", "ÜR.0002")

    @Before fun reset() { assertTrue(prefs.edit().remove(key).commit()) }
    @After fun cleanup() { prefs.edit().remove(key).commit() }

    private fun saved(completed: Boolean) {
        val body = JSONObject().put("requestId", id).put("quantity", 2000).put("postingDate", "2026-11-18")
            .put("expirationDate", "0001-01-01").put("binCode", "ÜR.0002").toString()
        val result = JSONObject().put("requestId", id).put("prodOrderNo", order).put("lineNo", 10000)
            .put("itemNo", "UI-FG").put("quantity", 2000).put("lotNo", "BC-LOT-VERIFY")
            .put("postingDate", "2026-11-18").put("completed", completed).put("cancelled", false)
            .put("entryNo", if (completed) 42 else 0).put("quantityBase", if (completed) 2000 else 0)
            .put("baseUnitOfMeasure", "ADET").put("documentNo", "VERIFY-DOC").toString()
        val draft = ProductionOutputDraft(id, order, 10000, "UI-FG", body, if (completed) "posted" else "prepared", result)
        assertTrue(prefs.edit().putString(key, draft.toJson()).commit())
    }

    @Test fun emuMenuAndInitialReportShowLotActionAndRejectEmptyQuantity() {
        assertTrue(Screen.ProductionOutput in operatorHomeScreens("emu"))
        assertFalse(Screen.ProductionOutput in operatorHomeScreens("bade"))
        compose.setContent { BcwmsTheme { ProductionPostingSheet(line(), {}, {}, {}) } }
        compose.onNodeWithText("Üretim Çıktısı Bildir").assertIsDisplayed()
        compose.onNodeWithText("ÜR.0002").assertExists()
        compose.onNodeWithText("Lot Ata — BC'den Otomatik").performScrollTo().performClick()
        compose.onNodeWithText("HATA: Bildirilen miktar sıfırdan büyük olmalı.").assertExists()
        assertNull(prefs.getString(key, null))
    }

    @Test fun preparedLotRestoresAndPostingRequiresExplicitConfirmation() {
        saved(false)
        compose.setContent { BcwmsTheme { ProductionPostingSheet(line(), {}, {}, {}) } }
        compose.onNodeWithText("Lot: BC-LOT-VERIFY").assertExists()
        compose.onNodeWithText("Bu Çıktının Etiketini Bas").assertDoesNotExist()
        compose.onNodeWithText("Deftere Naklet").performScrollTo().performClick()
        compose.onNodeWithText("Üretim çıktısı deftere nakledilsin mi?").assertIsDisplayed()
        compose.onNodeWithText("Vazgeç").performClick()
        assertEquals("prepared", productionOutputDraftFromJson(prefs.getString(key, "")!!)!!.phase)
    }

    @Test fun postedReceiptPrintsItsOwnLotAndQuantityWithoutReposting() {
        saved(true)
        var printed: OutputLot? = null
        var postedCalls = 0
        compose.setContent { BcwmsTheme { ProductionPostingSheet(line(), {}, { postedCalls++ }, { printed = it }) } }
        compose.onNodeWithText("Madde hareketi: 42 · Belge: VERIFY-DOC").assertExists()
        compose.onNodeWithText("Deftere Naklet").assertDoesNotExist()
        compose.onNodeWithText("Bu Çıktının Etiketini Bas").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals("BC-LOT-VERIFY", printed!!.lotNo)
            assertEquals(2000.0, printed!!.quantity, 0.0)
            assertEquals("ADET", printed!!.unit)
            assertEquals(0, postedCalls)
        }
    }
}
