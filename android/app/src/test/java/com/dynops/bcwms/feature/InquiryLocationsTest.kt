package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class InquiryLocationsTest {
    private fun ile(lot: String, loc: String, qty: Double) =
        JSONObject().put("lotNo", lot).put("locationCode", loc).put("remainingQuantity", qty)

    private fun lpLine(lp: String, lot: String, qty: Double) =
        JSONObject().put("lpNo", lp).put("lotNo", lot).put("quantity", qty)

    private fun lp(no: String, loc: String, bin: String, status: String = "Built") =
        JSONObject().put("no", no).put("locationCode", loc).put("binCode", bin).put("status", status)

    @Test
    fun binPlacesSkipEmptyAndSplitLps() {
        val places = inquiryBinPlaces(listOf(
            JSONObject().put("locationCode", "DKC WMS").put("binCode", "B-02").put("quantity", 5.0).put("activeLpNos", "LP1, LP2"),
            JSONObject().put("locationCode", "DKC WMS").put("binCode", "A-01").put("quantity", 0.0),
            JSONObject().put("locationCode", "DKC WMS").put("binCode", "A-03").put("quantity", 2.0).put("activeLpNos", ""),
        ))
        assertEquals(listOf("A-03", "B-02"), places.map { it.binCode })
        assertEquals(listOf("LP1", "LP2"), places[1].lpNos)
        assertEquals(emptyList<String>(), places[0].lpNos)
    }

    @Test
    fun lotLocationUsesLpBinsAndLooseRemainder() {
        val headers = activeLpHeaders(listOf(lp("LP1", "DKC WMS", "A-01"), lp("LP9", "DKC WMS", "Z-09", status = "Used")))
        val places = inquiryBinPlaces(listOf(
            JSONObject().put("locationCode", "DKC WMS").put("binCode", "A-01").put("quantity", 300.0),
            JSONObject().put("locationCode", "DKC WMS").put("binCode", "B-02").put("quantity", 200.0),
        ))
        val locs = inquiryLotLocations(
            "L1",
            listOf(ile("L1", "DKC WMS", 400.0), ile("L1", "DKC WMS", 100.0), ile("L2", "DKC WMS", 50.0)),
            listOf(lpLine("LP1", "L1", 300.0), lpLine("LP9", "L1", 99.0)),
            headers,
            places,
        )
        assertEquals(1, locs.size)
        assertEquals(500.0, locs[0].quantity, 0.0001)
        assertEquals(listOf(InquiryLotLp("LP1", "A-01", 300.0)), locs[0].lps)
        assertEquals(200.0, locs[0].looseQuantity, 0.0001)
        assertEquals(listOf("A-01", "B-02"), locs[0].looseBins)
    }

    @Test
    fun lotWithoutLpInSingleBinLocation() {
        val places = inquiryBinPlaces(listOf(JSONObject().put("locationCode", "URETIM").put("binCode", "U-1").put("quantity", 10.0)))
        val locs = inquiryLotLocations("L1", listOf(ile("L1", "URETIM", 10.0)), emptyList(), emptyMap(), places)
        assertEquals(10.0, locs[0].looseQuantity, 0.0001)
        assertEquals("Raf U-1", looseBinText(locs[0].looseBins))
    }

    @Test
    fun locationStockAndFilters() {
        val stock = inquiryLocationStock(listOf(ile("", "B", 2.0), ile("X", "A", 1.0), ile("", "B", 3.0)))
        assertEquals(listOf("A" to 1.0, "B" to 5.0), stock)
        assertEquals(listOf("no eq 'A' or no eq 'B'", "no eq 'C''X'"), lpHeaderFilters(listOf("A", "B", "A", "C'X"), chunk = 2))
        assertEquals("DKC WMS · Raf A-01", inquiryPlaceText("DKC WMS", "A-01"))
        assertEquals("DKC WMS", inquiryPlaceText("DKC WMS", ""))
    }
}
