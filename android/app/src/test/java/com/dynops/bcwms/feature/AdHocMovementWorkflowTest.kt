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
}
