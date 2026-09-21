package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class InquiryWorkflowTest {
    private fun entry(no: String, copies: String = "1") = InquiryItemEntry(
        queryKey = no,
        item = JSONObject().put("no", no),
        lpLines = emptyList(),
        ledger = emptyList(),
        queriedLpNo = "",
        uom = "ADET",
        labelCopies = copies,
    )

    @Test fun `adding another product does not inherit its label quantity`() {
        val rows = addInquiryEntry(listOf(entry("A", "12")), entry("B"))
        assertEquals(listOf("B", "A"), rows.map { it.queryKey })
        assertEquals(listOf("1", "12"), rows.map { it.labelCopies })
    }

    @Test fun `requery refreshes one product and preserves its label quantity`() {
        val rows = addInquiryEntry(listOf(entry("B", "3"), entry("A", "12")), entry("a"))
        assertEquals(listOf("a", "B"), rows.map { it.queryKey })
        assertEquals(listOf("12", "3"), rows.map { it.labelCopies })
    }

    @Test fun `missing product does not replace existing results`() {
        val rows = listOf(entry("A", "12"))
        assertEquals(rows, addInquiryEntry(rows, entry("MISSING").copy(item = null)))
    }

    @Test fun `removing and rescanning starts a fresh label quantity`() {
        val rows = listOf(entry("A", "12"), entry("B", "3"))
        val remaining = rows.filterNot { it.queryKey == "A" }
        val rescanned = addInquiryEntry(remaining, entry("A"))
        assertEquals(listOf("1", "3"), rescanned.map { it.labelCopies })
    }

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
    fun `queried LP summary is absent for an item query`() {
        val lines = listOf(JSONObject().put("lpNo", "LP1").put("quantity", 10))

        assertNull(queriedLpSummary("ITEM-1", lines))
    }
}
