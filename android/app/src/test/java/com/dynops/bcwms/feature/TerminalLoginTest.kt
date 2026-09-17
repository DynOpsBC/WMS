package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TerminalLoginTest {
    @Test fun `PIN keeps leading zeroes and accepts exactly four ASCII digits`() {
        assertTrue(validTerminalPin("0017"))
        assertTrue(validTerminalPin("9876"))
        listOf("", "123", "12345", " 1234", "12a4", "１２３４", "١٢٣٤").forEach {
            assertFalse(it, validTerminalPin(it))
        }
    }
    @Test fun `terminal preference scopes isolate companies and environments without separator collisions`() {
        val one = terminalPreferenceScope("tenant", "Production", "company1")
        assertNotEquals(one, terminalPreferenceScope("tenant", "Production", "company2"))
        assertNotEquals(one, terminalPreferenceScope("tenant", "Sandbox", "company1"))
        assertNotEquals(one, terminalPreferenceScope("other", "Production", "company1"))
        assertNotEquals(terminalPreferenceScope("a:b", "c", "d"), terminalPreferenceScope("a", "b:c", "d"))
    }
    @Test fun `terminal key remains an escaped OData string with Turkish and special characters`() {
        assertEquals("wmsTerminals('TERM%C4%B0NAL-1')/Microsoft.NAV.login", terminalLoginPath("TERMİNAL-1"))
        assertEquals("wmsTerminals('A%27%27%2FB%3DC')/Microsoft.NAV.login", terminalLoginPath("A'/B=C"))
    }
    @Test fun `login response must match both the selected employee and terminal`() {
        val p = JSONObject().put("userId", "OP01").put("terminalCode", "TERMINAL-1")
        assertTrue(terminalProfileMatches(p, "OP01", "TERMINAL-1"))
        assertFalse(terminalProfileMatches(p, "OP02", "TERMINAL-1"))
        assertFalse(terminalProfileMatches(p, "OP01", "TERMINAL-2"))
        assertFalse(terminalProfileMatches(JSONObject(), "", ""))
        p.put("error", "PIN hatalı")
        assertFalse(terminalProfileMatches(p, "OP01", "TERMINAL-1"))
    }
    @Test fun `manager membership spans terminals but a regular user remains terminal specific`() {
        val user = JSONObject().put("username", "OP01").put("disabled", false).put("terminalCode", "TERM-1")
        assertTrue(authorizedTerminalUser(user, "OP01", "TERM-1"))
        assertFalse(authorizedTerminalUser(user, "OP01", "TERM-2"))
        user.put("terminalAdmin", true)
        assertTrue(authorizedTerminalUser(user, "OP01", "TERM-2"))
        user.put("disabled", true)
        assertFalse(authorizedTerminalUser(user, "OP01", "TERM-2"))
        assertFalse(authorizedTerminalUser(user, "OTHER", "TERM-2"))
    }
    @Test fun `operator list includes active managers and escapes the terminal code`() {
        assertEquals("localUsers?\$filter=(terminalCode eq 'T%27%27%201' or terminalAdmin eq true) and disabled eq false", terminalUsersPath("T' 1"))
        assertEquals("Merve · Yönetici", terminalOperatorLabel(JSONObject().put("displayName", "Merve").put("terminalAdmin", true)))
    }
    @Test fun `terminal print cannot silently use shared service account default`() {
        assertNotNull(terminalPrintRequestIssue("""{"printerId":"","copies":1}"""))
        assertNull(terminalPrintRequestIssue("""{"printerId":"ZEBRA-1","copies":1}"""))
        assertNull(terminalPrintRequestIssue("""{"printerId":"","printLabels":false}"""))
        assertNull(terminalPrintRequestIssue("""{"username":"OP01","pin":"0017"}"""))
    }
    @Test fun `PIN expires exactly at thirty minutes and clock rollback cannot extend it`() {
        val login = 100000L
        assertTrue(terminalSessionFresh(login, login))
        assertTrue(terminalSessionFresh(login, login + TERMINAL_SESSION_MS - 1))
        assertFalse(terminalSessionFresh(login, login + TERMINAL_SESSION_MS))
        assertFalse(terminalSessionFresh(login, login - 1))
        assertFalse(terminalSessionFresh(0, login))
    }
    @Test fun `locked session blocks warehouse writes but allows PIN login`() {
        assertFalse(terminalSessionRequestAllowed("POST", "receipts('R1')/Microsoft.NAV.post", false))
        assertFalse(terminalSessionRequestAllowed("PATCH", "receiptLines('L1')", false))
        assertFalse(terminalSessionRequestAllowed("DELETE", "countLines('L1')", false))
        assertTrue(terminalSessionRequestAllowed("POST", terminalLoginPath("T1"), false))
        assertTrue(terminalSessionRequestAllowed("GET", terminalUsersPath("T1"), false))
        assertTrue(terminalSessionRequestAllowed("POST", "receipts('R1')/Microsoft.NAV.post", true))
    }
}
