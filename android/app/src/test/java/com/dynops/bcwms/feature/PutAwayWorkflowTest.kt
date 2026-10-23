package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** BADE 1.14.200 (Merve): LP ile arama, boşta belge, boş göz önerisi, kısmi yerleştirme. */
class PutAwayWorkflowTest {
    private fun line(lineNo: Int, action: String, item: String, lp: String, qty: Double, toHandle: Double, bin: String = "") =
        JSONObject().apply {
            put("lineNo", lineNo)
            put("actionType", action)
            put("sourceNo", "PO-1")
            put("sourceLineNo", if (item == "AB.00006") 10000 else 20000)
            put("whseDocumentNo", "PR-1")
            put("whseDocumentLineNo", if (item == "AB.00006") 10000 else 20000)
            put("itemNo", item)
            put("unitOfMeasureCode", "ADET")
            put("lpNo", lp)
            put("quantity", qty)
            put("qtyOutstanding", qty)
            put("qtyToHandle", toHandle)
            put("binCode", bin)
        }

    // BC satırları Qty. to Handle dolu oluşturur: 10/5 hazır gibi görünür.
    private val mixedLp = listOf(
        line(10000, "Take", "AB.00006", "LP000706", 10.0, 10.0, "K.K03.11"),
        line(20000, "Place", "AB.00006", "LP000706", 10.0, 10.0, "A.B01.11"),
        line(30000, "Take", "AB.00007", "LP000706", 5.0, 5.0, "K.K03.11"),
        line(40000, "Place", "AB.00007", "LP000706", 5.0, 5.0, "A.Z09.31"),
    )

    @Test
    fun `karma LP'de yalniz dogrulanan urun kaydedilir digeri sifirlanir`() {
        val plan = putAwayRegisterQuantityPlan(mixedLp, stagedLineNos = setOf(10000, 20000))
        assertEquals(10.0, plan[10000]!!, 0.0)
        assertEquals(10.0, plan[20000]!!, 0.0)
        assertEquals(0.0, plan[30000]!!, 0.0)
        assertEquals(0.0, plan[40000]!!, 0.0)
    }

    @Test
    fun `tam LP icin iki urun de kaydedilir`() {
        val plan = putAwayRegisterQuantityPlan(mixedLp, stagedLineNos = setOf(10000, 20000, 30000, 40000))
        assertEquals(listOf(10.0, 10.0, 5.0, 5.0), listOf(10000, 20000, 30000, 40000).map { plan[it]!! })
    }

    @Test
    fun `operatorun sectigi raf onerinin onune gecer`() {
        // Öneri A.B01.11; operatör A.K03.32'yi okuttu → alternatif kabul edilir.
        assertEquals(PutAwayTargetDecision.ALTERNATIVE, decidePutAwayTarget("A.K03.32", "A.B01.11", existsAtLocation = true))
        assertEquals(PutAwayTargetDecision.SUGGESTED, decidePutAwayTarget("a.b01.11", "A.B01.11", existsAtLocation = true))
        assertEquals(PutAwayTargetDecision.NOT_FOUND, decidePutAwayTarget("X.YOK", "A.B01.11", existsAtLocation = false))
    }

    @Test
    fun `kart onaylanmadan hazir gorunmez ve oneri notr gosterilir`() {
        val suggestion = PutAwayBinSuggestion("A.B02.05", "A", "EMPTY")
        val target = putAwayCardTarget(staged = false, placeBin = "A.TOPLAM", suggestion = suggestion)
        assertFalse(putAwayPairReady(staged = false))
        assertFalse(target.confirmed)
        assertEquals("📥 Öneri", target.label)
        assertEquals("A.B02.05", target.bin)
    }

    @Test
    fun `oneri yoksa BC gozu oneri olarak kalir`() {
        val target = putAwayCardTarget(staged = false, placeBin = "A.TOPLAM", suggestion = null)
        assertEquals("📥 Öneri", target.label)
        assertEquals("A.TOPLAM", target.bin)
    }

