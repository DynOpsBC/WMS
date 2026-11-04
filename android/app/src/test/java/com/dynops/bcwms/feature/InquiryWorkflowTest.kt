package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class InquiryWorkflowTest {
    @Test
    fun `queried LP summary combines quantity and distinct lots`() {
        val lines = listOf(
            JSONObject().put("lpNo", "LP000018").put("quantity", 5000).put("lotNo", "A101296"),
            JSONObject().put("lpNo", "lp000018").put("quantity", 880).put("lotNo", "A101296"),
            JSONObject().put("lpNo", "LP000019").put("quantity", 25).put("lotNo", "OTHER"),
        )

        val result = queriedLpSummary(" lp000018 ", lines)

        assertEquals("LP000018", result?.lpNo)
        assertEquals(5880.0, result?.quantity ?: 0.0, 0.0)
        assertEquals(listOf("A101296"), result?.lotNos)
    }

    @Test
    fun `queried LP summary keeps multiple lots`() {
        val lines = listOf(
            JSONObject().put("lpNo", "LP1").put("quantity", 10).put("lotNo", "LOT-A"),
            JSONObject().put("lpNo", "LP1").put("quantity", 20).put("lotNo", "LOT-B"),
        )

        assertEquals(listOf("LOT-A", "LOT-B"), queriedLpSummary("LP1", lines)?.lotNos)
    }

    @Test
    fun `LP content lists every item with its own lot and quantity`() {
        // BADE LP002347: üç farklı madde; eskiden yalnız AB.00126 ve LP toplamı (15060) görünüyordu.
        val lines = listOf(
            JSONObject().put("lpNo", "LP002347").put("lineNo", 30000).put("itemNo", "AB.01378").put("quantity", 5010).put("lotNo", "A102588").put("unitOfMeasure", "ADET"),
            JSONObject().put("lpNo", "LP002347").put("lineNo", 10000).put("itemNo", "AB.00126").put("quantity", 5040).put("lotNo", "A102586").put("unitOfMeasure", "ADET"),
            JSONObject().put("lpNo", "LP002347").put("lineNo", 20000).put("itemNo", "AB.00145").put("quantity", 5010).put("lotNo", "A102587").put("unitOfMeasure", "ADET"),
        )
        val cards = mapOf("AB.00126" to JSONObject().put("no", "AB.00126").put("description", "STICK GÖVDE"))

        val rows = lpContentRows(lines, cards)

        assertEquals(listOf("AB.00126", "AB.00145", "AB.01378"), rows.map { it.itemNo })
        assertEquals(listOf("A102586", "A102587", "A102588"), rows.map { it.lotNo })
        assertEquals(listOf(5040.0, 5010.0, 5010.0), rows.map { it.quantity })
        assertEquals("STICK GÖVDE", rows.first().description)
        assertEquals("", rows[1].description)
        assertEquals(15060.0, rows.sumOf { it.quantity }, 0.0)
        assertEquals("ADET", lpContentUnit(rows))
    }

    @Test
    fun `LP content unit falls back to item base unit and is blank when units differ`() {
        val lines = listOf(
            JSONObject().put("lpNo", "LP1").put("itemNo", "A").put("quantity", 2),
            JSONObject().put("lpNo", "LP1").put("itemNo", "B").put("quantity", 3).put("unitOfMeasure", "KG"),
        )
        val cards = mapOf("A" to JSONObject().put("no", "A").put("baseUnitOfMeasure", "ADET"))

        val rows = lpContentRows(lines, cards)

        assertEquals(listOf("ADET", "KG"), rows.map { it.uom })
        assertEquals("", lpContentUnit(rows))
    }

    @Test
    fun `queried LP summary is absent for an item query`() {
        val lines = listOf(JSONObject().put("lpNo", "LP1").put("quantity", 10))

        assertNull(queriedLpSummary("ITEM-1", lines))
    }

    @Test
    fun `LP placement label shows location, bin and zone when known`() {
        assertEquals("", lpPlacementLabel(null))
        assertEquals("Raf: MERKEZDEPO/M.A01.11 · Alan: A01", lpPlacementLabel(LpPlacement("MERKEZDEPO", "M.A01.11", "A01")))
        assertEquals("Raf: MERKEZDEPO/M.A01.11", lpPlacementLabel(LpPlacement("MERKEZDEPO", "M.A01.11", "")))
        assertEquals("Raf: MERKEZDEPO", lpPlacementLabel(LpPlacement("MERKEZDEPO", "", "")))
    }

    @Test
    fun `OData or-filter escapes quotes in LP numbers`() {
        assertEquals("no eq 'LP1' or no eq 'O''NEIL'", odataOrFilter(listOf("LP1", "O'NEIL")) { "no eq '$it'" })
    }
}
