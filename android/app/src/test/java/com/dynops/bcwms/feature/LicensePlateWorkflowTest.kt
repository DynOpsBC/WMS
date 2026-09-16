package com.dynops.bcwms.feature

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class LicensePlateWorkflowTest {
    @Test
    fun `bulk print uses small ordered batches`() {
        val lpNos = listOf("LP1", "LP2", "LP3", "LP4", "LP5", "LP6", "LP7")

        assertEquals(
            listOf(
                listOf("LP1", "LP2", "LP3"),
                listOf("LP4", "LP5", "LP6"),
                listOf("LP7"),
            ),
            bulkLpPrintBatches(lpNos),
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun `bulk print rejects an invalid concurrency limit`() {
        bulkLpPrintBatches(listOf("LP1"), maxParallel = 0)
    }

    @Test
    fun `bulk print sends empty LP to the ZPL LP label action`() {
        assertEquals("printLabel", bulkLpPrintAction(0))
        assertEquals("printLabel", bulkLpPrintAction(-1))
        assertEquals("printPalletLabels", bulkLpPrintAction(1))
        assertEquals("printPalletLabels", bulkLpPrintAction(4))
    }

    @Test
    fun `bulk print follows the device printer selection`() {
        assertEquals(LpPrintRoute("printLabel", "ZPL01"), bulkLpPrintRoute(0, "ZPL01", "PDF01"))
        // Filled LPs are MTE: the field's ZPL label printer first. BC renders the
        // approved RDLC PDF only when the resolved printer is a PDF printer.
        assertEquals(LpPrintRoute("printPalletLabels", "ZPL01"), bulkLpPrintRoute(2, "ZPL01", ""))
        assertEquals(LpPrintRoute("printPalletLabels", "ZPL01"), bulkLpPrintRoute(2, "ZPL01", "PDF01"))
        // A PDF QR document is suitable only for an empty carrier.
        assertEquals(LpPrintRoute("printDocument", "PDF01"), bulkLpPrintRoute(0, "", "PDF01"))
        assertEquals(LpPrintRoute("printPalletLabels", "PDF01"), bulkLpPrintRoute(3, " ", "PDF01"))
        // Nothing selected on the device: let BC's device printer mapping decide.
        assertEquals(LpPrintRoute("printLabel", ""), bulkLpPrintRoute(0, "", ""))
        assertEquals(LpPrintRoute("printPalletLabels", ""), bulkLpPrintRoute(2, "", ""))
    }

    @Test
    fun `MTE dates are normalised to the XML format`() {
        assertEquals("", normalizeMteDate("  "))
        assertEquals("2026-09-16", normalizeMteDate("16.09.2026"))
        assertEquals("2026-09-16", normalizeMteDate("16/9/2026"))
        assertEquals("2026-09-16", normalizeMteDate("2026-09-16"))
        assertEquals(null, normalizeMteDate("31.13.2026"))
        assertEquals(null, normalizeMteDate("dün"))
    }

    @Test
    fun `MTE options json carries only filled fields`() {
        val json = org.json.JSONObject(mteOptionsJson(MteOptions(inspectorEmployeeNo = " E001 ", qcApprovalDate = "2026-09-16", documentNo = "DOK-1")))
        assertEquals("E001", json.getString("inspectorEmployeeNo"))
        assertEquals("2026-09-16", json.getString("qcApprovalDate"))
        assertEquals("DOK-1", json.getString("documentNo"))
        assertFalse(json.has("supplierLotNo"))
        assertEquals("{}", mteOptionsJson(MteOptions()))
    }

    @Test
    fun `customer MTE report prefers the document printer`() {
        assertEquals("PDF01", mteReportPrinterCode("ZPL01", " PDF01 "))
        assertEquals("ZPL01", mteReportPrinterCode("ZPL01", ""))
        assertEquals("", mteReportPrinterCode("", ""))
    }

    @Test
    fun `MTE cannot be requested for an unloaded empty or pending receipt LP`() {
        assertTrue(canPrintMte(true, 2, ""))
        assertFalse(canPrintMte(false, 2, ""))
        assertFalse(canPrintMte(true, 0, ""))
        assertFalse(canPrintMte(true, 2, "REC001"))
    }

    @Test
    fun `single MTE and filled LP batch prefer the label printer and fall back to the document printer`() {
        assertEquals("ZPL01", mtePrinterCode(" ZPL01 ", "PDF01"))
        assertEquals("PDF01", mtePrinterCode(" ", " PDF01 "))
        assertEquals("", mtePrinterCode("", ""))
        assertEquals(LpPrintRoute("printPalletLabels", "ZPL01"), mtePrintRoute(" ZPL01 ", "PDF01"))
        assertEquals(LpPrintRoute("printPalletLabels", "PDF01"), mtePrintRoute("", " PDF01 "))
        assertEquals(mtePrintRoute(" ZPL01 ", "PDF01"), bulkLpPrintRoute(2, " ZPL01 ", "PDF01"))
        assertEquals(mtePrintRoute("", "PDF01"), bulkLpPrintRoute(2, "", "PDF01"))
    }

    @Test
    fun `empty open or unbuilt LP can be deleted`() {
        assertTrue(canDeleteLicensePlate("Open", 0))
        assertTrue(canDeleteLicensePlate("Unbuilt", 0))
        assertFalse(canDeleteLicensePlate("", 0))
    }

    @Test
    fun `LP with contents or operational status cannot be deleted`() {
        assertFalse(canDeleteLicensePlate("Open", 1))
        assertFalse(canDeleteLicensePlate("Unbuilt", 1))
        assertFalse(canDeleteLicensePlate("Built", 0))
        assertFalse(canDeleteLicensePlate("Assigned", 0))
    }

    @Test
    fun `serial tracked LP line accepts exactly one base unit`() {
        assertTrue(validLpTrackingQuantity(serialTrackingRequired = true, quantity = 1.0))
        assertFalse(validLpTrackingQuantity(serialTrackingRequired = true, quantity = 2.0))
        assertTrue(validLpTrackingQuantity(serialTrackingRequired = false, quantity = 25.0))
    }

    @Test
    fun `source bin must belong to the LP location`() {
        assertTrue(sourceBinBelongsToLpLocation("MERKEZ", listOf("MERKEZ")))
        assertFalse(sourceBinBelongsToLpLocation("MERKEZ", listOf("FABRIKA", "TRANSIT")))
    }

    @Test
    fun `source bin lookup fails closed until every OData page is loaded`() {
        assertFalse(sourceBinLookupAllowsMove(false, "MERKEZ", listOf("MERKEZ")))
        assertTrue(sourceBinLookupAllowsMove(true, "MERKEZ", listOf("MERKEZ")))
    }

    @Test
    fun `destroyed LP is excluded from active bin contents`() {
        assertTrue(activeLicensePlateStatus("Open"))
        assertTrue(activeLicensePlateStatus("Built"))
        assertFalse(activeLicensePlateStatus("Unbuilt"))
        assertFalse(activeLicensePlateStatus("Used"))
        assertFalse(activeLicensePlateStatus(""))
    }

    @Test
    fun `LP UOM choices are valid unique configured values with base first`() {
        assertEquals(
            listOf("ADET", "KOLI", "PALET"),
            lpUomOptions("ADET", listOf("ADET", "KOLI"), listOf("koli", "PALET")),
        )
    }

    @Test
    fun `lot is required when tracking stock or scanned lot exists`() {
        assertTrue(lpLotIsRequired(true, 0, ""))
        assertTrue(lpLotIsRequired(false, 2, ""))
        assertTrue(lpLotIsRequired(false, 0, "LOT-1"))
        assertFalse(lpLotIsRequired(false, 0, ""))
    }

    @Test
    fun `only an open LP can be edited and stopped`() {
        assertTrue(canEditLicensePlate("Open"))
        assertFalse(canEditLicensePlate("Built"))
        assertFalse(canEditLicensePlate("Assigned"))
        assertFalse(canEditLicensePlate(""))
    }

    @Test
    fun `empty unlocated LP can receive its first bin`() {
        assertTrue(canAssignLicensePlateBin("Open", 0, ""))
        assertTrue(canAssignLicensePlateBin("Built", 0, ""))
        assertFalse(canAssignLicensePlateBin("Open", 1, ""))
        assertFalse(canAssignLicensePlateBin("Open", 0, "A-01"))
        assertFalse(canAssignLicensePlateBin("Assigned", 0, ""))
    }

    @Test
    fun `legacy initial bin fallback only accepts missing bin validation`() {
        assertTrue(shouldPatchInitialBinForLegacyServer(400, "Bin Code must have a value in LP Header"))
        assertTrue(shouldPatchInitialBinForLegacyServer(422, "Bin Code zorunludur"))
        assertFalse(shouldPatchInitialBinForLegacyServer(500, "Bin Code must have a value"))
        assertFalse(shouldPatchInitialBinForLegacyServer(400, "Target bin does not exist"))
    }

    @Test
    fun `transfer and partial use require a built LP with contents`() {
        assertTrue(canTransferLicensePlate("Built", 1))
        assertTrue(canPartiallyUseLicensePlate("Built", 1))
        assertFalse(canTransferLicensePlate("Open", 1))
        assertFalse(canPartiallyUseLicensePlate("Built", 0))
    }

    @Test
    fun `partial use validates selected line and quantity bounds`() {
        assertTrue(validPartialUseInput(quantity = 3.0, lineNo = 10000, maximumQuantity = 5.0))
        assertFalse(validPartialUseInput(quantity = 0.0, lineNo = 10000, maximumQuantity = 5.0))
        assertFalse(validPartialUseInput(quantity = 6.0, lineNo = 10000, maximumQuantity = 5.0))
        assertFalse(validPartialUseInput(quantity = 3.0, lineNo = null, maximumQuantity = 5.0))
    }

    @Test
    fun `partial use sends Business Central enum values`() {
        assertEquals(
            listOf("CreateNewLP", "RemoveExcess", "RemoveUsedPortion"),
            lpPartialActions.map { it.apiValue },
        )
    }

    @Test
    fun `printMte falls back to the legacy action only when BC does not know it`() {
        assertTrue(mteFallbackToLegacy(404, ""))
        assertTrue(mteFallbackToLegacy(400, "Action 'Microsoft.NAV.printMte' not found"))
        assertTrue(mteFallbackToLegacy(400, "No HTTP resource was found that matches the request URI"))
        assertFalse(mteFallbackToLegacy(400, "Yazıcı bulunamadı"))
        assertFalse(mteFallbackToLegacy(500, "No WMS bridge printer is mapped for LP label printing"))
    }

    @Test
    fun `legacy MTE body keeps printer and copies and drops the options`() {
        val body = legacyMteBody("""{"printerId":"ZD230","copies":2,"optionsJson":"{\"tedarikciLotu\":\"X\"}"}""")
        val o = org.json.JSONObject(body)
        assertEquals("ZD230", o.getString("printerId"))
        assertEquals(2, o.getInt("copies"))
        assertFalse(o.has("optionsJson"))
        assertEquals(1, org.json.JSONObject(legacyMteBody("not json")).getInt("copies"))
    }
}
