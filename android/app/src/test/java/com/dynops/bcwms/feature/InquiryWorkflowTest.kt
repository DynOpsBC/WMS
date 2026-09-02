package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class InquiryWorkflowTest {
    @Test
    fun `queried LP summary combines quantity and distinct lots`() {
        val lines = listOf(
            JSONObject().put("lpNo", "LP000018").put("quantity", 5000).put("lotNo", "A101296"),
            JSONObject().put("lpNo", "lp000018").put("quantity", 880).put("lotNo", "A101296"),
            JSONObject().put("lpNo", "LP000019").put("quantity", 25).put("lotNo", "OTHER"),
        )

        val result = queriedLpSummary(" lp000018 ", lines)

        assertEquals("LP000018", result?.lpNo)
        assertEquals(5880.0, result?.quantity ?: 0.0, 0.0)
        assertEquals(listOf("A101296"), result?.lotNos)
    }

    @Test
    fun `queried LP summary keeps multiple lots`() {
        val lines = listOf(
            JSONObject().put("lpNo", "LP1").put("quantity", 10).put("lotNo", "LOT-A"),
            JSONObject().put("lpNo", "LP1").put("quantity", 20).put("lotNo", "LOT-B"),
        )

        assertEquals(listOf("LOT-A", "LOT-B"), queriedLpSummary("LP1", lines)?.lotNos)
    }

    @Test
    fun `queried LP summary is absent for an item query`() {
        val lines = listOf(JSONObject().put("lpNo", "LP1").put("quantity", 10))

        assertNull(queriedLpSummary("ITEM-1", lines))
    }
}
