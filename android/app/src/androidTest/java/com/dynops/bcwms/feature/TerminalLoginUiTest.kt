package com.dynops.bcwms.feature

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Button
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.BcApi
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Rule
import org.junit.Test

/** Exercises the real screen with an isolated offline gateway; no live BC writes. */
class TerminalLoginUiTest {
    @get:Rule val compose = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val users = listOf(
        JSONObject().put("username", "OP01").put("displayName", "Merve Demirci"),
        JSONObject().put("username", "OP02").put("displayName", "Ayşe Yılmaz"),
        JSONObject().put("username", "ADMIN01").put("displayName", "Depo Sorumlusu").put("terminalAdmin", true),
    )
    private val gateway = object : TerminalLoginGateway {
        override suspend fun terminals() = listOf(JSONObject().put("code", "TERMİNAL-1"), JSONObject().put("code", "TERMİNAL-2"))
        override suspend fun users(terminal: String) = users
        override suspend fun login(terminal: String, username: String, pin: String): String =
            if (pin != "0017") JSONObject().put("error", "PIN hatalı.").toString()
            else JSONObject().put("userId", username).put("terminalCode", terminal)
                .put("displayName", users.first { it.optString("username") == username }.optString("displayName"))
                .put("labelPrinterCode", if (terminal == "TERMİNAL-1") "ZEBRA-1" else "ZEBRA-2")
                .put("documentPrinterCode", "").put("terminalAdmin", username == "ADMIN01").toString()
    }
    @Before fun prepare() {
        check(!BcApi.hasToken(context)) { "Use an offline debug app for UI tests." }
        TerminalSession.select(context, "")
    }
    @After fun clearSession() { TerminalSession.select(context, "") }
    private fun waitFor(text: String) {
        compose.waitUntil(10000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
    }
    private fun evidence(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val file = java.io.File(context.getExternalFilesDir(null), "$name.png")
        file.outputStream().use {
            instrumentation.uiAutomation.takeScreenshot().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
        instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /sdcard/Download/wms-$name.png").use {
            java.io.FileInputStream(it.fileDescriptor).use { input -> input.readBytes() }
        }
    }
    @Test fun selectTerminalRejectWrongPinThenSignInWithKeyboardOpen() {
        var signedIn = false
        compose.setContent { MaterialTheme { TerminalOperatorLogin({ signedIn = it }, {}, gateway) } }
        waitFor("TERMİNAL-1")
        evidence("terminal-selection")
        compose.onNodeWithText("TERMİNAL-1").performClick()
        waitFor("Merve Demirci")
        evidence("terminal-users")
        compose.onNodeWithText("Merve Demirci").performClick()
        compose.onNodeWithText("Giriş yap").assertIsNotEnabled()
        compose.onNodeWithText("4 haneli PIN").performClick().performTextReplacement("9999")
        compose.onNodeWithText("Giriş yap").performScrollTo().performClick()
        waitFor("PIN hatalı.")
        assertFalse(signedIn)
        assertFalse(BcApi.hasLocalUser(context))
        compose.onNodeWithText("4 haneli PIN").performScrollTo().performTextReplacement("0017")
        evidence("terminal-pin")
        compose.onNodeWithText("Giriş yap").performScrollTo().performClick()
        compose.waitUntil(10000) { signedIn }
        assertEquals("OP01", BcApi.getLocalUser(context))
        assertEquals("ZEBRA-1", getDefaultPrinter(context))
        assertTrue(TerminalSession.authenticated(context))
    }
    @Test fun handoverRetainsTerminalAndUsesNewOperatorWithSamePrinter() {
        TerminalSession.select(context, "TERMİNAL-2")
        setDefaultPrinter(context, "ZEBRA-2")
        BcApi.saveLocalUser(context, "OLD", "{}")
        BcApi.clearLocalUser(context)
        var signedIn = false
        compose.setContent { MaterialTheme { TerminalOperatorLogin({ signedIn = it }, {}, gateway) } }
        waitFor("Ayşe Yılmaz")
        compose.onNodeWithText("Ayşe Yılmaz").performClick()
        compose.onNodeWithText("4 haneli PIN").performTextReplacement("0017")
        compose.onNodeWithText("Giriş yap").performScrollTo().performClick()
        compose.waitUntil(10000) { signedIn }
        assertEquals("OP02", BcApi.getLocalUser(context))
        assertEquals("TERMİNAL-2", TerminalSession.code(context))
        assertEquals("ZEBRA-2", getDefaultPrinter(context))
    }
    @Test fun managerLoginThenExplicitLogoutPreservesDeviceAndPrinter() {
        TerminalSession.select(context, "TERMİNAL-2")
        var signedIn = false
        compose.setContent { MaterialTheme { TerminalOperatorLogin({ signedIn = it }, {}, gateway) } }
        waitFor("Yönetici girişi")
        compose.onNodeWithText("Yönetici girişi").performClick()
        compose.onNodeWithText("4 haneli PIN").performTextReplacement("0017")
        compose.onNodeWithText("Giriş yap").performScrollTo().performClick()
        compose.waitUntil(10000) { signedIn }
        assertEquals("ADMIN01", BcApi.getLocalUser(context))
        assertTrue(JSONObject(BcApi.getLocalProfileJson(context)).optBoolean("terminalAdmin"))
        assertTrue(TerminalSession.authenticated(context))
        assertFalse(BcApi.isAdminTestSession(context))
        TerminalSession.signOut(context)
        assertFalse(TerminalSession.authenticated(context))
        assertFalse(BcApi.hasLocalUser(context))
        assertEquals("TERMİNAL-2", TerminalSession.code(context))
        assertEquals("ZEBRA-2", getDefaultPrinter(context))
    }

    @Test fun expiredSessionRetainsTerminalButRequiresNewEmployeePin() {
        TerminalSession.select(context, "TERMİNAL-1")
        BcApi.saveLocalUser(context, "OP01", JSONObject().put("userId", "OP01")
            .put("terminalCode", "TERMİNAL-1").put("terminalScope", TerminalSession.scope(context))
            .put("pinVerifiedAt", System.currentTimeMillis() - TERMINAL_SESSION_MS)
            .put("pinVerifiedElapsed", android.os.SystemClock.elapsedRealtime() - TERMINAL_SESSION_MS).toString())
        assertFalse(TerminalSession.authenticated(context))
        var signedIn = false
        compose.setContent { MaterialTheme { TerminalOperatorLogin({ signedIn = it }, {}, gateway) } }
        waitFor("Ayşe Yılmaz")
        compose.onNodeWithText("Ayşe Yılmaz").performClick()
        compose.onNodeWithText("4 haneli PIN").performTextReplacement("0017")
        compose.onNodeWithText("Giriş yap").performScrollTo().performClick()
        compose.waitUntil(10000) { signedIn }
        assertTrue(TerminalSession.authenticated(context))
        assertEquals("OP02", BcApi.getLocalUser(context))
        assertEquals("Ayşe Yılmaz", BcApi.getOperatorDisplayName(context))
        assertEquals("TERMİNAL-1", TerminalSession.code(context))
    }


    @Test fun sameEmployeePinResumesMountedDocumentQuantityAndStep() = checkDraftResume(false)
    @Test fun differentEmployeePinLeavesPreviousDocumentForHome() = checkDraftResume(true)

    private fun checkDraftResume(changeEmployee: Boolean) {
        TerminalSession.select(context, "TERMİNAL-1")
        var locked by mutableStateOf(false)
        var home by mutableStateOf(false)
        var documentMounts = 0
        compose.setContent {
            MaterialTheme {
                if (home) Text("Ana Menü") else {
                    // Like ReceivingModule, draft state belongs to the mounted document, not the lock screen.
                    var quantity by remember { mutableStateOf("") }
                    var step by remember { mutableStateOf("Miktar gir") }
                    DisposableEffect(Unit) { documentMounts++; onDispose {} }
                    Column {
                        Text("Mal kabul · TEST-001")
                        OutlinedTextField(quantity, { quantity = it }, label = { Text("LP miktarı") })
                        Text(step)
                        Button(onClick = { step = "Raf doğrulama" }) { Text("Sonraki adım") }
                    }
                }
                if (locked) TerminalReauthenticationDialog(
                    previousOperator = "OP01",
                    onVerified = { changed -> home = changed; locked = false },
                    onConnectionSettings = {}, gateway = gateway,
                )
            }
        }
        compose.onNodeWithText("LP miktarı").performTextReplacement("12.5")
        compose.onNodeWithText("Sonraki adım").performClick()
        compose.runOnIdle { locked = true }
        waitFor("Merve Demirci")
        compose.onNodeWithText(if (changeEmployee) "Ayşe Yılmaz" else "Merve Demirci").performClick()
        compose.onNodeWithText("4 haneli PIN").performTextReplacement("9999")
        compose.onNodeWithText("Giriş yap").performScrollTo().performClick()
        waitFor("PIN hatalı.")
        compose.runOnIdle { assertTrue(locked); assertEquals(1, documentMounts) }
        compose.onNodeWithText("4 haneli PIN").performScrollTo().performTextReplacement("0017")
        compose.onNodeWithText("Giriş yap").performScrollTo().performClick()
        compose.waitUntil(10000) { !locked }
        if (changeEmployee) {
            compose.onNodeWithText("Ana Menü").assertIsDisplayed()
            compose.onNodeWithText("Mal kabul · TEST-001").assertDoesNotExist()
            assertEquals("OP02", BcApi.getLocalUser(context))
        } else {
            compose.onNodeWithText("Mal kabul · TEST-001").assertIsDisplayed()
            compose.onNodeWithText("12.5").assertIsDisplayed()
            compose.onNodeWithText("Raf doğrulama").assertIsDisplayed()
            assertEquals(1, documentMounts)
            assertEquals("OP01", BcApi.getLocalUser(context))
            evidence("terminal-resume-draft")
        }
    }

    @Test fun expiryKeepsOwnerForDocumentReloadButBlocksWrites() = kotlinx.coroutines.runBlocking {
        TerminalSession.select(context, "TERMİNAL-1")
        BcApi.saveLocalUser(context, "OP01", JSONObject().put("userId", "OP01")
            .put("terminalCode", "TERMİNAL-1").put("terminalScope", TerminalSession.scope(context))
            .put("pinVerifiedAt", System.currentTimeMillis() - TERMINAL_SESSION_MS).toString())
        assertFalse(TerminalSession.authenticated(context))
        assertEquals("OP01", BcApi.currentUserId(context))
        // No token is installed: the session guard must reject this before any network request.
        val result = BcApi.post(context, "receipts('TEST-001')/Microsoft.NAV.assignToUser", "{}")
        assertFalse(result.ok)
        assertEquals(401, result.httpCode)
        TerminalSession.signOut(context)
        assertEquals("", BcApi.currentUserId(context))
    }
}
