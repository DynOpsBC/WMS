package com.dynops.bcwms.feature

import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.dynops.bcwms.ui.BcwmsTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class BinLabelWorkflowTest {
    @get:Rule val compose = createComposeRule()

    @Test fun bulkReviewShowsTotalAndPreventsRepeatSubmission() {
        var submissions = 0
        compose.setContent {
            var copies by remember { mutableStateOf("1") }
            BcwmsTheme {
                BinLabelPrintSheet("Toplu raf etiketi", "DKC / HAMMADDE / A · 8 raf", 8, false,
                    copies, { copies = it }, false, {}, false, "", { submissions++ }, {},
                    printerContent = { Text("Test yazıcısı") })
            }
        }
        compose.onNodeWithText("8 raf × 1 adet = 8 etiket").assertIsDisplayed()
        compose.onNodeWithText("+").performClick()
        compose.onNodeWithText("8 raf × 2 adet = 16 etiket").assertIsDisplayed()
        compose.onNodeWithText("16 etiket yazdır").performClick()
        assertEquals(1, submissions)
        compose.onNodeWithText("16 etiket yazdır").assertIsNotEnabled()
    }

    @Test fun areaLabelDoesNotOfferShelfDocumentOutput() {
        compose.setContent { BcwmsTheme {
            BinLabelPrintSheet("Alan etiketi yazdır", "DKC / HAMMADDE", 1, true,
                "1", {}, false, {}, false, "", {}, {}, printerContent = { Text("Test yazıcısı") })
        } }
        compose.onNodeWithText("A4 belge").assertDoesNotExist()
        compose.onNodeWithText("1 etiket yazdır").assertIsEnabled()
    }

    @Test fun documentOutputDoesNotRequireLabelQuantity() {
        var documentSelected = false
        compose.setContent {
            var document by remember { mutableStateOf(false) }
            BcwmsTheme {
                BinLabelPrintSheet("Raf etiketi yazdır", "DKC / A01", 1, false,
                    "", {}, document, { document = it }, false, "", { documentSelected = document }, {},
                    printerContent = { Text("Test yazıcısı") })
            }
        }
        compose.onNodeWithText("0 etiket yazdır").assertIsNotEnabled()
        compose.onNodeWithText("A4 belge").performClick()
        compose.onNodeWithText("A4 belgeyi aç").performClick()
        assertEquals(true, documentSelected)
    }
}
