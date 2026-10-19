package com.dynops.bcwms.feature

import android.graphics.Bitmap
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.ui.BcwmsTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import java.io.File

class BulkItemLabelsSheetTest {
    @get:Rule val compose = createComposeRule()

    @Test fun selectionAndIndividualCountsProduceOneBatch() {
        var submitted = emptyList<InquiryLabelJob>()
        compose.setContent {
            var result by remember { mutableStateOf<InquiryLabelBatchResult?>(null) }
            BcwmsTheme(darkTheme = false) {
                BulkItemLabelsSheet(
                    products = listOf(
                        InquiryLabelProduct("10X16X40 KAMA", "KOVAN BALTA BAĞLANTI KAMASI", "1"),
                        InquiryLabelProduct("521100-M01-005-R01", "7.62 FMJ 1. ve 2. SİVRİLTME KALIBI", "1"),
                    ), printing = false, progress = "", result = result,
                    onPrint = { submitted = it; result = InquiryLabelBatchResult(it.associate { job -> job.itemNo to job.copies }) },
                    onDismiss = {}, printerContent = { Text("Etiket yazıcısı · Test yazıcısı") },
                )
            }
        }
        compose.onNodeWithText("2 ürün · Toplam 2 etiket").assertIsDisplayed()
        compose.onNodeWithText("Seçimi kaldır").performClick()
        compose.onNodeWithText("Seçilenleri yazdır · 0 etiket").assertIsNotEnabled()
        compose.onNodeWithText("Tümünü seç").performClick()
        compose.onAllNodes(hasSetTextAction())[0].performTextClearance()
        compose.onNodeWithText("Seçilenleri yazdır · 1 etiket").assertIsNotEnabled()
        compose.onAllNodes(hasSetTextAction())[0].performTextInput("3")
        compose.onNodeWithText("2 ürün · Toplam 4 etiket").assertIsDisplayed()
        compose.onNodeWithText("Seçilenleri yazdır · 4 etiket").assertIsEnabled()
        androidx.test.espresso.Espresso.closeSoftKeyboard()
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val file = File(instrumentation.targetContext.getExternalFilesDir(null), "bulk-item-labels.png")
        file.outputStream().use { instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, it) }
        compose.onNodeWithContentDescription("521100-M01-005-R01 ürününü seç").performClick()
        compose.onNodeWithText("1 ürün · Toplam 3 etiket").assertIsDisplayed()
        compose.onNodeWithText("Seçilenleri yazdır · 3 etiket").performClick()
        assertEquals(listOf(InquiryLabelJob("10X16X40 KAMA", 3)), submitted)
        compose.onNodeWithText("Seçilenleri yazdır · 3 etiket").assertDoesNotExist()
        compose.onNodeWithText("Kapat").assertIsDisplayed()
    }

    @Test fun longListScrollsWithoutPushingPrintButtonOffscreen() {
        compose.setContent { BcwmsTheme(darkTheme = false) {
            BulkItemLabelsSheet(
                products = (0..29).map { InquiryLabelProduct("SKU-$it", "Uzun ürün açıklaması · Depo malzemesi", "1") },
                printing = false, progress = "", result = null, onPrint = {}, onDismiss = {},
                printerContent = { Text("Etiket yazıcısı · Test yazıcısı") },
            )
        } }
        compose.onNodeWithText("Seçilenleri yazdır · 30 etiket").assertIsDisplayed()
        compose.onNode(hasScrollToIndexAction()).performScrollToIndex(29)
        compose.onNodeWithText("SKU-29").assertIsDisplayed()
        compose.onNodeWithText("Seçilenleri yazdır · 30 etiket").assertIsDisplayed()
    }

}
