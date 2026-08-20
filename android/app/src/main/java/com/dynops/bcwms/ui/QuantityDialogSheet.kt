package com.dynops.bcwms.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.ScanField
import org.json.JSONObject

data class QuantityResult(
    val quantity: Double,
    val uom: String,
    val lotNo: String,
    val serialNo: String,
    val supplierLotNo: String = "",
)

/**
 * Modal bottom sheet for capturing a quantity with optional UoM / lot / serial.
 * Includes a stepper, a big "+1" button, and Confirm / Cancel.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuantityDialogSheet(
    title: String,
    itemNo: String,
    initialQty: Double = 1.0,
    initialUom: String = "",
    initialLot: String = "",
    initialSerial: String = "",
    initialSupplierLot: String = "",
    showLotSerial: Boolean = true,
    showSerial: Boolean = showLotSerial,
    showSupplierLot: Boolean = false,
    lotRequired: Boolean = false,
    showAvailableLotLookup: Boolean = false,
    // Stoktaki lotları açılışta yoklar: lot bulunursa alan zorunlu sayılır ve
    // seçim listesi görünür. BC'deki lotRequired alanı yayınlanmamış olsa bile
    // lot takipli üründe boş lotla sevk edilmesini engeller.
    autoDetectLotFromStock: Boolean = false,
    locationCode: String = "",
    binCode: String = "",
    variantCode: String = "",
    supplierLotRequired: Boolean = false,
    onConfirm: (QuantityResult) -> Unit,
    onDismiss: () -> Unit,
) {
    var qtyText by remember { mutableStateOf(formatQty(initialQty)) }
    var uom by remember { mutableStateOf(initialUom) }
    var lot by remember { mutableStateOf(initialLot) }
    var serial by remember { mutableStateOf(initialSerial) }
    var supplierLot by remember { mutableStateOf(initialSupplierLot) }
    var showSupplierLotLookup by remember { mutableStateOf(false) }
    var showAvailableLotLookupContent by remember { mutableStateOf(false) }
    // -1 = henüz bilinmiyor / sorgulanamadı, 0 = stokta lot yok, >0 = lot var.
    var stockLotCount by remember(itemNo, locationCode, binCode, variantCode) { mutableStateOf(-1) }
    val probeContext = LocalContext.current
    LaunchedEffect(autoDetectLotFromStock, showLotSerial, itemNo, locationCode, binCode, variantCode) {
        if (!autoDetectLotFromStock || !showLotSerial || itemNo.isBlank()) return@LaunchedEffect
        stockLotCount = fetchAvailableLots(probeContext, itemNo, locationCode, binCode, variantCode)
            .getOrNull()?.size ?: -1
    }
    val effectiveLotRequired = lotRequired || stockLotCount > 0
    val lotLookupVisible = showAvailableLotLookup || stockLotCount > 0

    fun qty(): Double = qtyText.toDoubleOrNull() ?: 0.0
    fun setQty(v: Double) { qtyText = formatQty(v.coerceAtLeast(0.0)) }

    SheetScaffold(onDismiss = onDismiss) {
            if (showSupplierLotLookup) {
                SupplierLotLookupContent(
                    itemNo = itemNo,
                    onBack = { showSupplierLotLookup = false },
                    onSelect = { selectedLot, selectedSupplierLot ->
                        lot = selectedLot
                        supplierLot = selectedSupplierLot
                        showSupplierLotLookup = false
                    },
                )
                return@SheetScaffold
            }
            if (showAvailableLotLookupContent) {
                AvailableLotLookupContent(
                    itemNo = itemNo,
                    locationCode = locationCode,
                    binCode = binCode,
                    variantCode = variantCode,
                    onBack = { showAvailableLotLookupContent = false },
                    onSelect = { selectedLot ->
                        lot = selectedLot
                        showAvailableLotLookupContent = false
                    },
                )
                return@SheetScaffold
            }

            Text(title, fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Text("Ürün: $itemNo", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(16.dp))

            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedIconButton(onClick = { setQty(qty() - 1) }) { Text("−", fontSize = 22.sp) }
                OutlinedTextField(
                    value = qtyText,
                    onValueChange = { qtyText = it.filter { c -> c.isDigit() || c == '.' } },
                    label = { Text("Miktar") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                OutlinedIconButton(onClick = { setQty(qty() + 1) }) { Text("+", fontSize = 22.sp) }
            }
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = { setQty(qty() + 1) },
                modifier = Modifier.fillMaxWidth().height(52.dp)
            ) { Text("+1", fontSize = 20.sp, fontWeight = FontWeight.Bold) }

            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = uom, onValueChange = { uom = it },
                label = { Text("Ölçü Birimi (UOM)") }, singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            if (showLotSerial) {
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = lot, onValueChange = { lot = it },
                    label = { Text(if (effectiveLotRequired || supplierLotRequired) "Lot No (zorunlu)" else "Lot No (opsiyonel)") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                if (lotLookupVisible) {
                    Spacer(Modifier.height(6.dp))
                    OutlinedButton(
                        onClick = { showAvailableLotLookupContent = true },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("📦 Stoktaki Lotlardan Seç")
                    }
                }
                if (effectiveLotRequired && lot.isBlank()) {
                    Text(
                        "Lot takipli üründe sevkiyat için stoktaki bir lotu seçmelisiniz.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
            if (showSupplierLot) {
                Spacer(Modifier.height(8.dp))
                ScanField(
                    label = if (supplierLotRequired) "Tedarikçi Lotu (zorunlu)" else "Tedarikçi Lotu",
                    value = supplierLot,
                    onValueChange = { supplierLot = it },
                    modifier = Modifier.fillMaxWidth(),
                    onScanned = { scanned ->
                        val resolved = BarcodeIntentResolver.resolve(scanned)
                        supplierLot = resolved.lotNo?.takeIf(String::isNotBlank) ?: scanned.trim()
                    },
                )
                Spacer(Modifier.height(6.dp))
                OutlinedButton(
                    onClick = { showSupplierLotLookup = true },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("🔎 Tedarikçi Lotu Lookup")
                }
                if (supplierLotRequired && supplierLot.isBlank()) {
                    Text(
                        "Bu alan okutulmadan veya girilmeden mal kabul satırı onaylanamaz.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
            if (showSerial) {
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = serial, onValueChange = { serial = it },
                    label = { Text("Seri No (opsiyonel)") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("İptal") }
                Button(
                    onClick = {
                        onConfirm(
                            QuantityResult(
                                qty(), uom.trim(), lot.trim(), serial.trim(), supplierLot.trim()
                            )
                        )
                    },
                    enabled = qty() > 0 &&
                        (!effectiveLotRequired || lot.isNotBlank()) &&
                        (!supplierLotRequired || (lot.isNotBlank() && supplierLot.isNotBlank())),
                    modifier = Modifier.weight(1f)
                ) { Text("Onayla") }
            }
            Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun AvailableLotLookupContent(
    itemNo: String,
    locationCode: String,
    binCode: String,
    variantCode: String,
    onBack: () -> Unit,
    onSelect: (lotNo: String) -> Unit,
) {
    val context = LocalContext.current
    var rows by remember(itemNo, locationCode, binCode, variantCode) { mutableStateOf<List<JSONObject>>(emptyList()) }
    var loading by remember(itemNo, locationCode, binCode, variantCode) { mutableStateOf(true) }
    var error by remember(itemNo, locationCode, binCode, variantCode) { mutableStateOf("") }

    LaunchedEffect(itemNo, locationCode, binCode, variantCode) {
        loading = true
        error = ""
        fetchAvailableLots(context, itemNo, locationCode, binCode, variantCode)
            .onSuccess { rows = it }
            .onFailure { error = it.message.orEmpty() }
        loading = false
    }

    TextButton(onClick = onBack) { Text("‹ Miktar girişine dön") }
    Text("Stoktaki Lotlar", fontWeight = FontWeight.Bold, fontSize = 18.sp)
    Text(
        listOf("Ürün: $itemNo", "Lokasyon: $locationCode", binCode.takeIf(String::isNotBlank)?.let { "Raf: $it" })
            .filterNotNull()
            .joinToString(" · "),
        fontSize = 12.sp,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(12.dp))

    when {
        loading -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            CircularProgressIndicator()
        }
        error.isNotBlank() -> Text(error, color = MaterialTheme.colorScheme.error)
        rows.isEmpty() -> Text(
            "Bu lokasyon/rafta pozitif stoklu lot bulunamadı.",
            color = MaterialTheme.colorScheme.error,
        )
        else -> rows.forEach { row ->
            val lotNo = row.optString("lotNo")
            val quantityBase = row.optDouble("quantityBase", 0.0)
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = { onSelect(lotNo) },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(Modifier.fillMaxWidth()) {
                    Text(lotNo, fontWeight = FontWeight.Bold)
                    Text(
                        "Stok (temel): ${formatQty(quantityBase)}" +
                            row.optString("binCode").takeIf(String::isNotBlank)?.let { " · Raf: $it" }.orEmpty(),
                        fontSize = 12.sp,
                    )
                }
            }
        }
    }
    Spacer(Modifier.height(24.dp))
}

@Composable
private fun SupplierLotLookupContent(
    itemNo: String,
    onBack: () -> Unit,
    onSelect: (lotNo: String, supplierLotNo: String) -> Unit,
) {
    val context = LocalContext.current
    var rows by remember(itemNo) { mutableStateOf<List<JSONObject>>(emptyList()) }
    var query by remember { mutableStateOf("") }
    var loading by remember(itemNo) { mutableStateOf(true) }
    var error by remember(itemNo) { mutableStateOf("") }

    LaunchedEffect(itemNo) {
        loading = true
        error = ""
        val safeItemNo = itemNo.replace("'", "''")
        val result = BcApi.get(
            context,
            "supplierLots?\$filter=itemNo eq '$safeItemNo'&\$orderby=supplierLotNo&\$top=100",
        )
        if (result.ok) {
            rows = BcApi.parseValueArray(result.body)
        } else {
            error = if (result.httpCode == 404)
                "Lookup servisi BC'de bulunamadı. 1.14.0.20 paketini yayımlayın."
            else
                "Tedarikçi lotları alınamadı (HTTP ${result.httpCode})."
        }
        loading = false
    }

    val normalizedQuery = query.trim()
    val filteredRows = rows.filter { row ->
        normalizedQuery.isBlank() ||
            row.optString("supplierLotNo").contains(normalizedQuery, ignoreCase = true) ||
            row.optString("lotNo").contains(normalizedQuery, ignoreCase = true)
    }

    TextButton(onClick = onBack) { Text("‹ Mal kabule dön") }
    Text("Tedarikçi Lotu Lookup", fontWeight = FontWeight.Bold, fontSize = 18.sp)
    Text(
        "Ürün: $itemNo · Seçildiğinde iç lot ve tedarikçi lotu birlikte doldurulur.",
        fontSize = 12.sp,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(12.dp))
    OutlinedTextField(
        value = query,
        onValueChange = { query = it },
        label = { Text("Tedarikçi lotu veya iç lot ara") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(10.dp))

    when {
        loading -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            CircularProgressIndicator()
        }
        error.isNotBlank() -> Text(error, color = MaterialTheme.colorScheme.error)
        filteredRows.isEmpty() -> Text(
            if (rows.isEmpty()) "Bu ürün için kayıtlı tedarikçi lotu bulunamadı. Yeni lotu elle girebilir veya okutabilirsiniz."
            else "Aramayla eşleşen tedarikçi lotu bulunamadı.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        else -> filteredRows.take(50).forEach { row ->
            val supplierLotNo = row.optString("supplierLotNo")
            val lotNo = row.optString("lotNo")
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = { onSelect(lotNo, supplierLotNo) },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(Modifier.fillMaxWidth()) {
                    Text(supplierLotNo, fontWeight = FontWeight.Bold)
                    Text(
                        "İç lot: $lotNo" + row.optDouble("inventory", 0.0)
                            .takeIf { it != 0.0 }
                            ?.let { " · Stok: ${formatQty(it)}" }
                            .orEmpty(),
                        fontSize = 12.sp,
                    )
                }
            }
        }
    }
    Spacer(Modifier.height(24.dp))
}

private fun formatQty(v: Double): String =
    if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()

/**
 * Stokta pozitif bakiyesi olan lotları getirir (BC: availableLots). Hem lot seçim
 * listesi hem de "bu ürün lot takipli mi" yoklaması aynı kaynağı kullansın diye
 * ortak: iki yerde farklı filtre kurulursa liste ile zorunluluk çelişebilir.
 */
