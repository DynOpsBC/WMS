package com.dynops.bcwms.feature

import android.graphics.Bitmap
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.ui.BcwmsTheme
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import java.io.File

class InquiryItemCardTest {
    @get:Rule val compose = createComposeRule()

    @Test fun stockSummaryKeepsDetailsAndPrintActionsSeparate() {
        val entries = listOf(
            entry("10*8 PNOM HOR", "10*8 PNOM HOR", 0.0),
            entry("5.56 B.FMJ KASE(AKS)", "HAMMADDE KASE FMJ", 3200000.0),
            entry("DSBC-32-90-PSA-N3", "FESTO PİSTON", 0.0),
        )
        var printed = ""
        var removed = ""
        compose.setContent {
            BcwmsTheme(darkTheme = false) {
                Surface {
                    var expanded by remember { mutableStateOf(entries.first().queryKey) }
                    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Ürün Sorgu", style = MaterialTheme.typography.headlineSmall)
                        Text("Ürünler (3)", style = MaterialTheme.typography.titleMedium)
                        entries.forEach { entry ->
                            InquiryItemCard(entry, expanded == entry.queryKey, false, false,
                                onToggle = { expanded = if (expanded == entry.queryKey) "" else entry.queryKey },
                                onRemove = { removed = entry.queryKey }, onPrint = { printed = entry.queryKey })
                        }
                    }
                }
            }
        }
        compose.onNodeWithText("3.200.000 ADET").assertIsDisplayed()
        compose.onNodeWithText("Sipariş miktarları").assertDoesNotExist()
        compose.onNodeWithText("Etiket adedi").assertDoesNotExist()
        compose.onNodeWithText("Stok ayrıntıları").performClick()
        compose.onNodeWithText("Gelecek (satın alma)").assertIsDisplayed()
        compose.onNodeWithText("Bu ürün için LP kaydı bulunamadı.").assertIsDisplayed()
        compose.onNodeWithText("Stok ayrıntılarını gizle").performClick()
        compose.onNodeWithText("Etiket yazdır").performClick()
        assertEquals(entries.first().queryKey, printed)
        compose.onNodeWithContentDescription("Ürünü daralt").performClick()
        compose.onNodeWithText("Kullanılabilir").assertDoesNotExist()
        compose.onAllNodesWithText("Detay")[0].performClick()
        compose.onNodeWithContentDescription("10*8 PNOM HOR ürününü listeden çıkar").performClick()
        assertEquals(entries.first().queryKey, removed)
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val file = File(instrumentation.targetContext.getExternalFilesDir(null), "inquiry-polished.png")
        file.outputStream().use { instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun entry(no: String, description: String, inventory: Double) = InquiryItemEntry(
        queryKey = no,
        item = JSONObject().put("no", no).put("description", description).put("inventory", inventory)
            .put("quantityOnPurchOrder", 100),
        lpLines = emptyList(), ledger = emptyList(), queriedLpNo = "", uom = "ADET",
    )
}
