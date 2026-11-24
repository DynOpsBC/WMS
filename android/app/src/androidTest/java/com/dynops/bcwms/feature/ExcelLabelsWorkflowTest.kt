package com.dynops.bcwms.feature

import androidx.compose.runtime.*
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.ui.BcwmsTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ExcelLabelsWorkflowTest {
    @get:Rule val compose = createComposeRule()

    @Test fun preparedButtonOpensAll1535RowsWithoutAFilePicker() {
        val rows = InstrumentationRegistry.getInstrumentation().context.assets
            .open("dkc-labels-2026-10-15.xlsx").use(ExcelLabelImport::read)
        val apiRows = rows.map { row -> org.json.JSONObject()
            .put("listCode", PreparedItemLabels.LIST_CODE).put("sourceDate", PreparedItemLabels.SOURCE_DATE)
            .put("lineNo", row.order).put("itemNo", row.itemNo).put("description", row.description).put("binCode", row.bin) }
        var loads = 0
        compose.setContent { BcwmsTheme { Column {
            ExcelItemLabelsCard(loadPreparedRows = { loads++; apiRows })
        } } }
        compose.onNodeWithText(PreparedItemLabels.BUTTON).performClick()
        compose.onNodeWithText("1535 satır → 1535 etiket").assertIsDisplayed()
        compose.onNodeWithText("15.10.2026 tarihli hazır göz listesi.").assertIsDisplayed()
        compose.onNodeWithText("Tümünü yazdır (1535)").assertIsDisplayed()
        assertEquals(1, loads)
    }

    @Test fun actualWorkbookParsesOnAndroid() {
        val rows = InstrumentationRegistry.getInstrumentation().context.assets
            .open("dkc-labels-2026-10-15.xlsx").use(ExcelLabelImport::read)
        assertEquals(1535, rows.size)
        assertEquals(1227, rows.map { it.itemNo }.distinct().size)
        assertEquals((1..1535).toList(), rows.map { it.order })
        assertEquals("HK0808", rows.first().itemNo)
    }

    @Test fun fullWorkbookPreviewKeepsPrintButtonReachable() {
        val rows = InstrumentationRegistry.getInstrumentation().context.assets
            .open("dkc-labels-2026-10-15.xlsx").use(ExcelLabelImport::read)
        compose.setContent { BcwmsTheme { ExcelLabelsPreview(rows, false, onDismiss = {}, onPrint = {}) } }
        compose.onNodeWithText("1535 satır → 1535 etiket").assertIsDisplayed()
        compose.onNodeWithText("Tümünü yazdır (1535)").assertIsDisplayed()
        val file = java.io.File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "excel-label-preview.png")
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        android.os.SystemClock.sleep(500)
        file.outputStream().use {
            InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
                .compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
        compose.onNode(hasScrollAction()).performScrollToIndex(rows.lastIndex)
        val last = rows.last()
        compose.onNodeWithText("${last.order}. ${last.itemNo}  •  ${last.bin}").assertIsDisplayed()
        compose.onNodeWithText("Tümünü yazdır (1535)").assertIsDisplayed()
    }

    @Test fun previewPreservesRepeatedItemsAndDisablesDoubleSubmission() {
        var submissions = 0
        compose.setContent {
            var busy by remember { mutableStateOf(false) }
            BcwmsTheme { ExcelLabelsPreview(
                rows = listOf(ExcelLabelRow(1, "00123", "Rulman", "A1"), ExcelLabelRow(2, "00123", "Rulman", "A2")),
                busy = busy, onDismiss = {}, onPrint = { submissions++; busy = true },
            ) }
        }
        compose.onNodeWithText("2 satır → 2 etiket").assertIsDisplayed()
        compose.onNodeWithText("1. 00123  •  A1").assertIsDisplayed()
        compose.onNodeWithText("2. 00123  •  A2").assertIsDisplayed()
        compose.onNodeWithText("Tümünü yazdır (2)").performClick().assertIsNotEnabled()
        assertEquals(1, submissions)
    }
}
