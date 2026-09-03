package com.dynops.bcwms.feature

import com.dynops.bcwms.scanner.BarcodeIntentResolver
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CountV2WorkflowTest {
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
