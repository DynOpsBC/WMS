package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Kitoko/Element4 #3338: Projeye Çıkış kuralları. */
class ProjectIssueWorkflowTest {
    private val base = ProjectIssueRequest(
        workOrderNo = "SIE-001", itemNo = "m-100", quantity = 3.0, uom = "ADET",
        locationCode = "ana", binCode = "g1-01", lpNo = "lp0001", lotNo = " L1 ", serialNo = "", userId = "TERM1",
    )

    @Test fun `valid request passes`() {
        assertNull(validateProjectIssue(base, binMandatory = true))
    }

    @Test fun `missing work order, location, bin, item and quantity are rejected`() {
        assertTrue(validateProjectIssue(base.copy(workOrderNo = ""), true)!!.contains("iş emri"))
        assertTrue(validateProjectIssue(base.copy(locationCode = ""), true)!!.contains("Lokasyon"))
        assertTrue(validateProjectIssue(base.copy(binCode = ""), true)!!.contains("raf"))
        assertNull(validateProjectIssue(base.copy(binCode = ""), false))
        assertTrue(validateProjectIssue(base.copy(itemNo = " "), true)!!.contains("Ürün"))
        assertTrue(validateProjectIssue(base.copy(quantity = 0.0), true)!!.contains("Miktar"))
        assertTrue(validateProjectIssue(base.copy(quantity = -1.0), true)!!.contains("Miktar"))
        assertTrue(validateProjectIssue(base.copy(quantity = Double.NaN), true)!!.contains("Miktar"))
        assertTrue(validateProjectIssue(base.copy(userId = ""), true)!!.contains("kullanıcı"))
    }

    @Test fun `serial issue must be exactly one`() {
        assertTrue(validateProjectIssue(base.copy(serialNo = "S1", quantity = 2.0), true)!!.contains("Seri"))
        assertNull(validateProjectIssue(base.copy(serialNo = "S1", quantity = 1.0), true))
    }

    @Test fun `body carries normalized fields for issueItem`() {
        val o = JSONObject(projectIssueBody(base))
        assertEquals("M-100", o.getString("itemNo"))
        assertEquals("ANA", o.getString("locationCode"))
        assertEquals("G1-01", o.getString("binCode"))
        assertEquals("LP0001", o.getString("lpNo"))
        assertEquals("L1", o.getString("lotNo"))
        assertEquals(3.0, o.getDouble("quantity"), 0.0)
        assertEquals("ADET", o.getString("unitOfMeasureCode"))
        assertEquals("TERM1", o.getString("userId"))
        assertEquals("", o.getString("variantCode"))
    }

    @Test fun `work orders parse and filter by number, project and text`() {
        val rows = listOf(
            JSONObject("""{"no":"SIE-001","projectNo":"E420251067","projectTaskNo":"210","description":"Montaj","team":"Ekip A","plannedStart":"2026-11-12","plannedFinish":"0001-01-01","status":"Açık","itemLineCount":2}"""),
            JSONObject("""{"no":"SIE-002","projectNo":"T10-PROJECT","projectTaskNo":"220","description":"Kablo","team":"","status":"Açık"}"""),
        ).map(::parseFieldWorkOrder)
        assertEquals("", rows[0].plannedFinish)
        assertEquals(2, rows[0].itemLineCount)
        assertEquals(listOf("SIE-001"), filterFieldWorkOrders(rows, "e42025").map { it.no })
        assertEquals(listOf("SIE-002"), filterFieldWorkOrders(rows, "kablo").map { it.no })
        assertEquals(2, filterFieldWorkOrders(rows, " ").size)
    }

    @Test fun `only item lines are shown with remaining quantity`() {
        val lines = parseFieldWorkOrderItemLines(listOf(
            JSONObject("""{"lineNo":20000,"isItem":true,"no":"M-2","quantity":5,"actualQuantity":7,"unitOfMeasureCode":"ADET"}"""),
            JSONObject("""{"lineNo":10000,"isItem":true,"no":"M-1","quantity":10,"actualQuantity":4,"unitOfMeasureCode":"ADET"}"""),
            JSONObject("""{"lineNo":30000,"isItem":false,"no":"KAYNAK1","quantity":8}"""),
        ))
        assertEquals(listOf("M-1", "M-2"), lines.map { it.itemNo })
        assertEquals(6.0, lines[0].remaining, 0.0)
        assertEquals(0.0, lines[1].remaining, 0.0)
    }

    @Test fun `lines path escapes quotes`() {
        assertEquals("fieldWorkOrderLines?\$filter=workOrderNo eq 'A''B'", fieldWorkOrderLinesPath("A'B"))
    }
}