internal suspend fun fetchAvailableLots(
    context: android.content.Context,
    itemNo: String,
    locationCode: String,
    binCode: String,
    variantCode: String,
): Result<List<JSONObject>> {
    fun safe(value: String) = value.replace("'", "''")
    val filters = buildList {
        add("itemNo eq '${safe(itemNo)}'")
        if (locationCode.isNotBlank()) add("locationCode eq '${safe(locationCode)}'")
        if (binCode.isNotBlank()) add("binCode eq '${safe(binCode)}'")
        if (variantCode.isNotBlank()) add("variantCode eq '${safe(variantCode)}'")
        add("lotNo ne ''")
    }.joinToString(" and ")
    val result = BcApi.get(context, "availableLots?\$filter=$filters&\$orderby=lotNo&\$top=200")
    if (!result.ok) {
        val message = if (result.httpCode == 404)
            "Stok lot servisi BC'de bulunamadı. BCWMSApp 1.14.0.24 veya üzerini yayınlayın."
        else
            "Stoktaki lotlar alınamadı (HTTP ${result.httpCode})."
        return Result.failure(IllegalStateException(message))
    }
    return Result.success(
        BcApi.parseValueArray(result.body)
            .filter { it.optString("lotNo").isNotBlank() && it.optDouble("quantityBase", 0.0) > 0.0 }
            .sortedBy { it.optString("lotNo") }
    )
}
