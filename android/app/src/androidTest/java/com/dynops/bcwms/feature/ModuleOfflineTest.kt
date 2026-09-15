package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.runtime.CompositionLocalProvider
import com.dynops.bcwms.LocalNavigator
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.BcApi
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/** Mount actual production modules without credentials, check rendering and
 * retry controls, and retain screenshots for narrow-terminal visual review.
 * These are offline smoke checks, not successful warehouse transactions. */
@RunWith(Parameterized::class)
class ModuleOfflineTest(private val module: String) {
    @get:Rule val compose = createComposeRule()

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{0}") fun modules() = listOf(
            "receiving", "putaway", "picking", "shipping", "packing", "lp", "movement",
            "directed", "count", "countv2", "production", "assembly", "quality", "printers",
            "item", "bin", "entries", "help",
        )
    }

    @Test fun offlineScreenRendersAndRetryDoesNotCrash() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        check(!BcApi.hasToken(instrumentation.targetContext)) { "Offline debug app required" }
        compose.setContent { CompositionLocalProvider(LocalNavigator provides {}) { MaterialTheme { Surface(Modifier.fillMaxSize()) {
            when (module) {
                "receiving" -> ReceivingModule()
                "putaway" -> PutAwayModule()
                "picking" -> PickingModule()
                "shipping" -> ShippingModule()
                "packing" -> PackingModule()
                "lp" -> LicensePlateModule()
                "movement" -> AdHocMoveModule()
                "directed" -> DirectedMoveModule()
                "count" -> CountModule()
                "countv2" -> CountV2Module()
                "production" -> ProductionModule()
                "assembly" -> AssemblyModule()
                "quality" -> QualityModule()
                "printers" -> PrintersModule()
                "item" -> ItemInquiryModule()
                "bin" -> BinInquiryModule()
                "entries" -> WhseEntriesModule()
                "help" -> TerminalHelpModule(false) {}
            }
        } } } }
        compose.waitForIdle()
        val text = SemanticsMatcher.keyIsDefined(SemanticsProperties.Text)
        check(compose.onAllNodes(text).fetchSemanticsNodes().isNotEmpty()) { "$module rendered no text" }
        val refresh = compose.onAllNodes(hasText("Yenile") and hasClickAction() and isEnabled())
        if (refresh.fetchSemanticsNodes().isNotEmpty()) {
            refresh[0].performClick()
            compose.waitForIdle()
        }
        val file = java.io.File(instrumentation.targetContext.getExternalFilesDir(null), "$module.png")
        file.outputStream().use { instrumentation.uiAutomation.takeScreenshot().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /sdcard/Download/wms-audit-$module.png").use {
            java.io.FileInputStream(it.fileDescriptor).use { input -> input.readBytes() }
        }
    }
}
