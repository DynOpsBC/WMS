package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test
import java.io.File

class CountRoundComparisonVisualTest {
    @get:Rule val compose = createComposeRule()

    @Test fun movedLpHasBothRoundSnapshotsOnSmallTerminal() {
        compose.setContent {
            MaterialTheme {
                Column(Modifier.width(300.dp)) {
                    Text("1. tur                         2. tur (son)")
                    CountRoundComparisonCard(CountRoundComparison(
                        "HM.00169 · Uzun ürün açıklaması · LP: LP000123 · KG",
                        CountRoundValues(10.0, 12.0, "A.A08.22", "A.B07.11"),
                        CountRoundValues(12.0, 11.0, "A.B07.11", "A.B07.11"),
                    ))
                }
            }
        }
        compose.onNodeWithText("Sistem rafı: A.A08.22").assertIsDisplayed()
        compose.onNodeWithText("Sistem rafı: A.B07.11").assertIsDisplayed()
        compose.onNodeWithText("Stok farkı: 2").assertIsDisplayed()
        compose.onNodeWithText("Stok farkı: -1").assertIsDisplayed()
        compose.onNodeWithText("Turlar arası miktar farkı: -1").assertIsDisplayed()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val destination = File(instrumentation.targetContext.getExternalFilesDir(null), "count-round-comparison.png")
        destination.outputStream().use { instrumentation.uiAutomation.takeScreenshot().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
    }

    @Test fun missingAndUncountedRemainDistinct() {
        compose.setContent {
            MaterialTheme {
                CountRoundComparisonCard(CountRoundComparison("ITEM2", null, CountRoundValues(5.0, null, "A1", "—")))
            }
        }
        compose.onNodeWithText("Bu turda satır yok").assertIsDisplayed()
        compose.onNodeWithText("Sayılan: Tamamlanmadı").assertIsDisplayed()
    }
}
