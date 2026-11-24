package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DkcOutputPallet1124Test {
    @Test
    fun palletizePathEscapesOrderNo() {
        assertEquals(
            "productionOrderLines(status='Released',prodOrderNo='UR''1',lineNo=10000)/Microsoft.NAV.palletizeOutput",
            palletizeOutputPath("UR'1", 10000),
        )
        val body = JSONObject(palletizeOutputBody(" PALLET ", ""))
        assertEquals("PALLET", body.getString("templateCode"))
        assertEquals("", body.getString("palletLpNo"))
    }

    @Test
    fun defaultTemplatePrefersPallet() {
        val t = listOf(JSONObject().put("code", "KUTU"), JSONObject().put("code", "P1").put("description", "Euro Palet"))
        assertEquals("P1", defaultPalletTemplate(t))
        assertEquals("KUTU", defaultPalletTemplate(t.take(1)))
        assertEquals("", defaultPalletTemplate(emptyList()))
    }

    @Test
    fun parsesBoundActionResult() {
        val inner = """{"palletLpNo":"LP000456","binCode":"ÜR.0003","boxCount":2,"totalBoxCount":5,"boxes":["LP1","LP2"]}"""
        val r = parsePalletizeResult(JSONObject().put("value", inner).toString())!!
        assertEquals("LP000456", r.palletLpNo)
        assertEquals(2, r.boxCount)
        assertEquals(5, r.totalBoxCount)
        assertEquals("ÜR.0003", r.binCode)
        assertNull(parsePalletizeResult("""{"value":"{}"}"""))
        assertNull(parsePalletizeResult("not json"))
    }
}
