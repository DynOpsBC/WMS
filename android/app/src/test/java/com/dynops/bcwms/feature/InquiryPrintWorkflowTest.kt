package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Test

class InquiryPrintWorkflowTest {
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
