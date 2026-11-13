package com.dynops.bcwms.feature

import android.graphics.Bitmap
import android.widget.EditText
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.replaceText
import androidx.test.espresso.matcher.ViewMatchers.isAssignableFrom
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.ScanBus
import com.dynops.bcwms.scanner.ScanEvent
import com.dynops.bcwms.ui.BcwmsTheme
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import java.io.File

class ItemStockDistributionTest {
    @get:Rule val compose = createComposeRule()
    private fun row(bin: String = "RAF-1", quantity: Double = 500.0, uom: String = "ADET") = JSONObject()
        .put("locationCode", "DEPO").put("binCode", bin).put("zoneCode", "HAMMADDE")
        .put("quantity", quantity).put("qtyBaseUoM", quantity).put("unitOfMeasureCode", uom)

    @Composable private fun StockList(load: suspend () -> BcApi.PagedItemsResult) {
        val state = rememberItemStockDistribution("TEST-URUN", "TEST-URUN", load)
        LazyColumn(Modifier.fillMaxSize().testTag("stock-list")) { itemStockDistribution(state, "ADET") }
    }

    @Test fun allRowsAppearImmediatelyWithZoneUnitVariantAndNegativeQuantity() {
        compose.setContent { BcwmsTheme(darkTheme = false) { StockList {
            BcApi.PagedItemsResult(listOf(row(), row("RAF-2", 200.0),
                row("RAF-3", -2.0, "KOLI").put("qtyBaseUoM", -20).put("variantCode", "MAVI")), true)
        } } }
        compose.onAllNodesWithText("500 ADET")[0].assertIsDisplayed()
        compose.onNodeWithText("200 ADET").assertIsDisplayed()
        compose.onNodeWithText("-2 KOLI").assertIsDisplayed()
        compose.onNodeWithText("680 ADET").assertIsDisplayed()
        compose.onNodeWithText("Varyant: MAVI").assertIsDisplayed()
        compose.onAllNodesWithText("HAMMADDE")[0].assertIsDisplayed()
        compose.onNodeWithText("DEPO · Alan: HAMMADDE").assertDoesNotExist()
        compose.onNodeWithText("Dağılım").assertDoesNotExist()
    }

    @Test fun incompleteResponseIsHiddenAndRetryLoadsCompleteStock() {
        var requests = 0
        compose.setContent { BcwmsTheme(darkTheme = false) { StockList {
            requests++
            BcApi.PagedItemsResult(listOf(row()), requests > 1)
        } } }
        compose.onNodeWithText("Raf stokları alınamadı. Tekrar deneyin.").assertIsDisplayed()
        compose.onNodeWithText("RAF-1").assertDoesNotExist()
        compose.onNodeWithText("Tekrar dene").performClick()
        compose.onAllNodesWithText("500 ADET")[0].assertIsDisplayed()
    }

    @Test fun emptyStockIsExplicit() {
        compose.setContent { BcwmsTheme(darkTheme = false) { StockList {
            BcApi.PagedItemsResult(listOf(row(quantity = 0.0)), true)
        } } }
        compose.onNodeWithText("Bu ürün için stok bulunan bin / depo gözü yok.").assertIsDisplayed()
    }

    @Test fun longResultsUseOneScrollableList() {
        compose.setContent { BcwmsTheme(darkTheme = false) { StockList {
            BcApi.PagedItemsResult((1..40).map { row("RAF-${it.toString().padStart(2, '0')}") }, true)
        } } }
        compose.onNodeWithTag("stock-list").performScrollToNode(hasText("RAF-40"))
        compose.onNodeWithText("RAF-40").assertIsDisplayed()
    }

    @Test fun stockNoteIsCollapsedAndDuplicateZoneIsHidden() {
        compose.setContent { BcwmsTheme(darkTheme = false) { StockList {
            BcApi.PagedItemsResult(listOf(row("HM1").put("zoneCode", "HM1")), true)
        } } }
        compose.onAllNodesWithText("HM1").assertCountEquals(1)
        val note = "Satırlar kendi biriminde, depo toplamları temel birimdedir. Bin takibi olmayan stoklar dahil değildir."
        compose.onNodeWithText(note).assertDoesNotExist()
        compose.onNodeWithText("Stok bilgisi ⓘ").performClick()
        compose.onNodeWithText(note).assertIsDisplayed()
    }

