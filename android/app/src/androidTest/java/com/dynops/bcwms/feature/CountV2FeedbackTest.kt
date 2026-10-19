package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.ui.BcwmsTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.unit.dp
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Rule
import org.junit.Test

class CountV2FeedbackTest {
    @get:Rule val compose = createComposeRule()

    private fun screenshot(name: String) {
        val instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        val file = java.io.File(instrumentation.targetContext.getExternalFilesDir(null), name)
        val roots = compose.onAllNodes(isRoot())
        val bitmap = roots[roots.fetchSemanticsNodes().lastIndex].captureToImage().asAndroidBitmap()
        file.outputStream().use {
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
    }

    @Test fun duplicateLpErrorIsModalAndCanBeShownAgainAfterAcknowledgement() {
        val message = "LP000077 LP, 1. sayımda A.A08.22 rafında zaten pozitif miktarla sayılmış. Önce o okutmayı geri alın veya miktarını düzeltin."
        compose.setContent {
            var status by remember { mutableStateOf("") }
            MaterialTheme {
                Button(onClick = { status = "HATA: $message" }) { Text("LP okut") }
                CountV2ErrorDialog(status, onDismiss = { status = "" })
            }
        }
        repeat(2) {
            compose.onNodeWithText("LP okut").performClick()
            compose.onNode(isDialog()).assertExists()
            compose.onNodeWithText(message).assertIsDisplayed()
            if (it == 0) screenshot("count-v2-popup.png")
            compose.onNodeWithText("Tamam").performClick()
            compose.onNode(isDialog()).assertDoesNotExist()
        }
    }

    @Test fun actualCountCardsShowGreenRedAndYellowWithAuditableAddresses() {
        fun row(bin: String, qty: Double, system: Double, lp: String) = org.json.JSONObject()
            .put("itemNo", "AB.00175").put("lotNo", "A101812").put("unitOfMeasureCode", "ADET")
            .put("binCode", bin).put("lpNo", lp).put("counted1", true).put("countedQty1", qty).put("systemQty", system)
        val correct = row("A.B06.12", 10.0, 10.0, "LP000078")
        val missing = row("A.A08.22", 0.0, 10.0, "LP000077")
        val finding = row("A.B07.11", 10.0, 0.0, "LP000077")
            .put("foundFromBin", "A.A08.22").put("foundLpQty", 10.0)
        compose.setContent { BcwmsTheme { Column(
            Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.25f)).systemBarsPadding().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("Sayım sonuçları", fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Text("3 satır · Örnek sayım", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            CountV2LineCard(correct, 1)
            CountV2LineCard(missing, 1)
            CountV2LineCard(finding, 1)
        } } }
        compose.onNodeWithText("Raf ve miktar doğru").assertIsDisplayed()
        compose.onNodeWithText("Miktar farkı").assertIsDisplayed()
        compose.onNodeWithText("Farklı rafta bulunan LP").assertIsDisplayed()
        compose.onNodeWithText("Bulunan raf").assertIsDisplayed()
        compose.onNodeWithText("A.B07.11").assertIsDisplayed()
        compose.onAllNodesWithText("A.A08.22").assertCountEquals(2)
        screenshot("count-v2-result-colors.png")
    }

    @Test fun binFindingKeepsBothAddressesAndAlsoShowsQuantityDifference() {
        val line = org.json.JSONObject().put("foundFromBin", "A.A08.22").put("binCode", "A.B07.11")
            .put("foundLpQty", 10.0).put("counted1", true).put("countedQty1", 8.0)
        compose.setContent { MaterialTheme { CountV2BinFindingDetails(line, 1) } }
        compose.onNodeWithText("A.A08.22").assertIsDisplayed()
        compose.onNodeWithText("A.B07.11").assertIsDisplayed()
        compose.onNodeWithText("LP miktar farkı: -2 · Kayıtlı LP miktarı: 10").assertIsDisplayed()
    }

    @Test fun successfulScanDoesNotOpenErrorDialog() {
        compose.setContent { MaterialTheme {
            CountV2ErrorDialog("TAMAM: LP LP000077 sayıldı", onDismiss = {})
        } }
        compose.onNode(isDialog()).assertDoesNotExist()
    }

    @Test fun sameItemAndLotRemainDistinguishableByLpAndLooseStockIsExplicit() {
        compose.setContent { MaterialTheme { Column {
            Text("AB.00175 · Lot: A101812")
            CountV2LpIdentity("LP000077")
            Text("AB.00175 · Lot: A101812")
            CountV2LpIdentity("LP000080")
            CountV2LpIdentity("")
        } } }
        compose.onNodeWithText("LP: LP000077").assertIsDisplayed()
        compose.onNodeWithText("LP: LP000080").assertIsDisplayed()
        compose.onNodeWithText("LP: Yok (LP’siz stok)").assertIsDisplayed()
        screenshot("count-v2-lp-identity.png")
    }
}
