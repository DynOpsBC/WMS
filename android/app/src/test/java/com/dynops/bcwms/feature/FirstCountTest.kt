package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FirstCountTest {
    private fun line(item: String, qty: Double, lot: String = "", bin: String = "") =
        JSONObject().put("itemNo", item).put("quantity", qty).put("quantityBase", qty).put("lotNo", lot).put("binCode", bin)
            .put("variantCode", "").put("unitOfMeasureCode", "ADET").put("description", "d")

    @Test fun `repeated scans of one item are summed`() {
        val t = firstCountTotals(listOf(line("1000", 3.0), line("1000", 4.0), line("2000", 1.0)))
        assertEquals(2, t.size)
        assertEquals(7.0, t.first { it.itemNo == "1000" }.quantity, 0.0)
        assertEquals(2, t.first { it.itemNo == "1000" }.scans)
    }

    @Test fun `different lots and bins stay separate`() {
        val t = firstCountTotals(listOf(line("1000", 1.0, lot = "A"), line("1000", 1.0, lot = "B"), line("1000", 1.0, lot = "A", bin = "R1")))
        assertEquals(3, t.size)
    }

    @Test fun `plain item qr is the item number`() {
        assertEquals("1000-AB" to "", firstCountItemFromScan("1000-ab"))
    }

    @Test fun `lp label is rejected`() {
        assertNull(firstCountItemFromScan("LP000123"))
    }
}
