package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TerminalSelectionTest {
    @Test fun `terminal preferences are isolated by tenant environment and company`() {
        val one = terminalPreferenceScope("tenant", "Production", "company1")
        assertNotEquals(one, terminalPreferenceScope("tenant", "Production", "company2"))
        assertNotEquals(one, terminalPreferenceScope("tenant", "Sandbox", "company1"))
        assertNotEquals(terminalPreferenceScope("a:b", "c", "d"), terminalPreferenceScope("a", "b:c", "d"))
    }

    @Test fun `printer action response preserves both terminal printer fields`() {
        val value = JSONObject().put("terminalCode", "TERMINAL-1")
            .put("labelPrinterCode", "YAZICI-1").put("documentPrinterCode", "PDF-1")
        assertEquals(
            TerminalPrinterSelection("YAZICI-1", "PDF-1"),
            parseTerminalPrinterSelection(JSONObject().put("value", value.toString()).toString(), "TERMINAL-1", true),
        )
    }

    @Test fun `wrong terminal or incomplete response cannot replace cached selection`() {
        assertNull(parseTerminalPrinterSelection(
            """{"code":"TERMINAL-2","labelPrinterCode":"YAZICI-1","documentPrinterCode":""}""",
            "TERMINAL-1", false,
        ))
        assertNull(parseTerminalPrinterSelection(
            """{"code":"TERMINAL-1","labelPrinterCode":"YAZICI-1"}""",
            "TERMINAL-1", false,
        ))
    }
}
