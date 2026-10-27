package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.BcApi
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ConnectionPickerUiTest {
    @get:Rule val compose = createComposeRule()
    private val current = BcApi.Company("old-id", "Element 4", "Element 4")
    // Reused company ID across a copied sandbox must still require an explicit selection.
    private val copied = BcApi.Company("old-id", "Element 4 Test", "Element 4 Test")
    private val environments = listOf(
        BcApi.EnvCompanies("Sand2010", listOf(current)),
        BcApi.EnvCompanies("DemoSandbox", listOf(copied)),
        BcApi.EnvCompanies("Production", listOf(BcApi.Company("live-id", "Kitoko", "Kitoko"))),
    )

    private fun content(busy: Boolean = false, connect: (BcApi.EnvCompanies, BcApi.Company) -> Unit = { _, _ -> },
                        find: (String) -> Unit = {}, cancel: () -> Unit = {}, refresh: () -> Unit = {}) {
        compose.setContent {
            MaterialTheme {
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
                    ConnectionPicker(environments, "Sand2010", current.id, current.displayName, busy,
                        refresh, find, connect, cancel)
                }
            }
        }
    }

    @Test fun environmentAndCompanySelectionStayDraftUntilConnectIsPressed() {
        val connected = mutableListOf<Pair<String, String>>()
        content(connect = { env, company -> connected += env.environment to company.id })
        compose.onNodeWithText("DemoSandbox").performScrollTo().performClick()
        compose.onNodeWithText("Seçilen şirkete bağlan").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("Element 4 Test").performScrollTo().performClick()
        assertTrue(connected.isEmpty())
        compose.onNodeWithText("Seçilen şirkete bağlan").performScrollTo().assertIsEnabled().performClick()
        assertEquals(listOf("DemoSandbox" to "old-id"), connected)
        evidence("connection-selected")
    }

    @Test fun changingEnvironmentCannotReuseThePreviousCompanySelection() {
        content()
        compose.onNodeWithText("Seçilen şirkete bağlan").performScrollTo().assertIsEnabled()
        compose.onNodeWithText("DemoSandbox").performScrollTo().performClick()
        compose.onNodeWithText("Seçilen şirkete bağlan").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("Element 4 Test").performScrollTo().performClick()
        compose.onNodeWithText("Production").performScrollTo().performClick()
        compose.onNodeWithText("Seçilen şirkete bağlan").performScrollTo().assertIsNotEnabled()
    }

    @Test fun busyScreenPreventsDuplicateConnectAndRefresh() {
        var calls = 0
        content(busy = true, connect = { _, _ -> calls++ }, refresh = { calls++ })
        compose.onNodeWithText("Kontrol ediliyor…").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("Yenile").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("Vazgeç").performScrollTo().assertIsNotEnabled()
        assertEquals(0, calls)
    }

    @Test fun otherEnvironmentSearchAndCancelAreEasyToReach() {
        var searched = ""
        var cancelled = false
        content(find = { searched = it }, cancel = { cancelled = true })
        compose.onNodeWithText("Ortam adı").assertDoesNotExist()
        compose.onNodeWithText("Başka ortam ekle").performScrollTo().performClick()
        compose.onNodeWithText("Ortam adı").performScrollTo().performTextInput("  Sand2310  ")
        compose.onNodeWithText("Ortamı bul").performScrollTo().performClick()
        assertEquals("Sand2310", searched)
        compose.onNodeWithText("Vazgeç").performScrollTo().performClick()
        assertTrue(cancelled)
    }

    @Test fun verifiedConnectionClearsOldOperatorAndKeepsTerminalPerEnvironment() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        check(!BcApi.hasToken(context)) { "Use an offline debug app for UI tests." }
        val env = BcApi.getEnvironment(context)
        val company = BcApi.Company(BcApi.getCompanyId(context), BcApi.getCompanyName(context), BcApi.getCompanyName(context))
        try {
            BcApi.setEnvironment(context, "Sand2010")
            BcApi.setCompany(context, current.id, current.displayName)
            TerminalSession.select(context, "SOURCE-TERMINAL")
            BcApi.saveLocalUser(context, "OLD-OPERATOR", "{}")
            BcApi.saveConnection(context, "DemoSandbox", copied)
            assertEquals("DemoSandbox", BcApi.getEnvironment(context))
            assertEquals(copied.id, BcApi.getCompanyId(context))
            assertFalse(BcApi.hasLocalUser(context))
            assertEquals("", TerminalSession.code(context))
            assertTrue(BcApi.connectionEnvironmentNames(context).contains("DemoSandbox"))
            BcApi.setEnvironment(context, "Sand2010")
            assertEquals("SOURCE-TERMINAL", TerminalSession.code(context))
        } finally {
            context.getSharedPreferences("bcwms_prefs", android.content.Context.MODE_PRIVATE).edit()
                .remove("wms_terminal." + TerminalSession.scope(context)).commit()
            BcApi.clearLocalUser(context)
            BcApi.setEnvironment(context, env)
            BcApi.setCompany(context, company.id, company.displayName)
        }
    }

    @Test fun connectionScreenIsReadableOnTerminalSize() {
        content()
        compose.onNodeWithText("Mevcut bağlantı").assertIsDisplayed()
        evidence("connection-environments")
        compose.onNodeWithText("DemoSandbox").performScrollTo().performClick()
        compose.onNodeWithText("Element 4 Test").performScrollTo().assertIsDisplayed()
    }

    private fun evidence(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val file = java.io.File(instrumentation.targetContext.getExternalFilesDir(null), "$name.png")
        file.outputStream().use { instrumentation.uiAutomation.takeScreenshot().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
    }
}
