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

    @org.junit.Test fun `box list parses and selection body joins chosen boxes`() {
        val body = org.json.JSONObject().put("value", "[{\"lpNo\":\"LP000471\",\"binCode\":\"ÜR.0003\",\"quantity\":100,\"unit\":\"ADET\",\"lotNo\":\"L1\"},{\"lpNo\":\"LP000472\",\"binCode\":\"ÜR.0003\",\"quantity\":12.5,\"unit\":\"KG\",\"lotNo\":\"\"}]").toString()
        val boxes = parseOutputBoxes(body)!!
        org.junit.Assert.assertEquals(listOf("LP000471", "LP000472"), boxes.map { it.lpNo })
        org.junit.Assert.assertEquals("100", outputBoxQtyText(boxes[0].quantity))
        org.junit.Assert.assertEquals("12,5", outputBoxQtyText(boxes[1].quantity))
        org.junit.Assert.assertEquals(emptyList<OutputBox>(), parseOutputBoxes("{\"value\":\"[]\"}"))
        org.junit.Assert.assertNull(parseOutputBoxes("bozuk"))
        val sent = org.json.JSONObject(palletizeBoxesBody("PALET", "", listOf("LP000471", "LP000473")))
        org.junit.Assert.assertEquals("LP000471,LP000473", sent.getString("boxLpNos"))
        org.junit.Assert.assertEquals("PALET", sent.getString("templateCode"))
        org.junit.Assert.assertTrue(outputLinePath("UR'1", 10000, "listOutputBoxes").endsWith("prodOrderNo='UR''1',lineNo=10000)/Microsoft.NAV.listOutputBoxes"))
    }
    @org.junit.Test fun `template kind word follows code or description`() {
        org.junit.Assert.assertEquals("Kutu", lpKindWord("KUTU", "Üretim kutusu"))
        org.junit.Assert.assertEquals("Palet", lpKindWord("PALLET-EUR", "Euro palet"))
        org.junit.Assert.assertEquals("Koli", lpKindWord("K1", "Koli 40x60"))
        org.junit.Assert.assertEquals("LP", lpKindWord("STD", "Standart"))
    }
}
