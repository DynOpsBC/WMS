package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MteOperatorTest {
    @Test fun `clearing extra fields preserves a manually selected inspector`() {
        assertEquals("EMP02", mteOptionsWithoutExtraFields("EMP02").inspectorEmployeeNo)
        val empty = mteOptionsWithoutExtraFields("")
        assertEquals("Merve", mteOptionsWithOperator(empty, "Merve", emptyList(), false).inspectorEmployeeNo)
    }

    @Test fun `manual inspector wins over the PIN operator`() {
        val options = MteOptions("EMP02", "LOT1", "QC01", "2026-09-18")
        assertEquals(options, mteOptionsWithOperator(options, "Merve Demirci", emptyList(), false))
        assertEquals(options, mteOptionsWithOperator(options, "Merve Demirci", emptyList(), true))
    }

    @Test fun `empty and whitespace selections print the PIN operator on ZPL`() {
        for (inspector in listOf("", "   ")) {
            val result = mteOptionsWithOperator(MteOptions(inspector), " Merve Demirci ", emptyList(), false)
            assertEquals("Merve Demirci", JSONObject(mteOptionsJson(result)).getString("inspectorEmployeeNo"))
        }
    }

    @Test fun `blank all fields still includes the operator without filling quality approval`() {
        val result = JSONObject(mteOptionsJson(mteOptionsWithOperator(MteOptions(), "Ayşe Yılmaz", emptyList(), false)))
        assertEquals("Ayşe Yılmaz", result.getString("inspectorEmployeeNo"))
        assertFalse(result.has("qcEmployeeNo"))
        assertFalse(result.has("qcApprovalDate"))
    }

    @Test fun `employee mapping uses the active company list only`() {
        val options = MteOptions(supplierLotNo = "LOT1")
        val firstCompany = mteOptionsWithOperator(options, "Merve", listOf("A01" to "Merve"), true)
        val secondCompany = mteOptionsWithOperator(options, "Merve", listOf("B09" to "Merve"), true)
        assertEquals("A01", firstCompany.inspectorEmployeeNo)
        assertEquals("B09", secondCompany.inspectorEmployeeNo)
        assertEquals("LOT1", secondCompany.supplierLotNo)
    }

    @Test fun `PDF requires a unique employee mapping instead of printing a service account or blank`() {
        for (employees in listOf(emptyList(), listOf("A01" to "Merve", "A02" to "Merve"))) {
            assertTrue(runCatching { mteOptionsWithOperator(MteOptions(), "Merve", employees, true) }.isFailure)
        }
    }

    @Test fun `missing PIN identity cannot fall back to the service account`() {
        assertTrue(runCatching { mteOptionsWithOperator(MteOptions(), "", emptyList(), false) }.isFailure)
    }
}
