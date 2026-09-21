package com.dynops.bcwms.feature

import com.dynops.bcwms.BcApi
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ProductionPickFlowTest {
    private fun created() = BcApi.ApiResult(true, 200, """{"value":"PICK-1"}""")
    private fun header(owner: String = "MERVE", source: String = "PROD-1", no: String = "PICK-1") =
        BcApi.ApiResult(true, 200, JSONObject().put("no", no).put("sourceNo", source).put("assignedUserId", owner).toString())

    @Test fun `ready LP request preserves scanned pallet and terminal operator`() = runBlocking {
        val events = mutableListOf<String>()
        val result = createProductionPickForOperator("PROD-1", " MERVE ", " LP-3 ", { action, body ->
            events += action
            assertEquals("MERVE", JSONObject(body).getString("userId"))
            assertEquals("LP-3", JSONObject(body).getString("lpNo"))
            created()
        }, { pick ->
            assertEquals("PICK-1", pick)
            events += "read"
            header(owner = "merve")
        })
        assertTrue(result.ok)
        assertEquals(listOf("createPickFromLpFor", "read"), events)
    }

    @Test fun `standard production pick also carries terminal operator`() = runBlocking {
        val result = createProductionPickForOperator("PROD-1", "MERVE", send = { action, body ->
            assertEquals("createPickFor", action)
            assertFalse(JSONObject(body).has("lpNo"))
            created()
        }, readHeader = { header() })
        assertTrue(result.ok)
    }

    @Test fun `missing operator or explicit blank LP never mutates`() = runBlocking {
        for ((user, lp) in listOf(" " to "LP-1", "MERVE" to " ")) {
            val result = createProductionPickForOperator("PROD-1", user, lp,
                { _, _ -> error("Must not write") }, { error("Must not read") })
            assertFalse(result.ok)
        }
    }

    @Test fun `missing endpoint never falls back to shared BC identity`() = runBlocking {
        val actions = mutableListOf<String>()
        val rejection = BcApi.ApiResult(false, 404, "not deployed")
        val result = createProductionPickForOperator("PROD-1", "MERVE", "LP-1", { action, _ ->
            actions += action
            rejection
        }, { error("Rejected action must not read") })
        assertSame(rejection, result)
        assertEquals(listOf("createPickFromLpFor"), actions)
    }

    @Test fun `wrong owner order identity and malformed response cannot open pick`() = runBlocking {
        for (response in listOf(header(owner = "DYNOPS"), header(source = "OTHER"), header(no = "PICK-2"),
            header(owner = ""), BcApi.ApiResult(true, 200, "invalid"), BcApi.ApiResult(false, 503, "offline"))) {
            var writes = 0
            val result = createProductionPickForOperator("PROD-1", "MERVE", send = { _, _ ->
                writes++
                created()
            }, readHeader = { response })
            assertFalse(response.body, result.ok)
            assertEquals(1, writes)
        }
    }

    @Test fun `missing pick number cannot navigate or attempt an ownership read`() = runBlocking {
        val result = createProductionPickForOperator("PROD-1", "MERVE", send = { _, _ -> BcApi.ApiResult(true, 204, "") },
            readHeader = { error("No pick exists to verify") })
        assertFalse(result.ok)
    }

    @Test fun `production detection requires released component source for every take row`() {
        fun line(source: Int = 5407, subtype: Int = 3, action: String = "Take") =
            JSONObject().put("sourceType", source).put("sourceSubtype", subtype).put("actionType", action)
        assertTrue(isProductionPick(listOf(line(), line(action = "Place"))))
        assertFalse(isProductionPick(emptyList()))
        assertFalse(isProductionPick(listOf(line(action = "Place"))))
        assertFalse(isProductionPick(listOf(line(), line(source = 37))))
        assertFalse(isProductionPick(listOf(line(subtype = 2))))
        assertFalse(isProductionPick(listOf(JSONObject().put("actionType", "Take"))))
    }

    @Test fun `production key escapes order and status literals`() {
        val key = productionComponentKey(JSONObject().put("prodOrderNo", "P'1").put("prodOrderLineNo", 10000).put("componentLineNo", 20000))
        assertTrue(key.contains("prodOrderNo='P''1'"))
        assertTrue(key.contains("prodOrderLineNo=10000,componentLineNo=20000"))
    }

    @Test fun `ready pallet starts at BC scoped quantity rather than full demand`() {
        val line = JSONObject().put("actionType", "Take").put("sourceType", 5407).put("sourceSubtype", 3)
            .put("licensePlateNo", "LP-4").put("qtyToHandle", 4.0)
        assertEquals(4.0, initialPalletPickQuantity(listOf(line), 10.0), 0.00001)
        line.put("qtyToHandle", 0.0)
        assertEquals(0.0, initialPalletPickQuantity(listOf(line), 10.0), 0.00001)
        line.put("qtyToHandle", 11.0)
        assertEquals(0.0, initialPalletPickQuantity(listOf(line), 10.0), 0.00001)
    }

    @Test fun `ordinary sales pick keeps its previous initial quantity`() {
        val line = JSONObject().put("actionType", "Take").put("sourceType", 37)
            .put("licensePlateNo", "LP-4").put("qtyToHandle", 4.0)
        assertEquals(10.0, initialPalletPickQuantity(listOf(line), 10.0), 0.00001)
    }

    @Test fun `production Multi pick permits one complete pallet with outstanding order demand`() {
        assertTrue(pickReadyToRegister("Multi", listOf(4.0, 0.0), allCollected = false, productionPick = true))
        assertFalse(pickReadyToRegister("Multi", listOf(0.0, 0.0), allCollected = false, productionPick = true))
        assertFalse(pickReadyToRegister("Multi", listOf(4.0, 0.0), allCollected = false, productionPick = false))
    }
}
