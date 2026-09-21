package com.dynops.bcwms

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PickTakeoverTest {
    private fun owner(value: String) = BcApi.ApiResult(true, 200, JSONObject().put("assignedUserId", value).toString())

    @Test fun `confirmed foreign owner is reassigned and read back`() = runBlocking {
        var reads = 0
        val actions = mutableListOf<String>()
        val result = claimPickWithConfirmation(" MERVE ", { owner(if (++reads <= 2) "DYNOPS" else "MERVE") }, {
            assertEquals("DYNOPS", it); true
        }, { action, body ->
            actions += action
            assertEquals("MERVE", JSONObject(body).getString("userId"))
            assertTrue(JSONObject(body).getString("reason").contains("DYNOPS"))
            BcApi.ApiResult(true, 204, "")
        })
        assertTrue(result.ok)
        assertEquals(listOf("forceReassign"), actions)
        assertEquals(3, reads)
    }

    @Test fun `declining takeover never writes`() = runBlocking {
        val result = claimPickWithConfirmation("MERVE", { owner("DYNOPS") }, { false }, { _, _ -> error("No mutation on cancel") })
        assertFalse(result.ok)
        assertTrue(result.body.contains("iptal"))
    }

    @Test fun `unassigned or same owner uses claim without confirmation`() = runBlocking {
        for (existing in listOf("", "merve")) {
            var reads = 0
            val result = claimPickWithConfirmation("MERVE", { owner(if (++reads == 1) existing else "MERVE") }, { error("No takeover prompt") }, { action, _ ->
                assertEquals("claim", action); BcApi.ApiResult(true, 204, "")
            })
            assertTrue(result.ok)
        }
    }

    @Test fun `owner changed during confirmation is not overwritten`() = runBlocking {
        var reads = 0
        val result = claimPickWithConfirmation("MERVE", { owner(if (++reads == 1) "DYNOPS" else "ALI") }, { true }, { _, _ -> error("Owner changed") })
        assertFalse(result.ok)
        assertTrue(result.body.contains("sahibi değişti"))
    }

    @Test fun `server success with unchanged owner does not unlock document`() = runBlocking {
        val result = claimPickWithConfirmation("MERVE", { owner("DYNOPS") }, { true }, { _, _ -> BcApi.ApiResult(true, 204, "") })
        assertFalse(result.ok)
    }

    @Test fun `failed reassignment is not retried or reported successful`() = runBlocking {
        var writes = 0
        val result = claimPickWithConfirmation("MERVE", { owner("DYNOPS") }, { true }, { _, _ ->
            writes++; BcApi.ApiResult(false, 403, "forbidden")
        })
        assertFalse(result.ok)
        assertEquals(1, writes)
    }

    @Test fun `unknown ownership or operator cannot trigger takeover`() = runBlocking {
        for (body in listOf("{}", "invalid", "{\"assignedUserId\":null}")) {
            val result = claimPickWithConfirmation("MERVE", { BcApi.ApiResult(true, 200, body) }, { error("Unknown owner") }, { _, _ -> error("Unknown owner") })
            assertFalse(result.ok)
        }
        val result = claimPickWithConfirmation(" ", { error("No operator") }, { error("No operator") }, { _, _ -> error("No operator") })
        assertFalse(result.ok)
    }
}
