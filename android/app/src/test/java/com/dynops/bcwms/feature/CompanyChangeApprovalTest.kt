package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CompanyChangeApprovalTest {
    @Test fun `configured BADE cannot move approval to another tenant via Microsoft login`() {
        assertFalse(mayCaptureTerminalTenant("bade", true, "BADE", "OTHER"))
        assertTrue(mayCaptureTerminalTenant("bade", true, "BADE", "bade"))
        assertTrue(mayCaptureTerminalTenant("bade", false, "BADE", "OTHER"))
        assertTrue(mayCaptureTerminalTenant("kitoko", true, "A", "B"))
    }
    private fun profile() = JSONObject().put("userId", "manager").put("terminalCode", "T1").put("terminalAdmin", true)
    @Test fun `only matching manager response authorizes company change`() {
        assertTrue(companyChangeProfileApproved(profile(), "manager", "T1"))
        assertFalse(companyChangeProfileApproved(null, "manager", "T1"))
        assertFalse(companyChangeProfileApproved(profile().put("terminalAdmin", false), "manager", "T1"))
        assertFalse(companyChangeProfileApproved(profile().put("disabled", true), "manager", "T1"))
        assertFalse(companyChangeProfileApproved(profile().put("error", "wrong PIN"), "manager", "T1"))
        assertFalse(companyChangeProfileApproved(profile(), "employee", "T1"))
        assertFalse(companyChangeProfileApproved(profile(), "manager", "T2"))
        assertFalse(companyChangeProfileApproved(profile().removeAdmin(), "manager", "T1"))
    }
    private fun JSONObject.removeAdmin(): JSONObject { remove("terminalAdmin"); return this }
}
