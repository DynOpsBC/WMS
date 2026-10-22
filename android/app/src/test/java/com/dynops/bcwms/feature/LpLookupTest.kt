package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Kitoko (22 Eki 2026): Etiket Çıkar → LP Etiketi arama listesi ve LP ekranından LP etiketi. */
class LpLookupTest {
    private fun header(no: String, status: String = "Built", bin: String = "A-01", total: Double = 0.0) =
        JSONObject().put("no", no).put("status", status).put("locationCode", "ANA").put("binCode", bin).put("totalQuantity", total)

    private fun line(lp: String, item: String, qty: Double, lot: String = "", desc: String = "", uom: String = "KOLİ") =
        JSONObject().put("lpNo", lp).put("itemNo", item).put("quantity", qty).put("lotNo", lot)
            .put("itemDescription", desc).put("unitOfMeasure", uom)

    @Test
    fun headerPathDefaultsToActiveNewestFirstPaged() {
        val path = lpLookupHeaderPath("", activeOnly = true, lineMatchLpNos = emptyList(), skip = 0)
        assertTrue(path, path.startsWith("licensePlates?\$select=$LP_LOOKUP_HEADER_SELECT"))
        assertTrue(path, path.contains("&\$orderby=no desc"))
        assertTrue("bir fazlası: sonraki sayfa var mı", path.contains("&\$top=${LP_LOOKUP_PAGE_SIZE + 1}"))
        assertTrue(path, path.contains("&\$skip=0"))
        assertTrue(path, path.endsWith("&\$filter=(status eq 'Open' or status eq 'Built' or status eq 'Assigned')"))
    }

    @Test
    fun headerPathAllStatusesWithoutTextHasNoFilter() {
        val path = lpLookupHeaderPath("  ", activeOnly = false, lineMatchLpNos = emptyList(), skip = 50)
        assertFalse(path, path.contains("\$filter"))
        assertTrue(path, path.contains("&\$skip=50"))
    }

    @Test
    fun headerPathSearchesNoBinSsccAndLineMatches() {
        val path = lpLookupHeaderPath(" lp0001 ", activeOnly = true, lineMatchLpNos = listOf("LP000010", "LP000010", " ", "LP000002"), skip = 0)
        assertTrue(path, path.contains(
            "(status eq 'Open' or status eq 'Built' or status eq 'Assigned') and " +
                "(contains(no,'LP0001') or contains(binCode,'LP0001') or contains(sscc,'LP0001') or no eq 'LP000010' or no eq 'LP000002')",
        ))
    }

    @Test
    fun quotesAreEscaped() {
        val path = lpLookupHeaderPath("A'B", activeOnly = false, lineMatchLpNos = listOf("X'1"), skip = 0)
        assertTrue(path, path.contains("contains(no,'A''B')"))
        assertTrue(path, path.contains("no eq 'X''1'"))
        assertEquals(
            "licensePlateLines?\$filter=contains(itemNo,'A''B') or contains(lotNo,'A''B')&\$select=lpNo&\$orderby=lpNo desc&\$top=200",
            lpLookupLineMatchPath("a'b"),
        )
        assertNull(lpLookupLineMatchPath("   "))
    }

    @Test
    fun lineMatchesAreDistinctNewestFirstAndCapped() {
        assertEquals(listOf("LP000010", "LP000009", "LP000002"), lpLookupLineMatches(listOf("LP000002", "LP000010", "LP000009", "LP000010", "", "null")))
        val many = (1..60).map { "LP%06d".format(it) }
        val capped = lpLookupLineMatches(many)
        assertEquals(LP_LOOKUP_LINE_MATCH_MAX, capped.size)
        assertEquals("LP000060", capped.first())
    }

    @Test
    fun contentPathLoadsOnlyThePageLps() {
        assertNull(lpLookupContentPath(emptyList()))
        assertEquals(
            "licensePlateLines?\$filter=lpNo eq 'LP2' or lpNo eq 'LP1'&\$select=lpNo,lineNo,itemNo,itemDescription,lotNo,quantity,unitOfMeasure&\$orderby=lpNo,lineNo",
            lpLookupContentPath(listOf("LP2", "LP1", "LP2", " ")),
        )
    }

