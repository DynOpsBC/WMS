package com.dynops.bcwms.feature

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.dynops.bcwms.ui.BcwmsTheme
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class CompanyChangeApprovalUiTest {
    @get:Rule val compose = createComposeRule()
    private class FakeGateway(private val grant: Boolean) : TerminalLoginGateway {
        var attempts = 0
        override suspend fun terminals() = emptyList<JSONObject>()
        override suspend fun users(terminal: String) = listOf(JSONObject()
            .put("username", "manager").put("displayName", "Test Manager").put("terminalCode", "T1")
            .put("disabled", false).put("terminalAdmin", true))
        override suspend fun login(terminal: String, username: String, pin: String): String {
            attempts++
            return JSONObject().put("userId", username).put("terminalCode", terminal)
                .put("terminalAdmin", grant).toString()
        }
    }
    @Test fun validManagerNeedsFreshPinBeforeApproval() {
        val api = FakeGateway(true)
        var approvals = 0
        compose.setContent { BcwmsTheme { CompanyChangeApproval({ approvals++ }, {}, api, "T1") } }
        compose.onNodeWithText("Onayla").assertIsNotEnabled()
        compose.onNodeWithText("Yönetici PIN").performTextInput("1234")
        compose.onNodeWithText("Onayla").performClick()
        compose.runOnIdle { assertEquals(1, approvals); assertEquals(1, api.attempts) }
    }
    @Test fun nonManagerResponseNeverChangesCompany() {
        val api = FakeGateway(false)
        var approvals = 0
        compose.setContent { BcwmsTheme { CompanyChangeApproval({ approvals++ }, {}, api, "T1") } }
        compose.onNodeWithText("Yönetici PIN").performTextInput("1234")
        compose.onNodeWithText("Onayla").performClick()
        compose.onNodeWithText("Yönetici PIN'i doğrulanamadı. Şirket değiştirilmedi.").assertIsDisplayed()
        compose.runOnIdle { assertEquals(0, approvals) }
        compose.onNodeWithText("Onayla").assertIsNotEnabled()
    }
    @Test fun cancelDoesNotVerifyOrChangeCompany() {
        val api = FakeGateway(true)
        var dismissed = 0
        compose.setContent { BcwmsTheme { CompanyChangeApproval({}, { dismissed++ }, api, "T1") } }
        compose.onNodeWithText("Vazgeç").performClick()
        compose.runOnIdle { assertEquals(1, dismissed); assertEquals(0, api.attempts) }
    }
}
