package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TerminalPrinterBarTest {
    @Test fun `binding shows the agent display name and the reported state`() {
        val row = JSONObject().put("code", "P0123").put("description", "Mal Kabul Zebra")
            .put("agentStatus", "Online").put("lastSeenAt", "2026-09-17T14:00:00Z")
        val binding = printerBindingFrom("P0123", row)
        assertTrue(binding.isSet)
        assertEquals("Mal Kabul Zebra", binding.title)
        assertEquals(true, binding.online)
        assertTrue(binding.lastSeen.isNotBlank())
    }

    @Test fun `binding falls back to the code and unknown state`() {
        assertEquals("P0123", printerBindingFrom("P0123", null).title)
        assertNull(printerBindingFrom("P0123", null).online)
        assertEquals(false, printerBindingFrom("P0123", JSONObject().put("agentStatus", "Offline")).online)
        assertEquals("P0123", printerBindingFrom("P0123", JSONObject().put("description", "p0123")).title)
        assertFalse(printerBindingFrom("", null).isSet)
    }
}
