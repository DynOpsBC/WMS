package com.dynops.bcwms.feature

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class InquiryLotLabelsTest {
    private fun ile(lot: String, remaining: Double) = JSONObject().put("lotNo", lot).put("remainingQuantity", remaining)
    private fun lp(no: String, lot: String) = JSONObject().put("lpNo", no).put("lotNo", lot)

    @Test
    fun `open entries are summed per lot and empty lots are left out`() {
        val lots = inquiryLotStocks(
            listOf(ile("L-003", 300000.0), ile("L-001", 5.5), ile("L-003", 50000.112), ile("", 10.0), ile("L-009", 0.0)),
            listOf(lp("LP000010", "L-003"), lp("LP000011", "l-003"), lp("LP000010", "L-003"), lp("LP000020", "L-001")),
        )
        assertEquals(listOf("L-001", "L-003"), lots.map { it.lotNo })
        assertEquals(350000.112, lots[1].quantity, 0.0001)
        assertEquals(listOf("LP000010", "LP000011"), lots[1].lpNos)
    }

    @Test
    fun `lp text fits the document line`() {
        assertEquals("", lotLabelLpText(emptyList()))
        assertEquals("LP: LP000010", lotLabelLpText(listOf("LP000010")))
        assertEquals("LP: LP000010 +2", lotLabelLpText(listOf("LP000010", "LP000011", "LP000012")))
        assertTrue(lotLabelLpText(listOf("LP-COK-UZUN-NUMARA-000010")).length <= 20)
    }

    @Test
    fun `label row carries item lot quantity and lp`() {
        val row = JSONArray(
            lotLabelRowsJson("9MM KOVAN KASE(AKS)", InquiryLotLabel("DKC26L408-003", 100000.0, listOf("LP000010")), "ADET", "19.11.2026", 2),
        ).getJSONObject(0)
        assertEquals("9MM KOVAN KASE(AKS)", row.getString("itemNo"))
        assertEquals("DKC26L408-003", row.getString("lotNo"))
        assertEquals("100.000 ADET", row.getString("quantityText"))
        assertEquals("LP: LP000010", row.getString("receiptNo"))
        assertEquals(2, row.getInt("copies"))
    }
}
