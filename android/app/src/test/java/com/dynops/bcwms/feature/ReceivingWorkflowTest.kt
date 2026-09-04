package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONObject

class ReceivingWorkflowTest {
    @Test
    fun `bulk receipt is blocked until single ledger entry server contract exists`() {
        val oldServerRows = listOf(JSONObject().put("lineNo", 10000))
        val safeServerRows = listOf(JSONObject().put("lineNo", 10000).put("bulkLpCount", 0))

        assertFalse(bulkReceiptKeepsSingleLedgerEntrySupported(oldServerRows))
        assertTrue(bulkReceiptKeepsSingleLedgerEntrySupported(safeServerRows))
    }

    @Test
    fun `successful LP start survives an immediately stale receipt reload`() {
        assertEquals("LP000041", resolvedActiveReceiptLp("", false, "LP000041"))
    }

    @Test
    fun `server active LP wins after receipt reload`() {
        assertEquals("LP000042", resolvedActiveReceiptLp(" LP000042 ", true, "LP000041"))
    }

    @Test
    fun `normal reload clears a closed LP`() {
        assertNull(resolvedActiveReceiptLp("LP000041", false))
    }

    @Test
    fun `bulk LP receipt lines are restored as ready after reload`() {
        val rows = listOf(
            JSONObject().put("lineNo", 10000).put("licensePlateNo", "LP000101").put("qtyToReceive", 100.0),
            JSONObject().put("lineNo", 20000).put("licensePlateNo", "").put("bulkLpCount", 2).put("qtyToReceive", 100.0),
            JSONObject().put("lineNo", 30000).put("licensePlateNo", "").put("qtyToReceive", 100.0),
        )

        assertEquals(setOf(10000, 20000), restoredBulkReceiptLineNos(rows))
    }

    @Test
    fun `preflight failure reports partial reset and requires reconciliation`() {
        val status = receivingPreflightFailureStatus(resetCount = 2)

        assertTrue(status.startsWith("UYARI: 2 satır sıfırlandı"))
        assertTrue(status.contains("Belge yenilendi"))
        assertTrue(status.contains("mal kabul kaydedilmedi"))
    }

    @Test
    fun `preflight failure without writes remains fail closed`() {
        val status = receivingPreflightFailureStatus(resetCount = 0)

        assertTrue(status.startsWith("HATA:"))
        assertTrue(status.contains("mal kabul kaydedilmedi"))
    }

    @Test
    fun `missing exclude action uses legacy patch fallback`() {
        assertTrue(shouldFallbackReceiptExcludeAction(404, ""))
        assertTrue(
            shouldFallbackReceiptExcludeAction(
                400,
                "Could not find a property named 'excludeFromPost' on type 'Microsoft.NAV.receiptLine'",
            ),
        )
    }

    @Test
    fun `business validation error does not bypass action with patch`() {
        assertTrue(!shouldFallbackReceiptExcludeAction(400, "The warehouse receipt is locked by another user."))
        assertTrue(!shouldFallbackReceiptExcludeAction(403, "Forbidden"))
    }
}
