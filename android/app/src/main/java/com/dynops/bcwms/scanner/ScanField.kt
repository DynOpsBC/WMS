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
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.dynops.bcwms.ui.WmsGlyph
import com.dynops.bcwms.ui.WmsIcon
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.platform.InterceptPlatformTextInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import kotlinx.coroutines.awaitCancellation

/**
 * Kitoko (22 Eki 2026): "sürekli alttan klavye açılmasın". Okutma alanları
 * odaklanınca ekran klavyesi açılmaz; donanım tarayıcı (ScanBus intent'i ve
 * tuş olayları) odaklı alana yazmaya devam eder. Elle yazmak için alanın
 * yanındaki ⌨ düğmesi klavyeyi açar. BADE/EMU/DynOps davranışı değişmez.
 */
internal fun scanFieldSuppressesKeyboard(flavor: String = com.dynops.bcwms.BuildConfig.FLAVOR): Boolean =
    flavor.equals("kitoko", ignoreCase = true)

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
    // Kitoko (19 Eki 2026): EMU etiket ekranlarından. okButton=false OK düğmesini
    // gizler; autoFocus alanı açılışta odaklar; onClear verilirse alanda temizle (×) çıkar.
    okButton: Boolean = true,
    autoFocus: Boolean = false,
    onClear: (() -> Unit)? = null,
    // Kitoko: okutma alanında ekran klavyesi yalnız ⌨ ile açılır.
    suppressKeyboard: Boolean = scanFieldSuppressesKeyboard(),
    // false: donanım okutmalarını ekran düzeyindeki yönlendirici alır (Kitoko ad-hoc).
    listenScanBus: Boolean = true,
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
    // ⌨ ile elle giriş istendi mi? Alan odağı kaybedince yine klavyesiz moda döner.
    val manualKeyboardState = remember { mutableStateOf(false) }
    var manualKeyboard by manualKeyboardState
    val internalFocusRequester = remember { androidx.compose.ui.focus.FocusRequester() }
    val fieldFocusRequester = focusRequester ?: internalFocusRequester
    val keyboardController = LocalSoftwareKeyboardController.current
    val imeBottom = WindowInsets.ime.getBottom(LocalDensity.current)
    var wasFocused by remember { mutableStateOf(false) }
    var refocusing by remember { mutableStateOf(false) }
    val focusManager = androidx.compose.ui.platform.LocalFocusManager.current
    LaunchedEffect(isFocused) {
        if (isFocused) wasFocused = true
        else if (wasFocused && !refocusing) { wasFocused = false; manualKeyboard = false }
    }
    // Yedek koruma: başka bir alanın açtığı klavye bu alana geçince kapanır.
    LaunchedEffect(isFocused, imeBottom, manualKeyboard, suppressKeyboard) {
        if (suppressKeyboard && !scanOnly && isFocused && !manualKeyboard && imeBottom > 0) keyboardController?.hide()
    }
    LaunchedEffect(manualKeyboard) {
        if (manualKeyboard && suppressKeyboard) {
            // Giriş oturumu odak alınırken başlar: klavyeye izin verip odağı yenile.
            refocusing = true
            try {
                if (isFocused) { focusManager.clearFocus(force = true); kotlinx.coroutines.delay(60) }
                runCatching { fieldFocusRequester.requestFocus() }
                kotlinx.coroutines.delay(80)
                keyboardController?.show()
            } finally { refocusing = false }
        }
    }
    val windowFocused = androidx.compose.ui.platform.LocalWindowInfo.current.isWindowFocused
    LaunchedEffect(isFocused, enabled, windowFocused, listenScanBus) {
        if (!listenScanBus || !isFocused || !enabled || !windowFocused) return@LaunchedEffect
        ScanBus.events.collect { event ->
            deliverScan(event.raw)
        }
    }

    if (autoFocus) {
        LaunchedEffect(Unit) {
            kotlinx.coroutines.delay(120)
            runCatching { fieldFocusRequester.requestFocus() }
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
            if (scanOnly) {
                Column(Modifier.weight(1f)) {
                    ScannerTextField(
                        label = label,
                        enabled = enabled,
                        focusRequester = focusRequester ?: remember { androidx.compose.ui.focus.FocusRequester() },
                        interactionSource = interactionSource,
                        modifier = Modifier.fillMaxWidth(),
                        onScanned = { deliverScan(it) },
                    )
                }
            } else Box(Modifier.weight(1f)) { KeyboardPolicy(suppress = suppressKeyboard, manual = manualKeyboardState) { OutlinedTextField(
                value = value,
                onValueChange = onValueChange,
                label = { Text(label) },
                singleLine = true,
                enabled = enabled,
                interactionSource = interactionSource,
                trailingIcon = if (onClear != null && value.isNotEmpty() && enabled) {
                    {
                        IconButton(
                            onClick = { onValueChange(""); onClear() },
                            modifier = Modifier.semantics { contentDescription = "Alanı temizle" },
                        ) {
                            WmsIcon(
                                glyph = WmsGlyph.CLOSE,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                    }
                } else null,
                // Elle giriş: klavye "bitti"/Enter → okutmayı tetikle (emülatörde ve
                // gerçek cihazda yazıp Enter'a basınca donanım taraması gibi işlenir).
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = {
                    if (enabled && !scanOnly) {
                        if (value.isBlank()) emptyHint = true else { emptyHint = false; onScanned?.invoke(value.trim()) }
                    }
                }),
                // Ekran akışı alanı programatik odaklayabilsin (sadece-okut sayım):
                // donanım tarayıcı yalnız odaklı alana yazar.
                modifier = Modifier.fillMaxWidth().focusRequester(fieldFocusRequester),
            ) } }
            if (suppressKeyboard && !scanOnly) {
                Spacer(Modifier.width(4.dp))
                IconButton(
                    enabled = enabled,
                    onClick = {
                        if (manualKeyboard) { manualKeyboard = false; keyboardController?.hide() }
                        else manualKeyboard = true
                    },
                    modifier = Modifier.semantics { contentDescription = if (manualKeyboard) "Klavyeyi kapat" else "Klavyeyle yaz" },
                ) { Text("⌨", fontSize = 20.sp, color = if (manualKeyboard) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            Spacer(Modifier.width(8.dp))
            // Elle giriş için "OK" — yazıp bas, hemen işlensin (Enter'a alternatif).
            if (onScanned != null && !scanOnly && okButton) {
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

/**
 * Kitoko: [suppress] iken alan odaklansa da ekran klavyesi için giriş oturumu
 * açılmaz (Compose InterceptPlatformTextInput). [manual] true olunca istek
 * normal yoldan geçer (⌨). Donanım tuş olayları ve ScanBus etkilenmez.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun KeyboardPolicy(suppress: Boolean, manual: State<Boolean>, content: @Composable () -> Unit) {
    if (!suppress) { content(); return }
    InterceptPlatformTextInput(
        interceptor = { request, nextHandler ->
            if (manual.value) nextHandler.startInputMethod(request) else awaitCancellation()
        },
        content = content,
    )
}
