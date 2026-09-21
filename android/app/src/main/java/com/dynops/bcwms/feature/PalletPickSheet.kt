package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

/** All picking entry points share this sheet. No line is optimistically closed:
 * every planned pallet must be scanned and BC must accept the confirmation.
 * The registration path sends all scanned LPs to BC packages supporting
 * registerScannedFor; older packages retain their existing allocation behavior.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PalletPickSheet(
    pickNo: String,
    group: LineGroup,
    onDismiss: () -> Unit,
    onFinished: (String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val key = "$pickNo|${group.key}|${group.lines.map { it.optInt("lineNo") }}"
    var quantity by remember(key) { mutableStateOf(fmtNum(initialPalletPickQuantity(group.lines, group.totalOutstanding))) }
    var plans by remember(key) { mutableStateOf<List<PalletPickPlan>>(emptyList()) }
    var sourceBinVerified by remember(key) { mutableStateOf(false) }
    var scannedCount by remember(key) { mutableStateOf(0) }
    var scan by remember(key) { mutableStateOf("") }
    var loadError by remember(key) { mutableStateOf("") }
    var error by remember(key) { mutableStateOf("") }
    var scanMessage by remember(key) { mutableStateOf("") }
    var loading by remember(key) { mutableStateOf(false) }
    var submitting by remember(key) { mutableStateOf(false) }
    var reloadKey by remember(key) { mutableStateOf(0) }
    val steps = palletScanSteps(plans)
    val qty = quantity.replace(',', '.').toDoubleOrNull()
    val uom = group.lines.first().optString("unitOfMeasureCode")
    val canConfirm = loadError.isBlank() &&
        (qty == 0.0 || (sourceBinVerified && palletScansComplete(steps, scannedCount)))

    suspend fun loadPlans(): List<PalletPickPlan> {
        require(qty != null && qty.isFinite() && qty >= 0 && qty <= group.totalOutstanding + 0.00001) {
            "Miktar 0 ile ${fmtNum(group.totalOutstanding)} arasında olmalı."
        }
        if (qty == 0.0) return emptyList()
        val requested = distributeQty(group, qty, ::pickLineCapacity)
        require(requested.isNotEmpty()) { "Miktar satırların kalanını aşıyor. Belgeyi yenileyin." }
        return loadDocumentPalletPlans(context, pickNo, requested)
    }

    // The verified source bin belongs to the group, not to one candidate list:
    // it survives quantity edits, list refreshes and a rejected confirmation.
    LaunchedEffect(key, quantity, reloadKey) {
        plans = emptyList(); scannedCount = 0; scan = ""; loadError = ""; error = ""; scanMessage = ""; loading = true
        try {
            plans = loadPlans()
            loading = false
        } catch (e: CancellationException) {
            // A superseded reload must not clear `loading`: the replacement run
            // owns it. Doing so in a finally block re-enabled pallet scanning
            // while the new lookup was still in flight, so the scan was judged
            // against an empty list and the stale message survived the reload.
            throw e
        } catch (e: Exception) {
            loadError = e.message ?: "Paletler doğrulanamadı. Yenileyin."
            loading = false
        }
    }

    fun submitScan(raw: String) {
        if (submitting) return
        val resolved = BarcodeIntentResolver.resolve(raw)
        val value = resolved.value.trim().ifBlank { raw.trim() }
        if (value.isBlank()) return
        scan = ""
        if (!sourceBinVerified) {
            if (!acceptsSourceBin(group.binCode, value)) {
                error = sourceBinScanError(group.binCode, resolved)
                scanMessage = ""
                return
            }
            sourceBinVerified = true
            // A correct bin proves the physical address, not a successful
            // pallet lookup. Never erase that independent blocker here.
            error = ""
            scanMessage = "Raf doğrulandı: ${group.binCode}. Şimdi sıradaki paletin LP etiketini okutun."
            return
        }
        if (loading) {
            scanMessage = "Palet listesi henüz yükleniyor. Liste gelince $value paletini tekrar okutun."
            return
        }
        // Read the current candidate list, never a snapshot captured by an older composition.
        val currentSteps = palletScanSteps(plans)
        if (currentSteps.isEmpty()) {
            scanMessage = if (qty == 0.0) "Miktar sıfır. Palet toplamak için önce toplanacak miktarı girin."
            else "$value okutuldu ama palet listesi hazır değil. Hata ayrıntısını kontrol edip palet listesini yenileyin."
            return
        }
        scanMessage = ""
        if (!acceptsPalletStep(currentSteps, scannedCount, value)) {
            error = currentSteps.getOrNull(scannedCount)?.let {
                "Yanlış veya tekrar okutulan palet. Sıradaki: ${it.lpNo} · Raf: ${it.binCode} · Lot: ${it.lotNo.ifBlank { "—" }}"
            } ?: "Tüm paletler okutuldu. Satırları onaylayın."
        } else {
            scannedCount++
            error = ""
        }
    }

    val currentSubmitScan by rememberUpdatedState<(String) -> Unit>(::submitScan)
    val scanFocus = remember { androidx.compose.ui.focus.FocusRequester() }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = { !submitting })
    SheetScaffold(onDismiss = { if (!submitting) onDismiss() }, sheetState = sheetState) {
        Text("Palet Okutarak Toplama", fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Text(group.itemNo, fontWeight = FontWeight.Bold)
        Text(group.description)
        Text("Kaynak raf: ${group.binCode}")
        Text("Lot: ${group.lines.first().optString("lotNo").ifBlank { plans.firstOrNull()?.lotNo ?: "Paletten doğrulanacak" }}")
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(
            value = quantity,
            onValueChange = {
                quantity = it
                plans = emptyList(); scannedCount = 0; scanMessage = ""; loading = true
            },
            enabled = !submitting,
            label = { Text("Toplanacak miktar ($uom)") },
            supportingText = { Text("Kalan: ${fmtNum(group.totalOutstanding)} $uom · Miktar değişirse paletleri yeniden okutun.") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.fillMaxWidth(),
        )
        if (loading) {
            LinearProgressIndicator(Modifier.fillMaxWidth().padding(vertical = 12.dp))
            Text("Kaynak paletler kontrol ediliyor…")
        }
        Card(Modifier.fillMaxWidth().padding(top = 12.dp)) {
            Column(Modifier.padding(14.dp)) {
                Text(if (sourceBinVerified) "RAF DOĞRULANDI" else "1. KAYNAK RAFI OKUT", fontWeight = FontWeight.Bold)
                Text(group.binCode, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                Text(if (sourceBinVerified) "✓ Doğru raftasınız. LP okutma adımına geçebilirsiniz."
                    else "Paleti okutmadan önce fiziksel raf etiketini doğrulayın.")
            }
        }
        val current = steps.getOrNull(scannedCount)
        if (sourceBinVerified && current != null) {
            Card(Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
                Column(Modifier.padding(14.dp)) {
                    Text("SIRADAKİ PALET · ${scannedCount + 1}/${steps.size}", fontWeight = FontWeight.Bold)
                    Text(current.lpNo, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                    Text("Raf: ${current.binCode} · Lot: ${current.lotNo.ifBlank { "—" }}")
                    Text("Bu paletten al: ${fmtNum(current.quantity)} $uom", fontSize = 20.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
        // Keep the scanner available even when the candidate lookup fails.
        // A scan without a valid plan reports the blocker and never confirms stock.
        ScanField(
            label = if (sourceBinVerified) "2. Paletin QR kodunu okut" else "1. Kaynak rafın kodunu okut",
            value = scan,
            onValueChange = { scan = it },
            onScanned = { currentSubmitScan(it) },
            focusRequester = scanFocus,
            updateValueOnScan = false,
            scanOnly = true,
            // The bin can be proven while candidates load; a pallet scanned during
            // loading gets an explicit "still loading" message instead of silence.
            enabled = !submitting,
            modifier = Modifier.fillMaxWidth(),
        )
        Text(if (sourceBinVerified)
            "Terminalin tarama tuşuyla paletin QR kodunu okutun. Kod alanda beklerse Okunan Paleti Doğrula'ya basın."
        else
            "Önce ekranda yazan kaynak rafın etiketini okutun. Yanlış rafta LP kabul edilmez.",
            style = MaterialTheme.typography.bodySmall)
        LaunchedEffect(loading, submitting, sheetState.currentValue) {
            if (!submitting && sheetState.currentValue == SheetValue.Expanded) scanFocus.requestFocus()
        }
        if (scanMessage.isNotBlank()) Text(scanMessage, modifier = Modifier.padding(vertical = 8.dp))
        if (loadError.isNotBlank()) {
            Card(
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
            ) {
                Column(Modifier.padding(12.dp)) {
                    Text("Palet listesi hazırlanamadı", fontWeight = FontWeight.Bold)
                    Text(loadError)
                }
            }
        }
        if (steps.isNotEmpty()) {
            Text("${scannedCount}/${steps.size} palet adımı doğrulandı", Modifier.padding(vertical = 8.dp))
            steps.forEachIndexed { index, step ->
                Text("${if (index < scannedCount) "✓" else "${index + 1}."} ${step.lpNo} · ${step.binCode} · Lot ${step.lotNo.ifBlank { "—" }} · ${fmtNum(step.quantity)} $uom")
            }
        }
        if (error.isNotBlank()) Text(error, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(vertical = 8.dp))
        Button(
            enabled = !loading && !submitting && canConfirm,
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
            onClick = {
                if (submitting || !canConfirm) return@Button
                submitting = true
                scope.launch {
                    var accepted = 0
                    var attempted = false
                    var requestedCount = group.lines.size
                    try {
                        // A stock or candidate change invalidates the physical scan plan.
                        val fresh = loadPlans()
                        check(fresh.size == plans.size && fresh.zip(plans).all { (a, b) -> samePalletPickPlan(a, b) }) {
                            "Palet stokları değişti. Listeyi yenileyip paletleri yeniden okutun."
                        }
                        val requested = distributeQty(group, requireNotNull(qty) { "Miktar geçersiz." }, ::pickLineCapacity)
                        check(requested.isNotEmpty()) { "Miktar satırların kalanını aşıyor. Belgeyi yenileyin." }
                        requestedCount = requested.size
                        // Clear the remainder before staging the smaller positive total.
                        // Otherwise old amounts on later group lines can still be posted.
                        for ((line, amount) in requested) {
                            if (amount == 0.0) {
                                attempted = true
                                val result = BcApi.confirmPickLine(context, pickNo, line.optInt("lineNo"), 0.0, line.optString("lotNo"))
                                check(result.ok) { BcApi.errorMessage(result.body) }
                                PalletPickVerification.clear(context, pickNo, line.optInt("lineNo"))
                                accepted++
                            }
                        }
                        if (qty == 0.0) {
                            onFinished("TAMAM: $accepted satırın girilen miktarı sıfırlandı.")
                            return@launch
                        }
                        for (plan in plans) {
                            attempted = true
                            val result = BcApi.confirmPickLine(context, pickNo, plan.lineNo, plan.quantity, plan.lotNo, plan.steps.first().lpNo)
                            check(result.ok) { BcApi.errorMessage(result.body) }
                            PalletPickVerification.save(context, pickNo, plan)
                            accepted++
                        }
                        onFinished("TAMAM: $accepted satır, ${steps.size} palet adımı doğrulandı.")
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        if (attempted) {
                            // Refresh the document even after an uncertain response. Never
                            // replay a partially successful group from this stale dialog.
                            onFinished("HATA: $accepted/$requestedCount satır onaylandı. ${e.message}. Belgeyi kontrol edin.")
                        } else {
                            plans = emptyList(); scannedCount = 0
                            loadError = e.message ?: "Doğrulama başarısız. Yenileyin."
                        }
                    } finally {
                        submitting = false
                    }
                }
            },
        ) { Text(if (submitting) "BC onayı bekleniyor…" else if (qty == 0.0) "Girilen Miktarı Sıfırla" else "Okutulan Paletleri Onayla") }
        TextButton(onClick = { reloadKey++ }, enabled = !submitting && !loading) { Text("Palet listesini yenile") }
    }
}

/** Wrapped source details remain visible on narrow terminals, independent of
 * saved grid column preferences. Load the server candidates also when BC did
 * not stamp a single LP on a line that spans several pallets.
 */
@Composable
internal fun PickSourceDetails(pickNo: String, line: JSONObject) {
    val context = LocalContext.current
    var details by remember(pickNo, line.toString()) { mutableStateOf("") }
    LaunchedEffect(pickNo, line.toString()) {
        val result = BcApi.pickLineSources(context, pickNo, line.optInt("lineNo"))
        details = if (result.ok) {
            val sources = parsePickLineSources(BcApi.scalarValue(result.body))
            sources.joinToString("\n") { "Palet: ${it.lpNo} · Lot: ${it.lotNo.ifBlank { "—" }}" }
                .ifBlank { "Uygun kaynak palet bulunamadı." }
        } else "Kaynak paletler alınamadı; satırdan tekrar deneyin."
    }
    Text("Kaynak raf: ${line.optString("binCode").ifBlank { "—" }}")
    Text("Kalan: ${fmtNum(pickLineCapacity(line))} ${line.optString("unitOfMeasureCode")} · Girilen: ${fmtNum(line.optDouble("qtyToHandle", 0.0))}")
    Text(details.ifBlank { "Kaynak paletler yükleniyor…" }, fontSize = 13.sp)
}

private fun fmtNum(value: Double): String = java.math.BigDecimal.valueOf(value).setScale(5, java.math.RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()