    @Test
    fun rowsShowFirstItemLotsAndTotals() {
        val rows = lpLookupRows(
            listOf(header("LP2"), header("LP1", status = "Open", bin = "")),
            listOf(
                line("LP2", "SK-1", 10.0, lot = "L1", desc = "Süt"),
                line("LP2", "SK-1", 5.0, lot = "L2", desc = "Süt"),
                line("LP2", "SK-2", 3.0, lot = "L1", uom = "ADET"),
                JSONObject().put("lpNo", "LP2").put("childLpNo", "LP9"),
            ),
        )
        assertEquals(listOf("LP2", "LP1"), rows.map { it.no })
        val full = rows[0]
        assertEquals("SK-1", full.firstItemNo)
        assertEquals("Süt", full.firstItemDescription)
        assertEquals(1, full.otherItemCount)
        assertEquals(listOf("L1", "L2"), full.lots)
        assertEquals("15 KOLİ · 3 ADET", full.totals)
        assertEquals("ANA", full.locationCode)
        val empty = rows[1]
        assertEquals("Boş LP", empty.totals)
        assertEquals("", empty.firstItemNo)
        assertEquals("Open", empty.status)
    }

    @Test
    fun rowsFallBackToHeaderTotalWhenContentFailed() {
        val rows = lpLookupRows(listOf(header("LP1", total = 48.0), header("LP2")), null)
        assertEquals("48", rows[0].totals)
        assertEquals("", rows[1].totals)
    }

    @Test
    fun lotsLabelAndExactMatch() {
        assertEquals("", lpLookupLotsLabel(emptyList()))
        assertEquals("A, B, C +2", lpLookupLotsLabel(listOf("A", "B", "C", "D", "E")))
        val rows = lpLookupRows(listOf(header("PAL-0001")), emptyList())
        assertEquals("PAL-0001", lpLookupExactMatch(rows, " pal-0001 "))
        assertNull(lpLookupExactMatch(rows, "PAL-0002"))
        assertNull(lpLookupExactMatch(rows, ""))
    }

    @Test
    fun scannedItemLabelSearchesByLotThenItem() {
        assertEquals("LOT42", lpLookupQueryFromScan("(01)08690000012345(10)lot42"))
        assertEquals("SK-10025", lpLookupQueryFromScan(" sk-10025 "))
    }

    @Test
    fun lpLabelStatusSummaries() {
        assertEquals(
            "TAMAM: LP000001 LP etiketi × 2 ZEBRA1 kuyruğuna alındı. Tasarım: LP-QR.",
            lpLabelPrintStatus(LpLabelPrintOutcome("ZEBRA1", "", listOf("LP000001"), emptyMap()), 2, "LP-QR"),
        )
        assertEquals(
            "TAMAM: 3 LP etiketi × 1 ZEBRA1 kuyruğuna alındı. Uyarı",
            lpLabelPrintStatus(LpLabelPrintOutcome("ZEBRA1", "Uyarı", listOf("A", "B", "C"), emptyMap()), 1, ""),
        )
        assertEquals(
            "UYARI: 1 LP kuyruğa alındı; 1 LP etiketi yazdırılamadı. B: yazıcı kapalı",
            lpLabelPrintStatus(LpLabelPrintOutcome("Z", "", listOf("A"), linkedMapOf("B" to "yazıcı kapalı")), 1, ""),
        )
        assertEquals(
            "HATA: Etiket yazıcısı seçilmedi.",
            lpLabelPrintStatus(LpLabelPrintOutcome("", "", emptyList(), emptyMap(), "Etiket yazıcısı seçilmedi."), 1, ""),
        )
    }

    @Test
    fun lpLabelActionsOnlyInKitoko() {
        assertTrue(lpLabelActionsOffered("kitoko"))
        assertFalse(lpLabelActionsOffered("bade"))
        assertFalse(lpLabelActionsOffered("emu"))
        assertFalse(lpLabelActionsOffered("dynops"))
    }
}
