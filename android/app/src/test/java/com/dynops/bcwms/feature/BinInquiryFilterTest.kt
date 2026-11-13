package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class BinInquiryFilterTest {
    private val rows = listOf(
        JSONObject().put("itemNo", "P-01061").put("itemDescription", "M5x35 Bombe İmbus").put("quantity", 100),
        JSONObject().put("itemNo", "P-00016").put("itemDescription", "Somun").put("quantity", 7),
    )

    @Test fun `filter by code or description without changing stock rows`() {
        assertSame(rows[0], filterBinInquiryItems(rows, " p-01061 ").single())
        assertSame(rows[0], filterBinInquiryItems(rows, "bombe").single())
        assertEquals(100, rows[0].getInt("quantity"))
        assertEquals(2, rows.size)
    }

    @Test fun `clearing filter restores every row and missing item gives no matches`() {
        assertTrue(filterBinInquiryItems(rows, "missing").isEmpty())
        assertSame(rows, filterBinInquiryItems(rows, " "))
    }
}
