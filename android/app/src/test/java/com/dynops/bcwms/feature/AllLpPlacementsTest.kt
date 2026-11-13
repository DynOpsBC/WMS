package com.dynops.bcwms.feature

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AllLpPlacementsTest {
    @Test fun `all LP positions load beyond twenty five and preserve zones`() = runBlocking {
        val nos = (1..51).map { "LP$it" }
        var batches = 0
        val result = loadAllLpPlacements(nos) { path ->
            if (path.startsWith("licensePlates")) {
                batches++
                nos.filter { path.contains("no eq '$it'") }.map {
                    JSONObject().put("no", it).put("locationCode", "LOC").put("binCode", "BIN")
                }
            } else listOf(JSONObject().put("locationCode", "LOC").put("code", "BIN").put("zoneCode", "ZONE"))
        }
        assertEquals(3, batches)
        assertEquals(51, result.size)
        assertEquals(LpPlacement("LOC", "BIN", "ZONE"), result["LP51"])
    }
    @Test fun `failed headers do not invent a location`() = runBlocking {
        assertTrue(loadAllLpPlacements(listOf("LP1")) { null }.isEmpty())
    }
}
