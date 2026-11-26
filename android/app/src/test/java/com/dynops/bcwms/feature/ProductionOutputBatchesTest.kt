package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class ProductionOutputBatchesTest {
    private fun e(no: Int, qty: Double, lot: String = "L1", date: String = "2026-11-26") =
        JSONObject().put("entryNo", no).put("quantity", qty).put("lotNo", lot).put("postingDate", date).put("baseUnitOfMeasure", "ADET")

    @Test fun `each output is its own row with its own quantity, newest first`() {
        val rows = productionOutputBatches(listOf(e(10, 100.0), e(11, 100.0), e(12, 100.0)))
        assertEquals(listOf(12, 11, 10), rows.map { it.entryNo })
        assertEquals(listOf(100.0, 100.0, 100.0), rows.map { it.quantity })
        assertEquals("ADET", rows[0].unit)
    }
    @Test fun `a reversed output is taken from the latest output of the same lot`() {
        val rows = productionOutputBatches(listOf(e(10, 100.0), e(11, 100.0, "L2"), e(12, 100.0), e(13, -150.0)))
        assertEquals(listOf(11 to 100.0, 10 to 50.0), rows.map { it.entryNo to it.quantity })
    }
}
