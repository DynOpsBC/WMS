package com.dynops.bcwms.feature

import android.graphics.Bitmap
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.BuildConfig
import com.dynops.bcwms.ui.BcwmsTheme
import org.junit.Rule
import org.junit.Test
import java.io.File

/** Real label screen on an offline debug app; never sends a physical print job. */
class ItemLabelRangesUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun kitokoShowsOnlyTheFourRemainingRangesOnATerminalScreen() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        check(BuildConfig.DEBUG && !BcApi.hasToken(instrumentation.targetContext))
        compose.setContent {
            BcwmsTheme(darkTheme = false) {
                Surface(Modifier.fillMaxSize().safeDrawingPadding()) {
                    Column {
                        Text("Etiket Çıkar", style = MaterialTheme.typography.titleLarge,
                            modifier = Modifier.padding(16.dp))
                        LabelsModule()
                    }
                }
            }
        }
        compose.onNodeWithText("Ürün Etiketi").performClick()
        compose.waitForIdle()
        instrumentation.uiAutomation.executeShellCommand("input keyevent 111").close()
        compose.waitForIdle()
        listOf(1251..1500, 1501..1750, 1751..2000, 2001..2250).forEach { range ->
            compose.onNodeWithText("Ürün ${range.first}–${range.last} etiketi")
                .assertIsDisplayed().assertIsEnabled()
        }
        listOf(1..300, 301..500, 501..700, 701..1000, 1001..1250).forEach { range ->
            compose.onNodeWithText(allItemLabelsTitle(range, true, true)).assertDoesNotExist()
        }
        val file = File(instrumentation.targetContext.getExternalFilesDir(null), "03-urun-etiketi-araliklar.png")
        file.outputStream().use {
            instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, it)
        }
    }
}
