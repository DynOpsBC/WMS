package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CountRoundComparisonTest {
    private fun line(bin: String, system: Double, count: Double?, lp: String = "LP1", uom: String = "AD") = JSONObject()
        .put("itemNo", "ITEM1").put("lpNo", lp).put("lpLineNo", 10000).put("unitOfMeasureCode", uom)
        .put("binCode", bin).put("systemQty", system).put("counted1", count != null).put("countedQty1", count ?: 0.0)

    @Test fun `moved LP keeps both bin histories and uses fresh stock for current variance`() {
        val old = line("B", 0.0, 10.0).put("foundFromBin", "A").put("foundLpQty", 10.0)
        val current = line("B", 10.0, 8.0)
        val row = compareCountRounds(listOf(old), listOf(current), 1).single()
        assertEquals("A", row.previous!!.systemBins)
        assertEquals("B", row.previous.countedBins)
        assertEquals("B", row.previous.scopeBins)
        assertEquals(10.0, row.previous.recordedLpQty!!, 0.0)
        assertEquals(10.0, row.previous.variance!!, 0.0)
        assertEquals(-2.0, row.current!!.variance!!, 0.0)
        assertEquals(-2.0, row.change!!, 0.0)
    }

    @Test fun `source zero and found count do not double count LP snapshot`() {
        val rows = compareCountRounds(listOf(line("A", 10.0, 0.0), line("B", 0.0, 10.0).put("foundFromBin", "A")), listOf(line("B", 10.0, 10.0)), 1)
        assertEquals(1, rows.size)
        assertEquals(10.0, rows.single().previous!!.systemQty, 0.0)
        assertEquals(10.0, rows.single().previous!!.countedQty!!, 0.0)
    }

    @Test fun `missing row is not a counted zero and unfinished count has no variance`() {
        val rows = compareCountRounds(listOf(line("A", 10.0, 10.0)), listOf(line("B", 5.0, null, "LP2")), 1)
        assertEquals(2, rows.size)
        assertNull(rows.first().current)
        assertNull(rows.last().previous)
        assertNull(rows.last().current!!.variance)
        assertNull(rows.last().change)
    }

    @Test fun `loose stock stays separate by bin and unit`() {
        val old = listOf(line("A", 1.0, 1.0, ""), line("B", 1.0, 1.0, ""), line("A", 2.0, 2.0, "", "KG"))
        assertEquals(3, compareCountRounds(old, old, 1).size)
    }
}
