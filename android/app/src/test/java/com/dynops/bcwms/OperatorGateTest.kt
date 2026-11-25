package com.dynops.bcwms

import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OperatorGateTest {
    @Test fun `gate only for DKC build without a signed-in operator`() {
        assertTrue(operatorGateApplies("emu", ""))
        assertFalse(operatorGateApplies("emu", "TUNAY.KAYA"))
        assertFalse(operatorGateApplies("bade", ""))
    }
    @Test fun `gate needs at least one enabled user`() {
        assertFalse(operatorGateRequired(emptyList()))
        assertFalse(operatorGateRequired(listOf(JSONObject().put("username", "X").put("disabled", true))))
        assertTrue(operatorGateRequired(listOf(JSONObject().put("username", "TUNAY.KAYA").put("disabled", false))))
    }
}
