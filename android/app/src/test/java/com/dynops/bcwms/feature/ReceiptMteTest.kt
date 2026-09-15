package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiptMteTest {
    private fun line(lp: String, receipt: String = "R1", type: String = "WhseReceipt", quantity: Double = 2.0) =
        JSONObject().put("lpNo", lp).put("sourceDocumentNo", receipt)
            .put("sourceDocumentType", type).put("itemNo", "ITEM1").put("quantity", quantity)

    @Test
    fun `all material groups on one LP yield one reprint choice`() {
        val rows = listOf(line("LP2"), line("LP1"), line("LP2").put("lotNo", "LOT2"))
        assertEquals(listOf("LP1", "LP2"), receiptMteLpNos("R1", rows))
    }

    @Test
    fun `another receipt or document type cannot leak into MTE choices`() {
        val rows = listOf(line("LP1"), line("LP2", receipt = "R2"), line("LP3", type = "WhseShipment"))
        assertEquals(listOf("LP1"), receiptMteLpNos("R1", rows))
    }

    @Test
    fun `empty or exhausted contents do not offer a misleading MTE reprint`() {
        val rows = listOf(
            line(""), line("LP1", quantity = 0.0), line("LP2", quantity = -1.0),
            line("LP3").put("itemNo", ""), JSONObject(),
        )
        assertTrue(receiptMteLpNos("R1", rows).isEmpty())
    }
}
