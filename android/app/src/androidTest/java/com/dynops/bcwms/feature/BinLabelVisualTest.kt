package com.dynops.bcwms.feature

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Rule
import org.junit.Test
import java.io.File

class BinLabelVisualTest {
    @get:Rule val compose = createComposeRule()

    @Test fun documentAndLookupRender() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val bitmap = Bitmap.createBitmap(1120, 770, Bitmap.Config.ARGB_8888)
        drawBinLabel(Canvas(bitmap), JSONObject().put("code", "A.B04.13").put("locationCode", "DKC")
            .put("zoneCode", "DEPO-01").put("binTypeCode", "PICK").put("description", "Hammadde / Ürün rafı"))
        File(context.getExternalFilesDir(null), "bin-a3-preview.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(
            "cp ${File(context.getExternalFilesDir(null), "bin-a3-preview.png").absolutePath} /sdcard/Download/bin-a3-preview.png"
        ).use { descriptor -> java.io.FileInputStream(descriptor.fileDescriptor).use { it.readBytes() } }
        bitmap.recycle()
        compose.setContent { MaterialTheme {
            InquiryPickerDialog("Raf seç · DKC", listOf("A.B04.13" to "Bölge DEPO-01 · Hammadde", "B.01" to "Paketleme"), {}, {})
        } }
        compose.onNode(hasSetTextAction()).performTextInput("hammadde")
        compose.onNodeWithText("A.B04.13").assertIsDisplayed()
        compose.onNodeWithText("B.01").assertDoesNotExist()
        compose.onNode(hasSetTextAction()).performTextClearance()
        compose.onNode(hasSetTextAction()).performTextInput("bulunmayan")
        compose.onNodeWithText("Eşleşen kayıt yok. Aramayı değiştirin.").assertIsDisplayed()
    }
}
