package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MteOperatorRequestTest {
    @Test fun `receipt reprint and bulk LP reprint carry the PIN name`() {
        val action = requireNotNull(mteOperatorAction("licensePlates", "printPalletLabels"))
        val request = mteOperatorRequest(action, """{"printerId":"ZPL01","copies":2}""", " Bülent Abatay ")
        assertEquals("printMteForOperator", request.action)
        val body = JSONObject(request.body)
        assertEquals("ZPL01", body.getString("printerId"))
        assertEquals(2, body.getInt("copies"))
        val options = JSONObject(body.getString("optionsJson"))
        assertEquals("Bülent Abatay", options.getString("operatorDisplayName"))
        assertFalse(options.has("inspectorEmployeeNo"))
    }

    @Test fun `bulk creation retains idempotency key and quantity plan`() {
        val body = JSONObject().put("requestId", "same-request").put("lpCount", 3)
            .put("quantityPerLp", 20).put("quantityLastLp", 5).put("printLabels", true)
        val action = requireNotNull(mteOperatorAction("itemLedgerEntries", "createLicensePlatesFromPlanIdempotent"))
        val result = JSONObject(mteOperatorRequest(action, body.toString(), "Merve").body)
        for (key in body.keys()) assertEquals(body.get(key), result.get(key))
        assertEquals("createLicensePlatesFromPlanIdempotentWithMte", action)
    }

    @Test fun `receipt and completion keep original print switches`() {
        for ((entity, action) in listOf("receipts" to "postAndCloseLP", "licensePlates" to "stopToPrinter")) {
            val target = requireNotNull(mteOperatorAction(entity, action))
            assertEquals("${action}WithMte", target)
            val body = JSONObject(mteOperatorRequest(target, """{"printLabel":false,"print":false}""", "Merve").body)
            assertFalse(body.getBoolean("printLabel"))
            assertFalse(body.getBoolean("print"))
        }
    }

    @Test fun `manual inspector and quality fields are preserved`() {
        val options = JSONObject().put("inspectorEmployeeNo", "EMP02").put("qcEmployeeNo", "QC01")
        val body = JSONObject().put("optionsJson", options.toString())
        val result = JSONObject(mteOperatorRequest("printMte", body.toString(), "Merve").body)
        assertEquals(options.toString(), result.getString("optionsJson"))
    }

    @Test fun `missing PIN identity cannot generate service-account label`() {
        assertTrue(runCatching { mteOperatorRequest("printMte", "{}", "  ") }.isFailure)
    }

    @Test fun `unrelated operations and existing explicit MTE flow are unchanged`() {
        assertNull(mteOperatorAction("licensePlates", "printLabel"))
        assertNull(mteOperatorAction("licensePlates", "printDocument"))
        assertNull(mteOperatorAction("licensePlates", "printMte"))
        assertNull(mteOperatorAction("receipts", "assignToUser"))
    }
}
