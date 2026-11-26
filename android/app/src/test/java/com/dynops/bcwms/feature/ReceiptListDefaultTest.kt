package com.dynops.bcwms.feature

import org.junit.Assert.*
import org.junit.Test

class ReceiptListDefaultTest {
    @Test fun `Element4 receipt list opens with all documents, other customers with their own`() {
        assertTrue(receiptListShowsAllByDefault("kitoko"))
        assertFalse(receiptListShowsAllByDefault("bade"))
        assertFalse(receiptListShowsAllByDefault("emu"))
    }
    @Test fun `supplier and order are shown on the receipt card`() {
        assertEquals("Tedarikçi: YILMAZ SAC · Sipariş: 106003", receiptVendorLine(" YILMAZ SAC ", "106003"))
        assertEquals("Tedarikçi: -", receiptVendorLine("", ""))
    }
}
