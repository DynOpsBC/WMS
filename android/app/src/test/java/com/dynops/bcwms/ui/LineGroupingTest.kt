package com.dynops.bcwms.ui

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LineGroupingTest {
    private fun line(item: String, lot: String = "", serial: String = "") = JSONObject().apply {
        put("itemNo", item)
        put("binCode", "A-01")
        put("lotNo", lot)
        put("serialNo", serial)
    }

    private fun groups(vararg lines: JSONObject) = groupLines(lines.toList()) { 1.0 }

    @Test
    fun `scanned lot selects its exact group instead of first item group`() {
        val result = selectScannedLineGroup(groups(line("ITEM-1", "LOT-A"), line("ITEM-1", "LOT-B")), "ITEM-1", lotNo = "lot-b")

        assertEquals("LOT-B", result.group?.lines?.single()?.optString("lotNo"))
        assertNull(result.issue)
    }

    @Test
    fun `unknown tracking value fails closed`() {
        val result = selectScannedLineGroup(groups(line("ITEM-1", "LOT-A")), "ITEM-1", lotNo = "LOT-X")

        assertNull(result.group)
        assertEquals(ScannedGroupIssue.TrackingMismatch, result.issue)
    }

    @Test
    fun `untracked scan is rejected when item has multiple tracked groups`() {
        val result = selectScannedLineGroup(groups(line("ITEM-1", "LOT-A"), line("ITEM-1", "LOT-B")), "ITEM-1")

        assertNull(result.group)
        assertEquals(ScannedGroupIssue.Ambiguous, result.issue)
    }

    @Test
    fun `serial disambiguates groups sharing a lot`() {
        val result = selectScannedLineGroup(
            groups(line("ITEM-1", "LOT-A", "SER-1"), line("ITEM-1", "LOT-A", "SER-2")),
            "ITEM-1",
            lotNo = "LOT-A",
            serialNo = "SER-2",
        )

        assertEquals("SER-2", result.group?.lines?.single()?.optString("serialNo"))
        assertNull(result.issue)
    }

    @Test
    fun `zero pick clears every line in the selected lot group`() {
        val first = line("ITEM-1", "LOT-A").put("lineNo", 10)
        val second = line("ITEM-1", "LOT-A").put("lineNo", 20)
        val group = groupLines(listOf(first, second)) { 5.0 }.single()

        val plan = distributeQty(group, 0.0) { 5.0 }

        assertEquals(listOf(10, 20), plan.map { it.first.getInt("lineNo") })
        assertTrue(plan.all { it.second == 0.0 })
    }
}
