package com.dynops.bcwms.feature

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import java.io.File

class LabelCopiesVisualTest {
    @get:Rule val compose = createComposeRule()

    @Test fun copiesFieldStepsTypesAndRejectsOutOfRange() {
        var value by mutableStateOf("1")
        compose.setContent {
            MaterialTheme {
                Surface {
                    Column(Modifier.padding(16.dp)) {
                        LabelCopiesField(value, { value = it })
                        Button(onClick = {}, enabled = parseLabelCopies(value) != null) {
                            Text("Etiket Bas · ${parseLabelCopies(value) ?: "-"} adet")
                        }
                    }
                }
            }
        }
        compose.onNodeWithText("−").assertIsNotEnabled()
        compose.onNodeWithText("+").performClick()
        compose.onNodeWithText("+").performClick()
        compose.runOnIdle { assertEquals("3", value) }
        compose.onNodeWithText("Etiket Bas · 3 adet").assertIsEnabled()
        compose.onNodeWithText("−").performClick()
        compose.runOnIdle { assertEquals("2", value) }
        compose.onNode(hasSetTextAction()).performTextReplacement("0")
        compose.onNodeWithText("1 ile 99 arasında bir adet girin.").assertExists()
        compose.onNodeWithText("Etiket Bas · - adet").assertIsNotEnabled()
        compose.onNode(hasSetTextAction()).performTextReplacement("25a")
        compose.runOnIdle { assertEquals("25", value) }
        compose.onNodeWithText("Etiket Bas · 25 adet").assertIsEnabled()
        compose.waitForIdle()

        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val file = File(context.getExternalFilesDir(null), "label-copies.png")
        file.outputStream().use { instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, it) }
        instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /sdcard/Download/label-copies.png").use {
            java.io.FileInputStream(it.fileDescriptor).use { input -> input.readBytes() }
        }
    }
}
