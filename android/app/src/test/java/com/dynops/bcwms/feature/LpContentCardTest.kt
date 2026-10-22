package com.dynops.bcwms.feature

import com.dynops.bcwms.BcApi
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Kitoko (22 Eki 2026): LP okutunca içerik kartı, LP / lot etiketi kararı. */
class LpContentCardTest {
    private fun line(lp: String, item: String, qty: Double, uom: String = "ADET", lot: String = "", variant: String = "") =
        JSONObject().put("lpNo", lp).put("itemNo", item).put("quantity", qty).put("unitOfMeasure", uom)
            .put("lotNo", lot).put("variantCode", variant)

    @Test
    fun lpQrAndSsccOpenTheCardOtherScansDoNot() {
        assertEquals(LpScanRef.ByNo("LP000123"), lpScanRef("LP000123"))
        assertEquals(LpScanRef.ByNo("LP000123"), lpScanRef(" lp000123 "))
        assertEquals(LpScanRef.BySscc("386900000000012345"), lpScanRef("386900000000012345"))
        assertEquals(LpScanRef.BySscc("386900000000012345"), lpScanRef("00386900000000012345"))
        assertNull("EAN-13 ürün barkodu", lpScanRef("8690000012345"))
        assertNull("raf", lpScanRef("B-K03"))
        assertNull("boş", lpScanRef("   "))
        assertNull("ürün no", lpScanRef("SK-10025"))
    }

    @Test
    fun homeNavigationIsConsumedOnce() {
        LpCardNavigation.request(LpScanRef.ByNo("LP000001"))
        assertEquals(LpScanRef.ByNo("LP000001"), LpCardNavigation.consume())
        assertNull(LpCardNavigation.consume())
    }

    @Test
    fun datesTotalsAndDocuments() {
        assertEquals("31.12.2027", lpCardDate("2027-12-31"))
        assertEquals("", lpCardDate("0001-01-01"))
        assertEquals("", lpCardDate(null))
        assertEquals("53 ADET · 12 KOLİ", lpCardTotals(listOf(line("LP1", "A", 48.0), line("LP1", "B", 5.0), line("LP1", "C", 12.0, "KOLİ"))))
        assertEquals("", lpCardTotals(emptyList()))
        assertEquals("Depo kabul RE000123", lpAssignedDocLabel("WhseReceipt", "RE000123"))
        assertEquals("Üretim çıktısı PO1", lpAssignedDocLabel("ProdOutput", "PO1"))
        assertEquals("", lpAssignedDocLabel("None", ""))
    }

    @Test
    fun lotLabelOnlyForLotLinesAndNewBc() {
        val lots = listOf(line("LP1", "A", 1.0, lot = "L1"), line("LP1", "A", 2.0, lot = "L1"), line("LP1", "B", 1.0, lot = "L2"), line("LP1", "C", 1.0))
        val ready = LabelLayoutLoad.Ready(listOf(LabelLayoutOption("LOT", "Lot", "Lot", 80.0, 40.0, 203, false)))
        assertTrue(lpLinesHaveLots(lots))
        assertEquals("Aynı ürün + lot tek etiket", 2, lpLotLabelCount(lots))
        assertTrue(lotLabelOffered(lots, ready))
        assertFalse("lot takipsiz ürün", lotLabelOffered(listOf(line("LP1", "C", 1.0)), ready))
        assertFalse("eski BC (404 / Lot türü yok)", lotLabelOffered(lots, LabelLayoutLoad.Hidden))
    }

    @Test
    fun lotKindLayoutsAreSeparateFromLp() {
        val page = BcApi.PagedItemsResult(
            listOf(
                JSONObject().put("code", "LP").put("labelKind", "LP"),
                JSONObject().put("code", "LOT").put("labelKind", "Lot"),
            ),
            complete = true,
        )
        val lot = labelLayoutsLoad(LabelLayoutKind.Lot, page) as LabelLayoutLoad.Ready
        assertEquals(listOf("LOT"), lot.options.map { it.code })
        val old = BcApi.PagedItemsResult(listOf(JSONObject().put("code", "LP").put("labelKind", "LP")), complete = true)
        assertEquals(LabelLayoutLoad.Hidden, labelLayoutsLoad(LabelLayoutKind.Lot, old))
    }

    @Test
    fun receiptOffersLotLabelOnlyForLpsWithLots() {
        val lines = listOf(line("LP1", "A", 5.0, lot = "L1"), line("LP2", "B", 3.0), line("LP3", "C", 1.0, lot = "L9"))
        assertEquals(listOf("LP1", "LP3"), receiptLotLabelLpNos(listOf("LP1", "LP2", "LP3"), lines))
        assertEquals(emptyList<String>(), receiptLotLabelLpNos(listOf("LP2"), lines))
    }
}
