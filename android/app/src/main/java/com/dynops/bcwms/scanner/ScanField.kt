package com.dynops.bcwms.scanner

import android.Manifest
import android.content.pm.PackageManager
import android.util.Log
import androidx.activity.compose.BackHandler
import androidx.compose.ui.focus.focusRequester
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.dynops.bcwms.ui.WmsGlyph
import com.dynops.bcwms.ui.WmsIcon
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
    focusRequester: androidx.compose.ui.focus.FocusRequester? = null,
    updateValueOnScan: Boolean = true,
    scanOnly: Boolean = false,
) {
    val context = LocalContext.current
    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED
        )
    }
    var scanning by remember { mutableStateOf(false) }
    // OK boş alanda basıldığında gösterilen ipucu.
    var emptyHint by remember { mutableStateOf(false) }
    var cameraError by remember { mutableStateOf<String?>(null) }
    // A focused collector outlives recompositions (bin/slot/document changes).
    // Resolve the current callbacks and input policy at delivery time.
    val deliverScan by rememberUpdatedState<(String) -> Unit>({ raw ->
        if (enabled && raw.isNotBlank()) {
            scanning = false
            emptyHint = false
            if (updateValueOnScan) onValueChange(raw)
            onScanned?.invoke(raw)
        }
    })
    // Hardware scanner (Zebra DataWedge) routing — sadece focuslu alan, ScanBus
    // event'lerini dinler. Bu sayede aynı ekranda birden fazla ScanField olsa
    // bile sarı tetik basışı sadece kullanıcının seçtiği alana yazar.
    val interactionSource = remember { MutableInteractionSource() }
    val isFocused by interactionSource.collectIsFocusedAsState()
    LaunchedEffect(isFocused, enabled) {
        if (!isFocused || !enabled) return@LaunchedEffect
        ScanBus.events.collect { event ->
            deliverScan(event.raw)
        }
    }

    val permLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasCameraPermission = granted
        if (granted) scanning = enabled else cameraError = if (scanOnly)
            "Kamera izni reddedildi — donanım tarayıcıyı kullanın." else "Kamera izni reddedildi — elle giriş yapın."
    }

    // Kamera önizlemesi ekrana gömülü olduğu için sistem geri tuşu önce yalnızca
    // önizlemeyi kapatmalı; aksi halde operatör belge ekranından tamamen çıkıyordu.
    BackHandler(enabled = scanning) { scanning = false }
    LaunchedEffect(enabled) { if (!enabled) scanning = false }

    Column(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = value,
                onValueChange = onValueChange,
                label = { Text(label) },
                singleLine = true,
                enabled = enabled,
                interactionSource = interactionSource,
                // Elle giriş: klavye "bitti"/Enter → okutmayı tetikle (emülatörde ve
                // gerçek cihazda yazıp Enter'a basınca donanım taraması gibi işlenir).
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = {
                    if (enabled && !scanOnly) {
                        if (value.isBlank()) emptyHint = true else { emptyHint = false; onScanned?.invoke(value.trim()) }
                    }
                }),
                readOnly = scanOnly,
                // Ekran akışı alanı programatik odaklayabilsin (sadece-okut sayım):
                // donanım tarayıcı yalnız odaklı alana yazar.
                modifier = if (focusRequester != null) Modifier.weight(1f).focusRequester(focusRequester) else Modifier.weight(1f),
            )
            Spacer(Modifier.width(8.dp))
            // Elle giriş için "OK" — yazıp bas, hemen işlensin (Enter'a alternatif).
            if (onScanned != null && !scanOnly) {
                // OK, alan boşken pasifti: operatör basıyor, hiçbir şey olmuyor
                // ve nedenini göremiyordu. Artık basılabiliyor ve ne beklendiğini
                // söylüyor (UAT: aynı sessizlik yerleştirme, ad-hoc ve paketlemede).
                FilledTonalButton(
                    enabled = enabled,
                    onClick = {
                        if (value.isBlank()) emptyHint = true else { emptyHint = false; onScanned.invoke(value.trim()) }
                    },
                ) { Text("OK") }
                Spacer(Modifier.width(6.dp))
            }
            FilledTonalButton(
                enabled = enabled,
                modifier = Modifier.semantics { contentDescription = if (scanning) "Kamerayı kapat" else "Kamera ile okut" },
                onClick = {
                    cameraError = null
                    if (hasCameraPermission) scanning = !scanning
                    else permLauncher.launch(Manifest.permission.CAMERA)
                }
            ) {
                WmsIcon(
                    glyph = if (scanning) WmsGlyph.CLOSE else WmsGlyph.SCAN,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(22.dp),
                )
            }
        }
        if (emptyHint) {
            Text(
                "Önce okutun ya da elle yazın: $label",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        cameraError?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
        if (enabled && scanning && hasCameraPermission) {
            CameraBarcodePreview(
                modifier = Modifier.fillMaxWidth().height(220.dp).padding(top = 8.dp),
                onError = {
                    cameraError = if (scanOnly) "Kamera açılamadı — donanım tarayıcıyı kullanın."
                        else "Kamera açılamadı — elle giriş yapın."
                    scanning = false
                },
                onBarcode = { code ->
                    if (scanning) deliverScan(code)
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
    val scanner = remember { BarcodeScanning.getClient() }
    val disposed = remember { java.util.concurrent.atomic.AtomicBoolean(false) }
    var cameraProvider by remember { mutableStateOf<ProcessCameraProvider?>(null) }
    var boundPreview by remember { mutableStateOf<Preview?>(null) }
    var boundAnalysis by remember { mutableStateOf<ImageAnalysis?>(null) }
    val currentOnBarcode by rememberUpdatedState(onBarcode)
    val currentOnError by rememberUpdatedState(onError)
    var delivered by remember { mutableStateOf(false) }

    DisposableEffect(Unit) {
        onDispose {
            disposed.set(true)
            boundAnalysis?.clearAnalyzer()
            val useCases = listOfNotNull(boundPreview, boundAnalysis).toTypedArray()
            if (useCases.isNotEmpty()) cameraProvider?.unbind(*useCases)
            scanner.close()
            analysisExecutor.shutdown()
        }
    }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            val previewView = PreviewView(ctx)
            val providerFuture = ProcessCameraProvider.getInstance(ctx)
            providerFuture.addListener({
                if (disposed.get()) return@addListener
                try {
                    val provider = providerFuture.get()
                    cameraProvider = provider
                    val preview = Preview.Builder().build().also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }
                    val analysis = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                    analysis.setAnalyzer(analysisExecutor) { proxy ->
                        @Suppress("UnsafeOptInUsageError")
                        val media = proxy.image
                        if (media == null || delivered || disposed.get()) { proxy.close(); return@setAnalyzer }
                        val input = InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees)
                        try {
                            scanner.process(input)
                            .addOnSuccessListener { codes ->
                                val raw = codes.firstOrNull()?.rawValue
                                if (!raw.isNullOrBlank() && !delivered && !disposed.get()) {
                                    delivered = true
                                    currentOnBarcode(raw)
                                }
                            }
                            .addOnCompleteListener { proxy.close() }
                        } catch (e: Exception) {
                            proxy.close()
                            if (!disposed.get()) {
                                Log.e("ScanField", "camera analysis failed", e)
                                ContextCompat.getMainExecutor(ctx).execute {
                                    if (!disposed.get()) currentOnError()
                                }
                            }
                        }
                    }
                    boundPreview = preview
                    boundAnalysis = analysis
                    provider.bindToLifecycle(
                        lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis
                    )
                } catch (e: Exception) {
                    Log.e("ScanField", "camera bind failed", e)
                    if (!disposed.get()) currentOnError()
                }
            }, ContextCompat.getMainExecutor(ctx))
            previewView
        }
    )
}
