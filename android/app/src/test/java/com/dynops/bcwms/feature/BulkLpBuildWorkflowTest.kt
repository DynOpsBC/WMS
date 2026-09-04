package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONObject

class BulkLpBuildWorkflowTest {
    @Test
    fun `one ledger row can be allocated to ten LP records`() {
        assertTrue(validLedgerBulkLpPlan(10, 100.0, 1000.0, ""))
        assertFalse(validLedgerBulkLpPlan(11, 100.0, 1000.0, ""))
        assertFalse(validLedgerBulkLpPlan(0, 100.0, 1000.0, ""))
    }

    @Test
    fun `serial tracked ledger row cannot be split`() {
        assertTrue(validLedgerBulkLpPlan(1, 1.0, 1.0, "SER-1"))
        assertFalse(validLedgerBulkLpPlan(2, 1.0, 2.0, "SER-1"))
    }

    @Test
    fun `ledger bulk payload requests one separate label per LP`() {
        val payload = JSONObject(ledgerBulkLpPayload("PALET", "A-01", 10, 100.0, "ZPL01", true))

        assertEquals("PALET", payload.getString("templateCode"))
        assertEquals(10, payload.getInt("lpCount"))
        assertEquals(100.0, payload.getDouble("quantityPerLp"), 0.0)
        assertTrue(payload.getBoolean("printLabels"))
    }

    @Test
    fun `location choices are normalized deduplicated and sorted`() {
        val options = bulkLpLocationOptions(
            listOf(
                JSONObject().put("code", " ZONE-B ").put("displayName", "İkinci Depo"),
                JSONObject().put("code", "").put("displayName", "Geçersiz"),
                JSONObject().put("code", "merkezdepo").put("displayName", "Merkez Depo"),
                JSONObject().put("code", "MERKEZDEPO").put("displayName", "Tekrar"),
            ),
        )

        assertEquals(listOf("merkezdepo", "ZONE-B"), options.map { it.code })
        assertEquals("merkezdepo · Merkez Depo", options.first().label)
        assertTrue(validBulkLpLocationSelection("MERKEZDEPO", true, options))
        assertFalse(validBulkLpLocationSelection("BILINMEYEN", true, options))
        assertFalse(validBulkLpLocationSelection("MERKEZDEPO", false, options))
    }

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
