package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiptLpLabelsTest {
    private fun lpLine(lp: String, receipt: String = "R1", lot: String = "", quantity: Double = 5.0) =
        JSONObject().put("lpNo", lp).put("sourceDocumentNo", receipt).put("sourceDocumentType", "WhseReceipt")
            .put("itemNo", "ITEM1").put("quantity", quantity).put("lotNo", lot)

    private fun receiptLine(lp: String) = JSONObject().put("licensePlateNo", lp).put("qtyToReceive", 3.0)

    @Test fun `only kitoko prints receipt labels on the terminal and hides MTE`() {
        assertTrue(terminalPrintsReceiptLabels("kitoko"))
        assertTrue(terminalPrintsReceiptLabels("Kitoko"))
        for (flavor in listOf("bade", "emu", "dynops", "")) {
            assertFalse(flavor, terminalPrintsReceiptLabels(flavor))
            assertTrue(flavor, mteOffered(flavor))
        }
        assertFalse(mteOffered("kitoko"))
    }

    @Test fun `kitoko always posts without BC label printing`() {
        for (skip in listOf(false, true)) {
            val request = receiptPostRequestFor("kitoko", skip, printReceipt = false, documentPrinter = "DOC1", lpPrinter = "ZPL1")
            assertEquals("postToPrinter", request.action)
            val body = JSONObject(request.body)
            assertFalse(body.getBoolean("print"))
            assertEquals("", body.getString("printerId"))
            assertFalse(body.has("lpPrinterId"))
            // Same exemption as "Yazdırmadan kaydet": no printer needed when nothing prints in BC.
            assertEquals(null, terminalPrintRequestIssue(request.body, "receipts(x)/Microsoft.NAV.postToPrinter"))
        }
    }

    @Test fun `kitoko still prints the receipt document when asked`() {
        val body = JSONObject(receiptPostRequestFor("kitoko", false, printReceipt = true, documentPrinter = "DOC1", lpPrinter = "ZPL1").body)
        assertTrue(body.getBoolean("print"))
        assertEquals("DOC1", body.getString("printerId"))
        val skipped = JSONObject(receiptPostRequestFor("kitoko", true, printReceipt = true, documentPrinter = "DOC1", lpPrinter = "ZPL1").body)
        assertFalse(skipped.getBoolean("print"))
    }

    @Test fun `bade and emu post requests are unchanged`() {
        for (flavor in listOf("bade", "emu", "dynops")) for (skip in listOf(false, true)) for (doc in listOf(false, true)) {
            assertEquals(receiptPostRequest(skip, doc, "DOC1", "ZPL1"), receiptPostRequestFor(flavor, skip, doc, "DOC1", "ZPL1"))
        }
        assertEquals("postAndCloseLP", receiptPostRequestFor("bade", false, false, "DOC1", "ZPL1").action)
    }

    @Test fun `terminal labels only for kitoko when not skipped`() {
        assertTrue(receiptAutoLpLabels("kitoko", skipPrinting = false))
        assertFalse(receiptAutoLpLabels("kitoko", skipPrinting = true))
        assertFalse(receiptAutoLpLabels("bade", skipPrinting = false))
        assertFalse(receiptAutoLpLabels("emu", skipPrinting = false))
    }

    @Test fun `candidates come from posted lines, header and active LP`() {
        val candidates = receiptPostLpCandidates(
            listOf(receiptLine("LP1"), receiptLine(""), receiptLine("LP1"), JSONObject()),
            headerLpNo = " LP2 ", activeLpNo = null,
        )
        assertEquals(setOf("LP1", "LP2"), candidates)
        assertEquals(emptySet<String>(), receiptPostLpCandidates(emptyList(), "", ""))
    }

    @Test fun `earlier partial receipt LPs are not labelled again`() {
        val before = listOf(lpLine("LP-OLD"))
        val after = listOf(lpLine("LP-OLD"), lpLine("LP-NEW2"), lpLine("LP-NEW1"), lpLine("LP-NEW1", lot = "L2"))
        assertEquals(listOf("LP-NEW1", "LP-NEW2"), receiptLpsClosedByPost("R1", before, after, emptySet()))
    }

    @Test fun `an LP of this post that already had contents is still labelled`() {
        val before = listOf(lpLine("LP-OLD"), lpLine("LP-ACTIVE"))
        val after = listOf(lpLine("LP-OLD"), lpLine("LP-ACTIVE"), lpLine("LP-NEW"))
        assertEquals(listOf("LP-ACTIVE", "LP-NEW"), receiptLpsClosedByPost("R1", before, after, setOf("LP-ACTIVE", "LP-MISSING")))
    }

    @Test fun `other receipts, empty LPs and candidates without contents get no label`() {
        val after = listOf(lpLine("LP-X", receipt = "R2"), lpLine("LP-EMPTY", quantity = 0.0), lpLine("LP1"))
        assertEquals(listOf("LP1"), receiptLpsClosedByPost("R1", emptyList(), after, setOf("LP-EMPTY", "LP-GHOST")))
    }

    @Test fun `lot labels only for lot tracked LPs of this post`() {
        val after = listOf(lpLine("LP1", lot = "LOT1"), lpLine("LP2"), lpLine("LP3", lot = "LOT3"))
        val closed = receiptLpsClosedByPost("R1", listOf(lpLine("LP3", lot = "LOT3")), after, emptySet())
        assertEquals(listOf("LP1", "LP2"), closed)
        assertEquals(listOf("LP1"), receiptLotLabelLpNos(closed, after))
    }

    @Test fun `result message lists every failure and never promises a retry`() {
        val ok = receiptAutoLabelStatus(ReceiptAutoLabelResult(listOf("LP1", "LP2"), listOf("LP1", "LP2"), emptyMap(), printerCode = "ZPL1"))
        assertTrue(ok, ok.startsWith("TAMAM:") && ok.contains("2 LP etiketi") && ok.contains("ZPL1"))
        val partial = receiptAutoLabelStatus(ReceiptAutoLabelResult(
            listOf("LP1", "LP2", "LP3"), listOf("LP1"), linkedMapOf("LP2" to "timeout", "LP3 lot" to "HTTP 500"),
            lotRequested = 1, lotPrinted = 0,
        ))
        assertTrue(partial, partial.startsWith("UYARI:") && partial.contains("1/3") && partial.contains("LP2: timeout") &&
            partial.contains("LP3 lot: HTTP 500") && partial.contains("Otomatik tekrar denenmedi"))
        val none = receiptAutoLabelStatus(ReceiptAutoLabelResult(emptyList(), emptyList(), emptyMap()))
        assertTrue(none, none.startsWith("TAMAM:") && none.contains("LP bulunamadı"))
        val error = receiptAutoLabelStatus(ReceiptAutoLabelResult(emptyList(), emptyList(), emptyMap(), error = "Yazıcı yok."))
        assertTrue(error, error.startsWith("UYARI:") && error.contains("Etiketler ekranından"))
    }
}