    @Test fun narrowDarkCardsKeepLargeTextAndQuantityVisible() {
        compose.setContent {
            val density = androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides
                androidx.compose.ui.unit.Density(density.density, 1.8f)) {
                BcwmsTheme(darkTheme = true) {
                    Box(Modifier.width(androidx.compose.ui.unit.Dp(240f))) { StockList {
                        BcApi.PagedItemsResult(listOf(row("MONTAJ-RAF-12", 12345.25, "KOLI")), true)
                    } }
                }
            }
        }
        compose.onNodeWithTag("stock-list").performScrollToNode(hasText("MONTAJ-RAF-12"))
        compose.onNodeWithText("MONTAJ-RAF-12").assertIsDisplayed()
        compose.onAllNodesWithText("12.345,25 KOLI")[0].assertIsDisplayed()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        File(instrumentation.targetContext.filesDir, "stock-cards-narrow-dark.png").outputStream().use {
            instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, it)
        }
    }

    @Test fun qrAndItemSubmissionQueryWhileLpSubmissionOpensLpCard() {
        val items = mutableListOf<String>()
        val lps = mutableListOf<LpScanRef>()
        compose.setContent { BcwmsTheme(darkTheme = false) {
            var query by remember { mutableStateOf("") }
            Column { StockInquiryInput(query, { query = it }, false, false, { items += it }, { lps += it }) }
        } }
        val field = onView(isAssignableFrom(EditText::class.java))
        field.perform(replaceText("P-00001"))
        compose.onNodeWithText("🔎 Sorgula").performClick()
        field.perform(replaceText("MADDE KODU=P-00002; LOT NO=TEST"))
        compose.onNodeWithText("🔎 Sorgula").performClick()
        field.perform(replaceText("LP0001"))
        compose.onNodeWithText("🔎 Sorgula").performClick()
        compose.runOnIdle {
            assertEquals(listOf("P-00001", "P-00002"), items)
            assertEquals(listOf(LpScanRef.ByNo("LP0001")), lps)
        }
    }

    @Test fun hardwareScanStillWorksAfterInputScrollsOffscreen() {
        val queries = mutableListOf<String>()
        val lps = mutableListOf<LpScanRef>()
        compose.setContent { BcwmsTheme(darkTheme = false) {
            var query by remember { mutableStateOf("") }
            StockInquiryScanListener(true) { raw -> routeStockInquiryScan(raw, { query = it }, { queries += it }, { lps += it }) }
            LazyColumn(Modifier.fillMaxSize().testTag("scan-list")) {
                item { StockInquiryInput(query, { query = it }, false, false, { queries += it }, { lps += it }) }
                items(40) { androidx.compose.material3.Text("SATIR-$it", Modifier.height(androidx.compose.ui.unit.Dp(64f))) }
            }
        } }
        compose.onNodeWithTag("scan-list").performScrollToIndex(40)
        compose.onNodeWithText("SATIR-39").assertIsDisplayed()
        compose.runOnIdle { ScanBus.emit(ScanEvent("MADDE KODU=P-00002; LOT NO=TEST", "QR")) }
        compose.waitUntil { queries.size == 1 }
        compose.runOnIdle { ScanBus.emit(ScanEvent("LP0001", "CODE128")) }
        compose.waitUntil { lps.size == 1 }
        compose.runOnIdle {
            assertEquals(listOf("P-00002"), queries)
            assertEquals(listOf(LpScanRef.ByNo("LP0001")), lps)
        }
    }

    @Test fun suppliedBcSnapshotMatchesDisplayedWarehouseStock() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val directory = instrumentation.targetContext.filesDir
        val fixture = File(directory, "bc-stock.json")
        assumeTrue("Supply a fresh BC binContents snapshot for acceptance evidence", fixture.exists())
        val snapshot = JSONObject(fixture.readText())
        val values = snapshot.getJSONArray("rows")
        val rows = (0 until values.length()).map { values.getJSONObject(it) }
        compose.setContent { BcwmsTheme(darkTheme = false) { StockList { BcApi.PagedItemsResult(rows, true) } } }
        rows.filter { it.getDouble("quantity") != 0.0 }.forEach { row ->
            compose.onNodeWithTag("stock-list").performScrollToNode(hasText(row.getString("binCode")))
            compose.onNodeWithText(row.getString("binCode")).assertIsDisplayed()
            val zone = row.optString("zoneCode")
            if (zone.isNotBlank() && zone != row.getString("binCode"))
                compose.onAllNodesWithText(zone)[0].assertIsDisplayed()
            compose.onAllNodesWithText("${formatStockQuantity(row.getDouble("quantity"))} ${row.getString("unitOfMeasureCode")}")[0].assertIsDisplayed()
        }
        compose.waitForIdle()
        File(directory, "stock-distribution-bc.png").outputStream().use {
            instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, it)
        }
    }
}
