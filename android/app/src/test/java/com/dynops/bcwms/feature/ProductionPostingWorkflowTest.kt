package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ProductionPostingWorkflowTest {
    private val id = "c5704be7-937d-4b3f-bc85-eaab1f2f00d1"
    private fun draft(phase: String = "prepare", result: String = "") = ProductionOutputDraft(id, "UR'001", 20000, "FG",
        JSONObject().put("requestId", id).put("quantity", 2000.0).put("postingDate", "2026-11-18")
            .put("expirationDate", "0001-01-01").put("binCode", "OUT").toString(), phase, result)
    private fun response(completed: Boolean = false): JSONObject = JSONObject()
        .put("requestId", "{$id}").put("prodOrderNo", "UR'001").put("lineNo", 20000).put("itemNo", "FG")
        .put("quantity", 2000.0).put("completed", completed).put("cancelled", false).put("lotNo", "BC-LOT-001")
        .put("postingDate", "2026-11-18").put("documentNo", "DOC-001").put("entryNo", if (completed) 42 else 0)
        .put("quantityBase", if (completed) 4000.0 else 0.0).put("baseUnitOfMeasure", "ADET")

    @Test fun partialOutputAllows2000Then3000From5000AndRejectsOverproduction() {
        assertNull(productionReportQuantityError(2000.0, 5000.0))
        assertNull(productionReportQuantityError(3000.0, 3000.0))
        assertNotNull(productionReportQuantityError(3001.0, 3000.0))
        assertNotNull(productionReportQuantityError(1.0, 0.0))
        listOf(null, 0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY).forEach {
            assertNotNull(productionReportQuantityError(it, 5000.0))
        }
    }

    @Test fun restartKeepsTheExactRequestIdAndPayloadAtEveryUncertainStage() {
        for (phase in listOf("prepare", "posting", "cancel", "cancel_prepare")) {
            val initial = draft(phase)
            val restored = productionOutputDraftFromJson(initial.toJson())!!
            assertEquals(initial, restored)
            assertEquals(productionRequestPath(initial, "postOutput"), productionRequestPath(restored, "postOutput"))
        }
        assertTrue(productionPreparePath(draft()).contains("prodOrderNo='UR''001',lineNo=20000"))
        assertTrue(productionRequestPath(draft(), "postOutput").contains("productionOutputRequests($id)"))
    }

    @Test fun preparedLotIsRestoredWithoutAllocatingAnotherLot() {
        val prepared = draft("prepared", response().toString())
        assertEquals(prepared, productionOutputDraftFromJson(prepared.toJson()))
        assertEquals("BC-LOT-001", validatedProductionOutputResult(prepared, prepared.result)!!.getString("lotNo"))
    }

    @Test fun onlyValidatedLedgerSuccessCanUnlockPrinting() {
        val posted = draft("posted", response(true).toString())
        assertEquals(posted, productionOutputDraftFromJson(posted.toJson()))
        assertEquals(4000.0, validatedProductionOutputResult(posted, posted.result)!!.getDouble("quantityBase"), 0.0)
        assertNull(productionOutputDraftFromJson(draft("posted", response(false).toString()).toJson()))
        assertNull(validatedProductionOutputResult(posted, response(true).put("entryNo", 0).toString()))
        assertNull(validatedProductionOutputResult(posted, response(true).put("baseUnitOfMeasure", "").toString()))
        assertNull(validatedProductionOutputResult(posted, response(true).put("cancelled", true).toString()))
    }

    @Test fun mismatchedOrCorruptRecoveryCannotStartANewOutput() {
        assertNull(productionOutputDraftFromJson("broken"))
        assertNull(productionOutputDraftFromJson(JSONObject(draft().toJson()).put("phase", "anything").toString()))
        assertNull(validatedProductionOutputResult(draft(), response().put("lineNo", 10000).toString()))
        assertNull(validatedProductionOutputResult(draft(), response().put("quantity", 1999).toString()))
        assertNull(validatedProductionOutputResult(draft(), response().put("itemNo", "OTHER").toString()))
        assertNull(validatedProductionOutputResult(draft(), response().put("requestId", "00000000-0000-0000-0000-000000000000").toString()))
    }

    @Test fun restoredRequestMustBelongToTheSelectedOrderLineAndItem() {
        val line = JSONObject().put("prodOrderNo", "UR'001").put("lineNo", 20000).put("itemNo", "FG")
        assertTrue(productionDraftMatchesLine(draft(), line))
        assertFalse(productionDraftMatchesLine(draft(), line.put("lineNo", 10000)))
        assertFalse(productionDraftMatchesLine(draft(), line.put("lineNo", 20000).put("itemNo", "OTHER")))
        assertFalse(productionDraftMatchesLine(draft(), line.put("itemNo", "FG").put("prodOrderNo", "OTHER")))
    }

    @Test fun datesMustBeRealCalendarDates() {
        assertNull(productionIsoDate("2026-02-30"))
        assertNull(productionIsoDate("18.11.2026"))
        assertNull(productionIsoDate(""))
        assertEquals("0001-01-01", productionIsoDate("", optional = true))
        assertEquals("2026-11-18", productionIsoDate("2026-11-18"))
    }

    @Test fun pickSourcesDistinguishSalesAndReleasedProductionEvenWithTheSameNumber() {
        val sales = JSONObject().put("sourceNo", "001").put("sourceType", 37).put("sourceSubtype", 1)
        val production = JSONObject().put("sourceNo", "001").put("sourceType", 5407).put("sourceSubtype", 3)
        assertEquals("Satış siparişi: 001", pickSourceCaption(sales))
        assertEquals("Serbest bırakılmış üretim emri: 001", pickSourceCaption(production))
        val summary = listOf(sales, production).map(::pickSourceCaption).distinct().joinToString(" · ")
        assertEquals(summary, pickSourceSummary(JSONObject().put("sourceSummary", summary)))
        assertEquals("Kaynak belge: 001", pickSourceCaption(sales.put("sourceSubtype", 5)))
        assertEquals("", pickSourceCaption(JSONObject()))
    }

    @Test
    fun listCardShowsOnlySourceNumbers() {
        assertEquals("UR000382", pickSourceNumbers(JSONObject().put("sourceSummary", "Serbest bırakılmış üretim emri: UR000382").put("sourceNo", "UR000382")))
        assertEquals(
            "UR000382 · SS000044",
            pickSourceNumbers(JSONObject().put("sourceSummary", "Serbest bırakılmış üretim emri: UR000382 · Satış siparişi: SS000044")),
        )
        // Older BC without sourceSummary: fall back to the header source number.
        assertEquals("UR000335", pickSourceNumbers(JSONObject().put("sourceNo", "UR000335")))
        assertEquals("", pickSourceNumbers(JSONObject()))
    }

    @Test
    fun listCardItemsComeFromTakeLinesOncePerItem() {
        fun line(no: String, action: String, item: String, description: String) = JSONObject()
            .put("no", no).put("actionType", action).put("itemNo", item).put("description", description)
        val items = pickItemsByDocument(
            listOf(
                line("PI000435", "Take", "KLC-4", "HAMMADDE KÜLÇE KURŞUN"),
                line("PI000435", "Place", "KLC-4", "HAMMADDE KÜLÇE KURŞUN"),
                line("PI000435", "Take", "KLC-4", "HAMMADDE KÜLÇE KURŞUN"),
                line("PI000435", "Take", "JMB-3", "JMB-3"),
                line("PI000436", "Take", "6.50 MM TEL", ""),
            ),
        )
        assertEquals(listOf("KLC-4 — HAMMADDE KÜLÇE KURŞUN", "JMB-3"), items["PI000435"])
        assertEquals(listOf("6.50 MM TEL"), items["PI000436"])
        assertTrue(pickItemsByDocument(emptyList()).isEmpty())
    }
}
