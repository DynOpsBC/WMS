package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class LpListOrderTest {
    private fun lp(no: String) = JSONObject().put("no", no)

    @Test
    fun `ascending and descending by LP number`() {
        val rows = listOf(lp("LP001774"), lp("LP000001"), lp("LP000010"), lp("LP000002"))
        assertEquals(listOf("LP000001", "LP000002", "LP000010", "LP001774"), lpListOrder(rows, false).map { it.optString("no") })
        assertEquals(listOf("LP001774", "LP000010", "LP000002", "LP000001"), lpListOrder(rows, true).map { it.optString("no") })
    }
}
