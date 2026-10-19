package com.dynops.bcwms.feature

import org.junit.Assert.*
import org.junit.Test

class ActiveLabelPrinterTest {
    @Test fun `header shows the exact agent name instead of printer ID description or host`() {
        assertEquals("ZDesigner ZD230-203dpi ZPL", activePrinterAgentName(
            """{"code":"P01","printerHandle":"ZDesigner ZD230-203dpi ZPL","description":"Depo etiketi","hostname":"192.168.1.10"}""", "P01"))
    }

    @Test fun `missing names invalid responses and other printers never become the displayed name`() {
        for (body in listOf("invalid", "{}", """{"code":"OTHER","printerHandle":"Wrong printer"}""",
            """{"code":"P01","description":"Not the agent name","printerHandle":""}""")) {
            assertNull(activePrinterAgentName(body, "P01"))
        }
    }

    @Test fun `printer key is escaped for the company scoped OData request`() {
        assertEquals("printers('P01')", activePrinterPath("P01"))
        assertEquals("printers('A%27%27%2FB%20C')", activePrinterPath("A'/B C"))
    }
}
