package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class PalletBoxRowsTest {
    private fun line(lp: String, item: String, qty: Double, lot: String = "") =
        JSONObject().put("lpNo", lp).put("itemNo", item).put("quantity", qty).put("lotNo", lot).put("unitOfMeasure", "ADET")

    @Test fun `pallet shows each box with its content and a total`() {
        val boxes = palletBoxRows(listOf("LP000540", "LP000541", "LP000543"),
            listOf(line("LP000540", "5.56MM", 100.0, "L1"), line("LP000541", "5.56MM", 100.0, "L1")))
        assertEquals(listOf("5.56MM × 100 · Lot L1", "5.56MM × 100 · Lot L1", "içerik yok"), boxes.map { it.text })
        assertEquals("3 kutu · 200 ADET", palletBoxSummary(boxes))
    }
    @Test fun `mixed units show only the box count`() {
        val kg = JSONObject().put("lpNo", "B").put("itemNo", "X").put("quantity", 2.5).put("unitOfMeasure", "KG")
        assertEquals("2 kutu", palletBoxSummary(palletBoxRows(listOf("A", "B"), listOf(line("A", "X", 1.0), kg))))
    }
}
