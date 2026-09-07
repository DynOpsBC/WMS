package com.dynops.bcwms.feature

import com.dynops.bcwms.scanner.BarcodeIntentResolver
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CountV2WorkflowTest {
    @Test
    fun `persisted retry retains original counter bin quantity and scan identity`() {
        val pending = PendingCountV2Scan("cab4ecca-1528-49df-a905-0f6df019989c", "A1",
            CountV2Label("ITEM", "RED", "ADET", "LOT", "SN", 5.0, "raw barcode"), 2)
        val restored = PendingCountV2Scan.fromStoredJson(pending.storedJson())
        assertEquals(pending, restored)
        val body = JSONObject(restored.payload())
        assertEquals(2, body.getInt("counterSlot"))
        assertEquals("A1", body.getString("binCode"))
        assertEquals(pending.scanId, body.getString("scanId"))
        assertEquals(5.0, body.getDouble("qty"), 0.0)
    }

    @Test
    fun `corrupt pending operation cannot silently become a fresh count`() {
        for (value in listOf("{}", "not json", """{"scanId":"invalid"}""")) {
            assertTrue(runCatching { PendingCountV2Scan.fromStoredJson(value) }.isFailure)
        }
    }

    private fun reviewLine(bin: String, system: Double, counted: Double, complete: Boolean = true, lot: String = "L1", uom: String = "ADET"): JSONObject =
        JSONObject().put("itemNo", "E").put("binCode", bin).put("systemQty", system)
            .put("countedQty1", counted).put("counted1", complete).put("lotNo", lot).put("unitOfMeasureCode", uom)
            .put("variance", counted - system)

    @Test
    fun `uncounted source bin is pending instead of a zero shortage`() {
        val groups = countV2VarianceGroups(listOf(reviewLine("A1", 0.0, 5.0), reviewLine("A2", 5.0, 0.0, false)), 1, false)
        assertFalse(groups.single().complete)
        assertFalse(groups.single().possibleBinMismatch)
        assertTrue(countV2VarianceReviewText(groups).contains("A2: sayım bekliyor"))
        assertFalse(countV2VarianceReviewText(groups).contains("Toplam stok farkı"))
    }

    @Test
    fun `explicit zero source and matching destination suggest bin difference`() {
        val group = countV2VarianceGroups(listOf(reviewLine("A1", 0.0, 5.0), reviewLine("A2", 5.0, 0.0)), 1, false).single()
        assertTrue(group.possibleBinMismatch)
        assertEquals(0.0, group.net, 0.0)
        assertTrue(countV2VarianceReviewText(listOf(group)).contains("A2: -5"))
    }

    @Test
    fun `stock still present in source stays a real surplus`() {
        val group = countV2VarianceGroups(listOf(reviewLine("A1", 0.0, 5.0), reviewLine("A2", 5.0, 5.0)), 1, false).single()
        assertFalse(group.possibleBinMismatch)
        assertEquals(5.0, group.net, 0.0)
    }

    @Test
    fun `different lots and units cannot offset each other`() {
        val groups = countV2VarianceGroups(listOf(reviewLine("A1", 0.0, 5.0),
            reviewLine("A2", 5.0, 0.0, lot = "L2"), reviewLine("A3", 5.0, 0.0, uom = "KOLI")), 1, false)
        assertEquals(3, groups.size)
        assertTrue(groups.none { it.possibleBinMismatch })
    }

    @Test
    fun `different variants and serials cannot offset each other`() {
        val groups = countV2VarianceGroups(listOf(reviewLine("A1", 0.0, 5.0).put("variantCode", "RED"),
            reviewLine("A2", 5.0, 0.0).put("variantCode", "BLUE"),
            reviewLine("A3", 5.0, 0.0).put("serialNo", "SN1")), 1, false)
        assertEquals(3, groups.size)
    }

    @Test
    fun `final review uses server winning variance instead of one counters quantity`() {
        val groups = countV2VarianceGroups(listOf(reviewLine("A1", 5.0, 2.0).put("variance", -1.0)), 1, true)
        assertEquals(-1.0, groups.single().net, 0.0)
    }

    @Test
    fun `missing counted flag cannot be treated as a completed zero`() {
        val row = reviewLine("A2", 5.0, 0.0).apply { remove("counted1") }
        assertFalse(countV2VarianceGroups(listOf(row), 1, false).single().complete)
    }

    @Test
    fun `disagreeing counters cannot produce a final balanced bin conclusion`() {
        val row = reviewLine("A1", 5.0, 0.0).put("recountRequired", true)
        val group = countV2VarianceGroups(listOf(row), 1, true).single()
        assertFalse(group.complete)
        assertFalse(group.possibleBinMismatch)
    }

    @Test
    fun `item lot quantity QR becomes an automatic count`() {
        val result = validateCountV2Label(
            BarcodeIntentResolver.resolve("MADDE KODU=AB.00005; LOT NO=A100797; MİKTAR=1,000; BİRİM=ADET")
        )

        assertTrue(result is CountV2LabelResult.Valid)
        val label = (result as CountV2LabelResult.Valid).label
        assertEquals("AB.00005", label.itemNo)
        assertEquals("A100797", label.lotNo)
        assertEquals("ADET", label.unitOfMeasureCode)
        assertEquals(1000.0, label.quantity, 0.0)
    }

    @Test
    fun `V2 rejects item barcode without explicit quantity`() {
        val result = validateCountV2Label(BarcodeIntentResolver.resolve("AB.00005"))

        assertTrue(result is CountV2LabelResult.Invalid)
        assertTrue((result as CountV2LabelResult.Invalid).message.contains("miktar"))
    }

    @Test
    fun `item without quantity becomes a manual entry candidate, labels with quantity do not`() {
        val typed = countV2ManualCandidate(BarcodeIntentResolver.resolve("HM.00115"))
        assertEquals("HM.00115", typed?.itemNo)
        assertEquals("", typed?.lotNo)

        val gs1NoQty = countV2ManualCandidate(BarcodeIntentResolver.resolve("(01)08690000000001(10)H100773"))
        assertEquals("08690000000001", gs1NoQty?.itemNo)
        assertEquals("H100773", gs1NoQty?.lotNo)

        assertTrue(countV2ManualCandidate(BarcodeIntentResolver.resolve("madde kodu=HM.00115 lot=H100773 miktar=5")) == null)
        assertTrue(countV2ManualCandidate(BarcodeIntentResolver.resolve("B-A.A01.11")) == null)
        assertTrue(countV2ManualCandidate(BarcodeIntentResolver.resolve("LP000040")) == null)
    }

    @Test
    fun `rapid duplicate is blocked but intentional later scan is allowed`() {
        assertTrue(isRapidCountV2Duplicate("QR-1", 1_000, "QR-1", 2_000))
        assertFalse(isRapidCountV2Duplicate("QR-1", 1_000, "QR-1", 2_500))
        assertFalse(isRapidCountV2Duplicate("QR-1", 1_000, "QR-2", 1_100))
    }

    @Test
    fun `classic sheet message explains both safe choices without a technical reference`() {
        val message = classicCountSheetV2Message(200)

        assertTrue(message.contains("200 hazır satır"))
        assertTrue(message.contains("Sayım ekranından devam edin"))
        assertTrue(message.contains("Yeni V2 Sayımı Oluştur"))
        assertFalse(message.contains("REF-"))
    }

    /**
     * Mirrors the CountV2Document / CountDocument call-site idiom: the header comes from
     * countSheets('no') without $select, so the flag is either present (new AL) or absent (old AL).
     */
    private fun headerAllowsTerminalPost(headerJson: String): Boolean {
        val header = JSONObject(headerJson)
        return terminalCountPostAllowed(
            hasFlag = header.has("terminalPostAllowed"),
            flag = header.optBoolean("terminalPostAllowed", false),
        )
    }

    @Test
    fun `V2 header without the flag keeps the post button for older AL packages`() {
        assertTrue(headerAllowsTerminalPost("""{"no":"CS00001","status":"InProgress","v2ScanMode":true}"""))
    }

    @Test
    fun `V2 header flag hides the post button when BC setup disables terminal posting`() {
        assertFalse(headerAllowsTerminalPost("""{"no":"CS00001","v2ScanMode":true,"terminalPostAllowed":false}"""))
        assertTrue(headerAllowsTerminalPost("""{"no":"CS00001","v2ScanMode":true,"terminalPostAllowed":true}"""))
    }

    @Test
    fun `V2 post button waits for the header and then follows the terminal posting flag`() {
        assertFalse(countV2PostButtonVisible(headerLoaded = false, terminalPostAllowed = true))
        assertFalse(countV2PostButtonVisible(headerLoaded = true, terminalPostAllowed = false))
        assertTrue(countV2PostButtonVisible(headerLoaded = true, terminalPostAllowed = true))
        // Older AL package: a loaded header without the flag keeps the button.
        assertTrue(
            countV2PostButtonVisible(
                headerLoaded = true,
                terminalPostAllowed = headerAllowsTerminalPost("""{"no":"CS00001","v2ScanMode":true}"""),
            )
        )
        assertFalse(
            countV2PostButtonVisible(
                headerLoaded = true,
                terminalPostAllowed = headerAllowsTerminalPost("""{"no":"CS00001","terminalPostAllowed":false}"""),
            )
        )
    }

    @Test
    fun `BC posting note is operator safe Turkish`() {
        assertTrue(COUNT_POSTED_IN_BC_NOTE.contains("Business Central"))
        assertTrue(COUNT_POSTED_IN_BC_NOTE.contains("stoklara işlenir"))
        assertFalse(COUNT_POSTED_IN_BC_NOTE.contains("REF-"))
    }
}
