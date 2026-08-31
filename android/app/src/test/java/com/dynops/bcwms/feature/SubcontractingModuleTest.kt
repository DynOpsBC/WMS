package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SubcontractingModuleTest {
    private fun operation() = JSONObject().apply {
        put("status", "Released")
        put("prodOrderNo", "PÜ'100")
        put("routingReferenceNo", 10000)
        put("routingNo", "RT-01")
        put("operationNo", "20")
    }

    @Test
    fun `operation identity contains every BC composite key field`() {
        assertEquals("Released|PÜ'100|10000|RT-01|20", operationKey(operation()))
    }

    @Test
    fun `bound action key escapes production order apostrophe`() {
        val key = operationODataKey(operation())
        assertTrue(key.contains("status='Released'"))
        assertTrue(key.contains("prodOrderNo='PÜ''100'"))
        assertTrue(key.contains("routingReferenceNo=10000"))
        assertTrue(key.contains("operationNo='20'"))
    }

    @Test
    fun `component identity separates production and component lines`() {
        val component = JSONObject().put("prodOrderLineNo", 10000).put("componentLineNo", 20000)
        assertEquals("10000|20000", componentKey(component))
    }

    @Test
    fun `multiple LP scans append once and stay comma separated`() {
        assertEquals("LP001", appendLpBarcode("", " LP001 "))
        assertEquals("LP001,LP002", appendLpBarcode("LP001", "LP002"))
        assertEquals("LP001,LP002", appendLpBarcode("LP001,LP002", "LP002"))
    }

    @Test
    fun `receipt identity and bound action escape every purchase key`() {
        val row = JSONObject()
            .put("documentType", "Order")
            .put("purchaseOrderNo", "FS'100")
            .put("purchaseLineNo", 20000)
        assertEquals("Order|FS'100|20000", subcontractReceiptKey(row))
        assertEquals(
            "documentType='Order',purchaseOrderNo='FS''100',purchaseLineNo=20000",
            subcontractReceiptODataKey(row),
        )
    }

    @Test
    fun `return barcode matches outbound purchase production and supplier references`() {
        val row = JSONObject()
            .put("outboundReferenceNo", "FS-100")
            .put("purchaseOrderNo", "PO-200")
            .put("prodOrderNo", "PROD-300")
            .put("vendorOrderNo", "V-400")
            .put("externalDocumentNo", "EXT-500")
            .put("outboundTransferShipmentNo", "TS-600")
        listOf("fs-100", "PO-200", "prod-300", "V-400", "ext-500", "ts-600").forEach {
            assertTrue(subcontractReceiptMatchesReference(row, it))
        }
    }

    @Test
    fun `operation can close only on exact full receipt`() {
        assertTrue(canFinishSubcontractOperation(10.0, 10.0))
        assertFalse(canFinishSubcontractOperation(5.0, 10.0))
        assertFalse(canFinishSubcontractOperation(10.1, 10.0))
        assertFalse(canFinishSubcontractOperation(0.0, 0.0))
    }

    @Test
    fun `dispatch list groups operation lines under production order`() {
        val rows = listOf(
            operation().put("operationNo", "10"),
            operation().put("operationNo", "20"),
            operation().put("prodOrderNo", "PÜ-200").put("operationNo", "10"),
        )

        val groups = subcontractDispatchGroups(rows)

        assertEquals(2, groups.size)
        assertEquals("PÜ'100", subcontractDispatchDocumentKey(groups[0].first()))
        assertEquals(listOf("10", "20"), groups[0].map { it.getString("operationNo") })
        assertEquals("PÜ-200", subcontractDispatchDocumentKey(groups[1].first()))
    }

    @Test
    fun `receipt list groups product lines under outbound reference`() {
        fun line(reference: String, po: String, lineNo: Int) = JSONObject()
            .put("documentType", "Order")
            .put("outboundReferenceNo", reference)
            .put("purchaseOrderNo", po)
            .put("purchaseLineNo", lineNo)

        val groups = subcontractReceiptGroups(
            listOf(line("FS-100", "PO-1", 10), line("FS-100", "PO-1", 20), line("", "PO-2", 10)),
        )

        assertEquals(2, groups.size)
        assertEquals("FS-100", subcontractReceiptDocumentKey(groups[0].first()))
        assertEquals(2, groups[0].size)
        assertEquals("PO-2", subcontractReceiptDocumentKey(groups[1].first()))
    }

    @Test
    fun `receipt search includes item supplier and every document reference`() {
        val row = JSONObject()
            .put("outboundReferenceNo", "FS-100")
            .put("purchaseOrderNo", "PO-200")
            .put("prodOrderNo", "PROD-300")
            .put("itemNo", "HM.00025")
            .put("vendorNo", "V-400")
            .put("vendorName", "ÖRNEK FASONCU")

        listOf("FS-100", "PO-200", "PROD-300", "hm.00025", "V-400", "örnek").forEach {
            assertTrue(it, subcontractReceiptMatchesReference(row, it))
        }
    }
}
