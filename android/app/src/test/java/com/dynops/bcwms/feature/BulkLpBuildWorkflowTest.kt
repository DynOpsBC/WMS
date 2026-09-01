package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONObject

class BulkLpBuildWorkflowTest {
    @Test
    fun `common quantity is assigned to every LP and rows stay independent`() {
        val rows = commonLpQuantityDrafts(10, "100")

        assertEquals(10, rows.size)
        assertTrue(rows.all { it.quantity == "100" })
        val edited = rows.map { if (it.id == 10) it.copy(quantity = "80") else it }
        assertEquals("100", edited.first().quantity)
        assertEquals("80", edited.last().quantity)
    }

    @Test
    fun `bulk LP count is capped at two hundred`() {
        assertTrue(commonLpQuantityDrafts(0, "1").isEmpty())
        assertTrue(commonLpQuantityDrafts(201, "1").isEmpty())
        assertEquals(200, commonLpQuantityDrafts(200, "1").size)
    }

    @Test
    fun `bulk LP creation does not require a bin`() {
        val rows = commonLpQuantityDrafts(3, "0")
        val payload = JSONObject(bulkLpBuildPayload("MERKEZDEPO", "", rows))

        assertTrue(rows.isNotEmpty())
        assertFalse(rows.any { it.quantity.toDouble() < 0.0 })
        assertEquals("MERKEZDEPO", payload.getString("locationCode"))
        assertEquals("", payload.getString("binCode"))
    }
}
