package com.dynops.bcwms

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PickClaimTest {
    @Test fun `claim carries PIN username and waits for persisted ownership`() = runBlocking {
        val calls = mutableListOf<String>()
        val result = claimPickForOperator(" MERVE ", { action, body ->
            calls += action
            assertEquals("MERVE", JSONObject(body).getString("userId"))
            BcApi.ApiResult(true, 204, "")
        }, {
            calls += "read"
            BcApi.ApiResult(true, 200, """{"assignedUserId":"merve"}""")
        })
        assertTrue(result.ok)
        assertEquals(listOf("claim", "read"), calls)
    }

    @Test fun `legacy service-account success is never reported as assigned to operator`() = runBlocking {
        val result = claimPickForOperator("MERVE", { _, _ -> BcApi.ApiResult(true, 204, "") }, {
            BcApi.ApiResult(true, 200, """{"assignedUserId":"DYNOPS"}""")
        })
        assertFalse(result.ok)
        assertEquals(409, result.httpCode)
        assertTrue(result.body.contains("DYNOPS"))
    }

    @Test fun `another owner's rejection is preserved with no fallback or second write`() = runBlocking {
        val actions = mutableListOf<String>()
        val rejection = BcApi.ApiResult(false, 400, "Belge başka kullanıcıda")
        val result = claimPickForOperator("MERVE", { action, _ ->
            actions += action
            rejection
        }, { error("Rejected claim must not be reported as success") })
        assertSame(rejection, result)
        assertEquals(listOf("claim"), actions)
    }

    @Test fun `missing operator never sends a mutation`() = runBlocking {
        val result = claimPickForOperator("  ", { _, _ -> error("Must not call BC") }, { error("Must not call BC") })
        assertFalse(result.ok)
        assertEquals(401, result.httpCode)
    }

    @Test fun `failed ownership read keeps claim uncertain and does not retry write`() = runBlocking {
        var writes = 0
        val result = claimPickForOperator("MERVE", { _, _ ->
            writes++
            BcApi.ApiResult(true, 204, "")
        }, { BcApi.ApiResult(false, 503, "offline") })
        assertFalse(result.ok)
        assertEquals(1, writes)
        assertTrue(result.body.contains("doğrulanamadı"))
    }

    @Test fun `missing owner and malformed responses cannot unlock document`() = runBlocking {
        for (body in listOf("{}", "not json", """{"assignedUserId":""}""")) {
            val result = claimPickForOperator("MERVE", { _, _ -> BcApi.ApiResult(true, 204, "") }, {
                BcApi.ApiResult(true, 200, body)
            })
            assertFalse(body, result.ok)
        }
    }

    @Test fun `missing claim endpoint never falls back to BC account assignment`() = runBlocking {
        val actions = mutableListOf<String>()
        val result = claimPickForOperator("MERVE", { action, _ ->
            actions += action
            BcApi.ApiResult(false, 404, "action unavailable")
        }, { error("Must not read after failed request") })
        assertFalse(result.ok)
        assertEquals(listOf("claim"), actions)
    }
}
