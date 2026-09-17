package com.dynops.bcwms.feature

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TerminalChangeTest {
    private fun profile(admin: Boolean = true, terminal: String = "T2", user: String = "ADMIN") =
        JSONObject().put("userId", user).put("terminalCode", terminal).put("terminalAdmin", admin)

    @Test fun `initial selection is free but a selected terminal cannot be cleared or changed without approval`() {
        assertTrue(terminalSelectionAllowed("", "T1", null))
        assertTrue(terminalSelectionAllowed("T1", "T1", null))
        assertFalse(terminalSelectionAllowed("T1", "", null))
        assertFalse(terminalSelectionAllowed("T1", "T2", null))
        assertFalse(terminalSelectionAllowed("", "", null))
    }

    @Test fun `replacement requires a manager response matching the new terminal`() {
        assertTrue(terminalSelectionAllowed("T1", "T2", profile()))
        assertFalse(terminalSelectionAllowed("T1", "T2", profile(admin = false)))
        assertFalse(terminalSelectionAllowed("T1", "T2", profile(terminal = "T3")))
        assertFalse(terminalSelectionAllowed("T1", "T2", profile(user = "")))
        assertFalse(terminalSelectionAllowed("T1", "T2", profile().put("error", "PIN hatalı")))
        assertFalse(terminalSelectionAllowed("T1", "", profile()))
    }

    private class Gateway(var response: String?) : TerminalLoginGateway {
        val attempts = mutableListOf<List<String>>()
        override suspend fun terminals(): List<JSONObject>? = error("Not needed")
        override suspend fun users(terminal: String): List<JSONObject>? = error("Not needed")
        override suspend fun login(terminal: String, username: String, pin: String): String? {
            attempts += listOf(terminal, username, pin)
            return response
        }
    }

    @Test fun `approval verifies a fresh PIN against the target even when the old terminal is unavailable`() = runBlocking {
        val gateway = Gateway(profile().toString())
        val approved = verifiedTerminalChangeProfile(gateway, "T2", "ADMIN", "0017")
        assertTrue(terminalSelectionAllowed("DISABLED-OLD", "T2", approved))
        assertEquals(listOf(listOf("T2", "ADMIN", "0017")), gateway.attempts)
    }

    @Test fun `incorrect PIN network failure malformed response and non managers fail closed`() = runBlocking {
        for (response in listOf(null, "bad", "{}", """{"error":"PIN hatalı"}""",
            profile(admin = false).toString(), profile(user = "OTHER").toString(), profile(terminal = "T3").toString())) {
            assertTrue(response, runCatching {
                verifiedTerminalChangeProfile(Gateway(response), "T2", "ADMIN", "0017")
            }.isFailure)
        }
    }

    @Test fun `invalid PIN is not submitted to BC`() = runBlocking {
        val gateway = Gateway(profile().toString())
        assertTrue(runCatching { verifiedTerminalChangeProfile(gateway, "T2", "ADMIN", "12") }.isFailure)
        assertTrue(gateway.attempts.isEmpty())
    }
}
