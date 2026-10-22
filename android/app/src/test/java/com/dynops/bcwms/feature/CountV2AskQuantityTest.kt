package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CountV2AskQuantityTest {
    private fun line(no: Int, bin: String, item: String, lp: String = "", lot: String = "") =
        JSONObject().put("lineNo", no).put("binCode", bin).put("itemNo", item).put("lpNo", lp).put("lotNo", lot)

    private val lines = listOf(
        line(10, "A-01", "1000", lp = "LP001"),
        line(20, "A-01", "1001", lp = "LP001"),
        line(30, "A-01", "1000"),
        line(40, "A-02", "1000"),
        line(50, "A-01", "1002", lot = "L7"),
    )

    @Test
    fun `asks only on Kitoko`() {
        assertTrue(countV2AsksQuantity("kitoko"))
        assertFalse(countV2AsksQuantity("bade"))
        assertFalse(countV2AsksQuantity("emu"))
    }

    @Test
    fun `lp scan asks every line of that lp in the bin, in order`() {
        val r = countV2LinesToAsk(lines, CountV2AskTarget("A-01", lpNo = "LP001"), emptySet())
        assertEquals(listOf(10, 20), r.map { it.optInt("lineNo") })
        val next = countV2LinesToAsk(lines, CountV2AskTarget("A-01", lpNo = "LP001"), setOf(10))
        assertEquals(listOf(20), next.map { it.optInt("lineNo") })
    }

    @Test
    fun `item scan asks loose lines of the scanned bin only`() {
        val r = countV2LinesToAsk(lines, CountV2AskTarget("A-01", itemNo = "1000"), emptySet())
        assertEquals(listOf(30), r.map { it.optInt("lineNo") })
    }

    @Test
    fun `plain lot label resolves by lot number`() {
        assertEquals(listOf(50), countV2LinesToAsk(lines, CountV2AskTarget("A-01", itemNo = "L7"), emptySet()).map { it.optInt("lineNo") })
        assertEquals(listOf(50), countV2LinesToAsk(lines, CountV2AskTarget("A-01", lotNo = "L7"), emptySet()).map { it.optInt("lineNo") })
    }
}

class CountV2ZoneStartTest {
    private fun sheet(no: String, loc: String, zone: String, status: String = "Open") =
        JSONObject().put("no", no).put("locationCode", loc).put("zoneFilter", zone).put("status", status)

    @Test fun `opens the open sheet of the scanned zone`() {
        val r = countV2ZoneStart("PICK", listOf("MERKEZ"), "", listOf(sheet("C1", "MERKEZ", "PICK", "Posted"), sheet("C2", "MERKEZ", "PICK")), true)
        assertEquals(CountV2ZoneStart.Open("C2"), r)
    }

    @Test fun `creates when no open sheet for that zone`() {
        val r = countV2ZoneStart("PICK", listOf("MERKEZ"), "", listOf(sheet("C1", "MERKEZ", "PICK", "Posted"), sheet("C3", "MERKEZ", "BULK")), true)
        assertEquals(CountV2ZoneStart.Create("MERKEZ"), r)
    }

    @Test fun `zone in several locations uses current location or asks`() {
        assertEquals(CountV2ZoneStart.Create("B"), countV2ZoneStart("PICK", listOf("A", "B"), "B", emptyList(), true))
        assertEquals(CountV2ZoneStart.ChooseLocation(listOf("A", "B")), countV2ZoneStart("PICK", listOf("A", "B"), "", emptyList(), true))
    }

    @Test fun `unknown zone or failed read is an error`() {
        assertTrue(countV2ZoneStart("X", emptyList(), "", emptyList(), true) is CountV2ZoneStart.Error)
        assertTrue(countV2ZoneStart("X", listOf("A"), "", emptyList(), false) is CountV2ZoneStart.Error)
    }
}
