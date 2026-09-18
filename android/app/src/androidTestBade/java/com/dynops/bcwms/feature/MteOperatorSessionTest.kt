package com.dynops.bcwms.feature

import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.BuildConfig
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/** Offline debug session; no BC calls or physical print jobs. */
class MteOperatorSessionTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var previousCompanyId: String
    private lateinit var previousCompanyName: String

    @Before fun prepare() {
        check(BuildConfig.DEBUG && !BcApi.hasToken(context))
        previousCompanyId = BcApi.getCompanyId(context)
        previousCompanyName = BcApi.getCompanyName(context)
        BcApi.setCompany(context, "mte-test-company-a", "Test A")
        login("MERVE", "Merve Demirci")
    }

    @After fun cleanup() {
        TerminalSession.signOut(context)
        BcApi.setCompany(context, previousCompanyId, previousCompanyName)
    }

    private fun login(username: String, displayName: String) {
        assertTrue(TerminalSession.select(context, "MTE-TEST"))
        BcApi.saveLocalUser(context, username, JSONObject()
            .put("userId", username).put("displayName", displayName)
            .put("terminalCode", "MTE-TEST").put("terminalScope", TerminalSession.scope(context))
            .put("pinVerifiedAt", System.currentTimeMillis())
            .put("pinVerifiedElapsed", android.os.SystemClock.elapsedRealtime()).toString())
        setDefaultPrinter(context, "ZPL", PRINTER_USAGE_LABEL)
        setDefaultPrinter(context, "", PRINTER_USAGE_DOCUMENT)
    }

    @Test fun currentPinUserAppearsInBlankMteOptions() {
        val result = mteOptionsForCurrentOperator(context, MteOptions(), emptyList(), TerminalSession.scope(context))
        assertEquals("Merve Demirci", result.inspectorEmployeeNo)
    }

    @Test fun anotherCompanyCannotReuseAnOldPinIdentityOrEmployeeList() {
        val originalScope = TerminalSession.scope(context)
        BcApi.setCompany(context, "mte-test-company-b", "Test B")
        assertTrue(runCatching {
            mteOptionsForCurrentOperator(context, MteOptions(), listOf("A01" to "Merve Demirci"), originalScope)
        }.isFailure)
        login("AYSE", "Ayşe Yılmaz")
        assertTrue(runCatching {
            mteOptionsForCurrentOperator(context, MteOptions(), emptyList(), originalScope)
        }.isFailure)
        val current = mteOptionsForCurrentOperator(context, MteOptions(), emptyList(), TerminalSession.scope(context))
        assertEquals("Ayşe Yılmaz", current.inspectorEmployeeNo)
    }

    @Test fun signedOutUserCannotPrintEvenWithAManualInspector() {
        val scope = TerminalSession.scope(context)
        TerminalSession.signOut(context)
        assertTrue(runCatching {
            mteOptionsForCurrentOperator(context, MteOptions("EMP01"), emptyList(), scope)
        }.isFailure)
    }
}
