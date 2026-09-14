package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Test

class InquiryPrintWorkflowTest {
    @Test fun `inactive printers are not described as ready`() {
        val inactive = org.json.JSONObject().put("active", false)
        val active = org.json.JSONObject().put("active", true)
        org.junit.Assert.assertTrue(printerReadinessMessage(listOf(inactive)).startsWith("UYARI:"))
        org.junit.Assert.assertTrue(printerReadinessMessage(listOf(inactive, active)).contains("1 aktif"))
        org.junit.Assert.assertTrue(printerReadinessMessage(listOf(inactive, active)).contains("1 pasif"))
    }
    @Test fun `inactive selected label falls back to document`() {
        assertEquals("PDF01", inquiryLabelPrinter("ZPL01", "PDF01", labelAvailable = false))
    }

    @Test fun `unavailable label is not reused without a document printer`() {
        assertEquals("", inquiryLabelPrinter("ZPL01", "", labelAvailable = false))
    }
    @Test fun `label printer takes priority when both are selected`() {
        assertEquals("ZPL01", inquiryLabelPrinter("ZPL01", "PDF01"))
    }

    @Test fun `document printer is used when no label printer is selected`() {
        assertEquals("PDF01", inquiryLabelPrinter("", "PDF01"))
    }

    @Test fun `empty selections preserve BC mapping resolution`() {
        assertEquals("", inquiryLabelPrinter("", ""))
    }
}
