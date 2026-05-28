package com.dynops.bcwms.scanner

import android.Manifest
import android.content.pm.PackageManager
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors

/**
 * A scan input: a labelled text field with a "Scan" button.
 * Tapping Scan opens an in-place CameraX + ML Kit preview; the first decoded barcode
 * is returned via [onScanned]. If the camera permission is denied or the camera is
 * unavailable (common in emulators), the field degrades to manual keyboard entry —
 * the text field stays fully usable.
 */
@Composable
fun ScanField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    onScanned: ((String) -> Unit)? = null,
    enabled: Boolean = true,
) {
    val context = LocalContext.current
    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED
        )
    }
    var scanning by remember { mutableStateOf(false) }
    var cameraError by remember { mutableStateOf<String?>(null) }

    val permLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasCameraPermission = granted
        if (granted) scanning = true else cameraError = "Kamera izni reddedildi — elle giriş yapın."
    }

    Column(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = value,
                onValueChange = onValueChange,
                label = { Text(label) },
                singleLine = true,
                enabled = enabled,
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(8.dp))
            FilledTonalButton(
                enabled = enabled,
                onClick = {
                    cameraError = null
                    if (hasCameraPermission) scanning = !scanning
                    else permLauncher.launch(Manifest.permission.CAMERA)
                }
            ) { Text(if (scanning) "✕" else "📷") }
        }
        cameraError?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
        if (scanning && hasCameraPermission) {
            CameraBarcodePreview(
                modifier = Modifier.fillMaxWidth().height(220.dp).padding(top = 8.dp),
                onError = { cameraError = "Kamera açılamadı — elle giriş yapın."; scanning = false },
                onBarcode = { code ->
                    scanning = false
                    onValueChange(code)
                    onScanned?.invoke(code)
                }
            )
        }
    }
}

@Composable
private fun CameraBarcodePreview(
    modifier: Modifier = Modifier,
    onBarcode: (String) -> Unit,
    onError: () -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }
    var delivered by remember { mutableStateOf(false) }

    DisposableEffect(Unit) {
        onDispose { analysisExecutor.shutdown() }
    }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            val previewView = PreviewView(ctx)
            val providerFuture = ProcessCameraProvider.getInstance(ctx)
            providerFuture.addListener({
                try {
                    val provider = providerFuture.get()
                    val preview = Preview.Builder().build().also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }
                    val scanner = BarcodeScanning.getClient()
                    val analysis = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                    analysis.setAnalyzer(analysisExecutor) { proxy ->
                        @Suppress("UnsafeOptInUsageError")
                        val media = proxy.image
                        if (media == null || delivered) { proxy.close(); return@setAnalyzer }
                        val input = InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees)
                        scanner.process(input)
                            .addOnSuccessListener { codes ->
                                val raw = codes.firstOrNull()?.rawValue
                                if (!raw.isNullOrBlank() && !delivered) {
                                    delivered = true
                                    onBarcode(raw)
                                }
                            }
                            .addOnCompleteListener { proxy.close() }
                    }
                    provider.unbindAll()
                    provider.bindToLifecycle(
                        lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis
                    )
                } catch (e: Exception) {
                    Log.e("ScanField", "camera bind failed", e)
                    onError()
                }
            }, ContextCompat.getMainExecutor(ctx))
            previewView
        }
    )
}
