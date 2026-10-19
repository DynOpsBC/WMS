package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiptLpCloseTest {
    @Test
    fun closingAReceiptPalletNeverPrintsAnEmptyLabel() {
        val body = JSONObject(receiptStopLpBody("LP000700"))
        assertEquals("LP000700", body.getString("lpNo"))
        assertFalse(body.getBoolean("printLabel"))
    }

    @Test
    fun closedStatusTellsTheOperatorTheNextSteps() {
        val text = receiptLpClosedStatus("LP000700")
        assertTrue(text.startsWith("TAMAM:"))
        assertTrue(text.contains("LP000700"))
        assertTrue(text.contains("Naklet"))
    }

    @Test
    fun onlyTouchedReadyLinesWithoutAPalletAwaitAnLp() {
        val lines = listOf(
            JSONObject("""{"lineNo":10000,"qtyToReceive":20,"licensePlateNo":""}"""),
            JSONObject("""{"lineNo":20000,"qtyToReceive":8,"licensePlateNo":"LP000700"}"""),
            JSONObject("""{"lineNo":30000,"qtyToReceive":5,"licensePlateNo":"","bulkLpCount":2}"""),
            JSONObject("""{"lineNo":40000,"qtyToReceive":50,"licensePlateNo":""}"""),
            JSONObject("""{"lineNo":50000,"qtyToReceive":0,"licensePlateNo":""}"""),
        )
        // 40000: BC'nin önceden doldurduğu, operatörün dokunmadığı satır.
        assertEquals(listOf(10000), receiptLinesAwaitingLp(lines, setOf(10000, 20000, 30000, 50000)))
    }

    @Test
    fun attachBodyCarriesTheLineList() {
        val body = JSONObject(receiptAttachLinesBody("LP000701", listOf(10000, 20000)))
        assertEquals("LP000701", body.getString("lpNo"))
        assertEquals("[10000,20000]", body.getString("lineNosJson"))
    }
}
