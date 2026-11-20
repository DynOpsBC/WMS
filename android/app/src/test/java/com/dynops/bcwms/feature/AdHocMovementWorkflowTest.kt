package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdHocMovementWorkflowTest {
    @Test
    fun `LP code in Product mode is routed to atomic LP workflow`() {
        val decision = decideAdHocProductInput("LP000021")

        assertEquals(AdHocProductInputRoute.LicensePlateWorkflow, decision.route)
        assertEquals("LP000021", decision.value)
    }

    @Test
    fun `SSCC in Product mode is routed to atomic LP workflow`() {
        val decision = decideAdHocProductInput("001234567890123456")

        assertEquals(AdHocProductInputRoute.LicensePlateWorkflow, decision.route)
        assertEquals("001234567890123456", decision.value)
    }

    @Test
    fun `item barcode remains on movementOps product contract`() {
        val decision = decideAdHocProductInput("HM.00042")

        assertEquals(AdHocProductInputRoute.ProductMutation, decision.route)
        assertEquals("HM.00042", decision.value)
    }

    @Test
    fun `non item and non LP barcode cannot create product mutation`() {
        val decision = decideAdHocProductInput("B-A01-11")

        assertEquals(AdHocProductInputRoute.Invalid, decision.route)
    }

    @Test fun `project code routes product moves to adHocProject`() {
        assertEquals("adHoc", adHocProductAction("", ""))
        assertEquals("adHocLot", adHocProductAction("L1", ""))
        assertEquals("adHocProject", adHocProductAction("", "PR00010"))
        assertEquals("adHocProject", adHocProductAction("L1", "PR00010"))
        assertEquals("PR00010", normalizeProjectCode("  pr00010 "))
        assertTrue(adHocProjectEnabled("kitoko"))
        assertFalse(adHocProjectEnabled("bade"))
    }

    @Test
    fun projectPickerSearchesNumberNameAndCustomer() {
        val p = org.json.JSONObject().put("no", "PR00010").put("description", "Rafineri bakım hattı").put("billToName", "TÜPRAŞ")
        assertTrue(projectMatches(p, ""))
        assertTrue(projectMatches(p, "pr0001"))
        assertTrue(projectMatches(p, "BAKIM"))
        assertTrue(projectMatches(p, "tüpraş"))
        assertFalse(projectMatches(p, "montaj"))
    }

    @Test
    fun salesOrderRoutesAndSearchAreScopedToElement4() {
        assertTrue(adHocSalesOrderEnabled("Element 4 Dizayn Müh. End. A.Ş"))
        assertTrue(adHocSalesOrderEnabled("ELEMENT4-TR-DEMO-V1"))
        assertFalse(adHocSalesOrderEnabled("Kitoko Aydınlatma ve Müh. A.Ş."))
        assertEquals("adHocSalesOrder", adHocProductAction("", "E4TEST.R1", useSalesOrder = true))
        assertEquals("adHocSalesOrder", adHocProductAction("L1", "E4TEST.R1", useSalesOrder = true))
        assertEquals("adHocLot", adHocProductAction("L1", "", useSalesOrder = true))
        assertEquals("moveToBinSalesOrder", adHocLpBinAction("E4TEST.R1", useSalesOrder = true))
        assertEquals("moveToBinProject", adHocLpBinAction("PR001", useSalesOrder = false))
        assertEquals("moveToBin", adHocLpBinAction("", useSalesOrder = true))
        val order = org.json.JSONObject().put("no", "E4TEST.R1").put("customerName", "Deneme Müşterisi")
        assertTrue(projectMatches(order, "test.r1"))
        assertTrue(projectMatches(order, "müşterisi"))
        assertFalse(projectMatches(order, "PR001"))
    }

    @Test
    fun projectMoveSummaryShowsQuantityAndRoute() {
        val e = org.json.JSONObject().put("quantity", 12.0).put("unitOfMeasureCode", "ADET").put("fromBinCode", "A-01-01").put("toBinCode", "MONTAJ-1")
        assertEquals("12 ADET · A-01-01 → MONTAJ-1", projectMoveSummary(e))
        assertEquals("2.5 · — → KAYNAK", projectMoveSummary(org.json.JSONObject().put("quantity", 2.5).put("toBinCode", "KAYNAK")))
    }

    @Test
    fun projectMoveTimeIsShownInDeviceTime() {
        val istanbul = java.time.ZoneId.of("Europe/Istanbul")
        assertEquals("18.11.2026 16:05", projectMoveTimeText("2026-11-18T13:05:00Z", istanbul))
        assertEquals("", projectMoveTimeText("", istanbul))
    }
}
