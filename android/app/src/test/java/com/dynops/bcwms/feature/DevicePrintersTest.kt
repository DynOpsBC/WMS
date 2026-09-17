package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class DevicePrintersTest {
    @Test fun `picker cannot assign inactive or wrong-format destinations`() {
        val label = JSONObject().put("active", true).put("format", " zpl ")
        assertTrue(printerSelectionAllowed(label, PRINTER_USAGE_LABEL))
        assertFalse(printerSelectionAllowed(label, PRINTER_USAGE_DOCUMENT))
        label.put("active", false)
        assertFalse(printerSelectionAllowed(label, PRINTER_USAGE_LABEL))
        val pdf = JSONObject().put("active", true).put("format", "PDF")
        assertTrue(printerSelectionAllowed(pdf, PRINTER_USAGE_DOCUMENT))
        assertFalse(printerSelectionAllowed(pdf, PRINTER_USAGE_LABEL))
    }
    @Test fun `operator can find a printer by station location or Windows name`() {
        val printer = JSONObject().put("code", "ZPL-01").put("stationId", "DKC-WMS02")
            .put("locationCode", "DEPO-A").put("printerHandle", "Zebra GK420")
        for (query in listOf(" wms02 ", "depo-a", "zebra", "ZPL-01", "")) assertTrue(printerMatchesSearch(printer, query))
        assertFalse(printerMatchesSearch(printer, "DKC-WMS03"))
    }
}
