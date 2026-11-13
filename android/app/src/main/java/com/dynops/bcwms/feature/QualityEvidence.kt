package com.dynops.bcwms.feature

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.dynops.bcwms.BcApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

internal const val MAX_QUALITY_EVIDENCE_BYTES = 5 * 1024 * 1024

/** The server validates permission, exact inspection revision and decision requirements. */
@Composable
internal fun QualityEvidence(inspectionId: String, enabled: Boolean) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selected by remember(inspectionId) { mutableStateOf<Uri?>(null) }
    var cameraUri by remember { mutableStateOf<Uri?>(null) }
    var description by remember(inspectionId) { mutableStateOf("") }
    var status by remember(inspectionId) { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) selected = uri
    }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        if (ok) selected = cameraUri
    }
    fun takePhoto() {
        try {
            val folder = File(context.cacheDir, "quality-evidence").apply { mkdirs() }
            cameraUri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", File.createTempFile("quality-", ".jpg", folder))
            camera.launch(cameraUri!!)
        } catch (_: Exception) { status = "Kamera açılamadı. Dosya seçerek ekleyebilirsiniz." }
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) takePhoto() else status = "Fotoğraf için kamera izni gerekiyor. Dosya da seçebilirsiniz."
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("Fotoğraf / Belge ekle")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(enabled = enabled && !busy, onClick = {
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) takePhoto()
                else permission.launch(Manifest.permission.CAMERA)
            }) { Text("Fotoğraf çek") }
            OutlinedButton(enabled = enabled && !busy, onClick = { picker.launch(arrayOf("image/jpeg", "image/png", "application/pdf")) }) { Text("Dosya seç") }
        }
        if (selected != null) {
            OutlinedTextField(description, { description = it.take(250) }, label = { Text("Ek açıklaması") }, enabled = !busy, modifier = Modifier.fillMaxWidth())
            Button(enabled = enabled && !busy, onClick = {
                val uri = selected ?: return@Button
                scope.launch {
                    busy = true
                    try {
                        val payload = withContext(Dispatchers.IO) {
                            val bytes = context.contentResolver.openInputStream(uri)?.use { stream ->
                                val buffer = ByteArray(8192)
                                val output = java.io.ByteArrayOutputStream()
                                while (output.size() <= MAX_QUALITY_EVIDENCE_BYTES) {
                                    val count = stream.read(buffer, 0, minOf(buffer.size, MAX_QUALITY_EVIDENCE_BYTES + 1 - output.size()))
                                    if (count < 0) break
                                    output.write(buffer, 0, count)
                                }
                                output.toByteArray() }
                                ?: error("Dosya okunamadı.")
                            require(bytes.isNotEmpty() && bytes.size <= MAX_QUALITY_EVIDENCE_BYTES) { "Dosya boş olamaz; en fazla 5 MB seçin." }
                            var name = "quality-photo.jpg"
                            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                                if (cursor.moveToFirst()) name = cursor.getString(0)
                            }
                            JSONObject().put("fileName", name).put("description", description)
                                .put("contentBase64", Base64.encodeToString(bytes, Base64.NO_WRAP)).toString()
                        }
                        val base = "${BcApi.BC_RESOURCE}/v2.0/${BcApi.getTenant(context)}/${BcApi.getEnvironment(context)}/api/dynops/element4/v1.0/companies(${BcApi.getCompanyId(context)})"
                        val result = BcApi.post(context, "$base/evidenceInspections($inspectionId)/Microsoft.NAV.addEvidence", payload)
                        if (result.ok) {
                            selected = null; description = ""; status = "Ek BC muayenesine kaydedildi. Başka bir ek ekleyebilirsiniz."
                        } else status = BcApi.errorMessage(result.body)
                    } catch (error: Exception) { status = error.message ?: "Ek kaydedilemedi." }
                    finally { busy = false }
                }
            }) { Text(if (busy) "Kaydediliyor…" else "Seçilen eki kaydet") }
        }
        if (status.isNotBlank()) Text(status)
    }
}
