package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EmptyLpWorkflowTest {
    private fun bin(code: String, location: String) = JSONObject().put("code", code).put("locationCode", location)

    @Test
    fun `scanned bin gives its location and exact code`() {
        val found = resolveEmptyLpBin(listOf(bin("ÜR.0001", "DKC WMS")), " ür.0001 ")
        assertEquals(EmptyLpBin.Found("ÜR.0001", "DKC WMS"), found)
    }

    @Test
    fun `unknown or missing bin is refused`() {
        assertTrue(resolveEmptyLpBin(emptyList(), "XX") is EmptyLpBin.Problem)
        assertTrue(resolveEmptyLpBin(listOf(bin("A", "L1")), "") is EmptyLpBin.Problem)
    }

    @Test
    fun `bin code used in two locations is refused`() {
        val result = resolveEmptyLpBin(listOf(bin("A1", "DKC WMS"), bin("A1", "MİLLİ DEPO")), "A1")
        assertTrue(result is EmptyLpBin.Problem)
    }

    @Test
    fun `request carries template location and bin`() {
        val body = JSONObject(emptyLpRequestBody(" CARTON-M ", EmptyLpBin.Found("MK.0001", "DKC WMS")))
        assertEquals("CARTON-M", body.getString("templateCode"))
        assertEquals("DKC WMS", body.getString("locationCode"))
        assertEquals("MK.0001", body.getString("binCode"))
    }

    @Test
    fun `new lp number is read from the response`() {
        assertEquals("LP000123", createdLpNo("""{"no":"LP000123","status":"Open"}"""))
        assertEquals("", createdLpNo("not json"))
    }
}