    @Test
    fun `dogrulanan kart hazir ve secilen gozu gosterir`() {
        val target = putAwayCardTarget(staged = true, placeBin = "A.K03.32", suggestion = PutAwayBinSuggestion("A.B02.05", "A", "EMPTY"))
        assertTrue(putAwayPairReady(staged = true))
        assertTrue(target.confirmed)
        assertEquals("📥 Koy", target.label)
        assertEquals("A.K03.32", target.bin)
    }

    @Test
    fun `bos goz onerisi yaniti satir numarasina gore okunur`() {
        val raw = """[{"lineNo":20000,"lpNo":"LP000706","binCode":"A.B02.05","zoneCode":"A","source":"EMPTY"},""" +
            """{"lineNo":40000,"lpNo":"LP000706","binCode":"A.B02.05","zoneCode":"A","source":"EMPTY"},""" +
            """{"lineNo":60000,"lpNo":"","binCode":"","zoneCode":"","source":"BC_FALLBACK"}]"""
        val map = parsePutAwayBinSuggestions(raw)
        assertEquals(2, map.size)
        assertEquals("A.B02.05", map[20000]!!.binCode)
        assertTrue(map[40000]!!.isEmptyBin)
        assertTrue(parsePutAwayBinSuggestions("not json").isEmpty())
        assertTrue(parsePutAwayBinSuggestions("").isEmpty())
    }

    @Test
    fun `bana listesi atanmamis belgeleri de gosterir ve once benimkileri siralar`() {
        fun doc(no: String, owner: String) = JSONObject().put("no", no).put("assignedUserId", owner)
        val rows = listOf(doc("PU3", "OTHER"), doc("PU2", ""), doc("PU1", "OP50FFC"))
        assertTrue(putAwayVisibleForMine(rows[1], "op50ffc"))
        assertTrue(putAwayVisibleForMine(rows[2], "op50ffc"))
        assertFalse(putAwayVisibleForMine(rows[0], "op50ffc"))
        assertEquals(listOf("PU1", "PU2", "PU3"), sortPutAwaysForUser(rows, "OP50FFC").map { it.optString("no") })
    }

    @Test
    fun `atanan kisinin adi kimlik yerine gosterilir`() {
        assertEquals("Ahmet Yılmaz", putAwayAssigneeLabel("OP50FFC1", "Ahmet Yılmaz"))
        assertEquals("OP50FFC1", putAwayAssigneeLabel("OP50FFC1", ""))
        assertEquals("OP50FFC1", putAwayAssigneeLabel("OP50FFC1", "null"))
        assertEquals("Atanmamış", putAwayAssigneeLabel("", ""))
    }

    @Test
    fun `LP aramasi satir ve atama sorgulari guvenli kurulur`() {
        assertEquals(
            "putAwayLines?\$filter=lpNo eq 'LP000706'&\$select=no&\$top=200",
            putAwayLinesByLpPath(" lp000706 "),
        )
        assertTrue(putAwayLinesByLpPath("L'P").contains("'L''P'"))
        assertTrue(licensePlateBySsccPath("012345678901234567").contains("sscc eq '012345678901234567'"))
    }

    @Test
    fun `LP basligi yerlestirmeye atanmissa belge bulunur`() {
        assertEquals("PU001042", putAwayNoFromLpAssignment(JSONObject().put("assignedDocumentType", "WhsePutaway").put("assignedDocumentNo", "PU001042")))
        assertNull(putAwayNoFromLpAssignment(JSONObject().put("assignedDocumentType", "WhsePick").put("assignedDocumentNo", "PI0001")))
        assertNull(putAwayNoFromLpAssignment(null))
    }

    @Test
    fun `tek belge dogrudan acilir birden fazlasi suzulur`() {
        assertEquals(PutAwaySearchOutcome.Open("PU001042"), putAwaySearchOutcome(setOf("PU001042")))
        assertEquals(PutAwaySearchOutcome.Filter(setOf("PU1", "PU2")), putAwaySearchOutcome(setOf("PU1", "PU2")))
        assertEquals(PutAwaySearchOutcome.NotFound, putAwaySearchOutcome(emptySet()))
    }
}
