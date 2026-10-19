package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TerminalPrinterSelectionTest {
    @Test fun `clear response removes only the requested usage including when both become empty`() {
        for (selection in listOf(TerminalPrinterSelection("", "D2"), TerminalPrinterSelection("Z1", ""), TerminalPrinterSelection("", ""))) {
            val value = JSONObject().put("terminalCode", "T1")
                .put("labelPrinterCode", selection.label).put("documentPrinterCode", selection.document)
            assertEquals(selection, parseTerminalPrinterSelection(
                JSONObject().put("value", value.toString()).toString(), "T1", true))
        }
    }
    @Test fun `save response preserves both printer usages`() {
        val value = """{"terminalCode":"T1","labelPrinterCode":"Z1","documentPrinterCode":"D2"}"""
        assertEquals(TerminalPrinterSelection("Z1", "D2"), parseTerminalPrinterSelection(
            JSONObject().put("value", value).toString(), "T1", true))
    }
    @Test fun `BC can clear or change previously selected printers`() {
        assertEquals(TerminalPrinterSelection("", "D3"), parseTerminalPrinterSelection(
            """{"code":"T1","labelPrinterCode":"","documentPrinterCode":"D3"}""", "T1", false))
    }
    @Test fun `wrong terminal incomplete responses and errors cannot overwrite selection`() {
        for (body in listOf("invalid", "{}", """{"error":"denied"}""",
            """{"code":"T2","labelPrinterCode":"Z1","documentPrinterCode":"D2"}""",
            """{"code":"T1","labelPrinterCode":"Z1"}""")) {
            assertNull(parseTerminalPrinterSelection(body, "T1", false))
            assertNull(parseTerminalPrinterSelection(body, "T1", true))
        }
    }
}
