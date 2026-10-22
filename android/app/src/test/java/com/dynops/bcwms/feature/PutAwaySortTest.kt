package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class PutAwaySortTest {
    private fun doc(no: String, user: String) = JSONObject().put("no", no).put("assignedUserId", user)

    @Test
    fun `my put-aways come first, then unassigned, then others`() {
        val rows = listOf(doc("PU5", "ALI"), doc("PU4", ""), doc("PU3", "ayse"), doc("PU2", "VELI"), doc("PU1", "AYSE"))
        assertEquals(listOf("PU3", "PU1", "PU4", "PU5", "PU2"), sortPutAwaysForUser(rows, "AYSE").map { it.optString("no") })
        assertEquals(listOf("PU4", "PU5", "PU3", "PU2", "PU1"), sortPutAwaysForUser(rows, "").map { it.optString("no") })
    }
}
