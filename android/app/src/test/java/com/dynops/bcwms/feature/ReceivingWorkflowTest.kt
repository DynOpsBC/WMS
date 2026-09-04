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

    @Test
    fun `missing atomic receipt action names required BC package`() {
        val status = missingReceiptPostBackendStatus(404, "No HTTP resource was found")

        assertTrue(status.orEmpty().contains("1.14.1.20"))
        assertTrue(status.orEmpty().contains("belge ve LP kaydedilmedi"))
        assertNull(missingReceiptPostBackendStatus(400, "Posting date is required"))
    }

    @Test
    fun `receipt post exposes actionable unknown BC validation instead of only ref`() {
        val status = receiptPostFailureStatus(
            "Warehouse handling is required for this item. CorrelationId: 12345678-1234-1234-1234-123456789012.",
            400,
        )

        assertTrue(status.contains("Mal kabul kaydedilmedi"))
        assertTrue(status.contains("Warehouse handling is required for this item"))
        assertFalse(status.contains("CorrelationId"))
        assertFalse(status.contains("REF-"))
    }

    @Test
    fun `receipt post translates purchase and receipt location mismatch`() {
        val status = receiptPostFailureStatus(
            "Location Code must be equal to '' in Purchase Line: No.=X. Current value is 'MERKEZDEPO'.",
            400,
        )

        assertTrue(status.contains("lokasyonu uyuşmuyor"))
        assertTrue(status.contains("beklenen: boş"))
        assertTrue(status.contains("mevcut: MERKEZDEPO"))
    }
}
