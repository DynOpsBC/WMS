package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.StatusText
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

// Older clients/tests still use this empty-LP payload contract. The active
// BADE screen below uses the ledger-based contract.
internal data class BulkLpBuildDraft(val id: Int, val quantity: String)

internal data class BulkLpLocationOption(val code: String, val displayName: String) {
    val label: String
        get() = if (displayName.isBlank() || displayName.equals(code, ignoreCase = true)) code
        else "$code · $displayName"
}

internal fun bulkLpLocationOptions(rows: List<JSONObject>): List<BulkLpLocationOption> =
    rows.mapNotNull { row ->
        val code = row.optString("code").trim()
        if (code.isBlank()) null
        else BulkLpLocationOption(
            code = code,
            displayName = row.optString("displayName").ifBlank { row.optString("name") }.trim(),
        )
    }.distinctBy { it.code.uppercase() }.sortedBy { it.code.uppercase() }

internal fun validBulkLpLocationSelection(
    locationCode: String,
    locationsComplete: Boolean,
    locations: List<BulkLpLocationOption>,
): Boolean = locationsComplete && locations.any { it.code.equals(locationCode.trim(), ignoreCase = true) }

internal fun commonLpQuantityDrafts(count: Int, quantity: String): List<BulkLpBuildDraft> =
    if (count !in 1..200) emptyList()
    else List(count) { index -> BulkLpBuildDraft(index + 1, quantity) }

internal fun bulkLpBuildPayload(locationCode: String, binCode: String, drafts: List<BulkLpBuildDraft>): String =
    JSONObject().apply {
        put("locationCode", locationCode.trim())
        put("binCode", binCode.trim())
        put("quantitiesJson", JSONArray().apply {
            drafts.forEach { put(it.quantity.toDoubleOrNull() ?: 0.0) }
        }.toString())
    }.toString()

internal fun validLedgerBulkLpPlan(
    lpCount: Int?,
    quantityPerLp: Double?,
    remainingQuantity: Double,
    serialNo: String,
): Boolean {
    if (lpCount == null || lpCount !in 1..100) return false
    if (quantityPerLp == null || !quantityPerLp.isFinite() || quantityPerLp <= 0.0) return false
    if (lpCount * quantityPerLp > remainingQuantity) return false
    return serialNo.isBlank() || (lpCount == 1 && quantityPerLp == 1.0)
}

internal fun ledgerBulkLpPayload(
    templateCode: String,
    binCode: String,
    lpCount: Int,
    quantityPerLp: Double,
    printerId: String,
    printLabels: Boolean,
): String = JSONObject().apply {
    put("templateCode", templateCode.trim())
    put("binCode", binCode.trim())
    put("lpCount", lpCount)
    put("quantityPerLp", quantityPerLp)
    put("printerId", printerId.trim())
    put("printLabels", printLabels)
}.toString()

private fun lpQuantityText(value: String): String {
    var decimalSeen = false
    return buildString {
        value.replace(',', '.').forEach { char ->
            when {
                char.isDigit() -> append(char)
                char == '.' && !decimalSeen -> {
                    append(char)
                    decimalSeen = true
                }
            }
        }
    }
}

private fun formatLpQuantity(value: Double): String =
    if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BulkLpBuildSheet(
    onDismiss: () -> Unit,
    onBuilt: (List<String>) -> Unit,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    var lookup by remember { mutableStateOf("") }
    var entries by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var selectedEntry by remember { mutableStateOf<JSONObject?>(null) }
    var template by remember { mutableStateOf("") }
    var templates by remember { mutableStateOf<List<String>>(emptyList()) }
    var templateExpanded by remember { mutableStateOf(false) }
    var bin by remember { mutableStateOf("") }
    var lpCountText by remember { mutableStateOf("10") }
    var quantityText by remember { mutableStateOf("100") }
    var printLabels by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var completed by remember { mutableStateOf(false) }
    var createdLpNos by remember { mutableStateOf<List<String>>(emptyList()) }

    LaunchedEffect(Unit) {
        val page = BcApi.getAllPages(context, "licensePlateTemplates?\$top=50&\$select=code,description")
        templates = if (page.complete) {
            page.rows.map { it.optString("code") }.filter(String::isNotBlank)
        } else {
            status = "HATA: LP şablonları alınamadı."
            emptyList()
        }
    }

    fun finish() {
        if (completed) onBuilt(createdLpNos) else onDismiss()
    }

    fun findLedgerEntries() {
        val value = lookup.trim()
        if (value.isBlank()) {
            status = "HATA: Madde numarası veya Madde Defter Giriş No girin."
            return
        }
        scope.launch {
            busy = true
            selectedEntry = null
            status = "Madde Defter Girişleri aranıyor..."
            val filter = value.toIntOrNull()?.let { "entryNo eq $it" }
                ?: "itemNo eq '${value.replace("'", "''")}'"
            val page = BcApi.getAllPages(
                context,
                "itemLedgerEntries?\$filter=$filter&\$orderby=entryNo desc&\$top=100&" +
                    "\$select=entryNo,itemNo,postingDate,documentNo,locationCode,quantity,remainingQuantity," +
                    "baseUnitOfMeasure,variantCode,lotNo,serialNo",
            )
            busy = false
            entries = if (page.complete) page.rows.filter { it.optDouble("remainingQuantity") > 0.0 }
            else emptyList()
            status = when {
                !page.complete -> "HATA: Madde Defter Girişlerinin tamamı alınamadı."
                entries.isEmpty() -> "BOŞ: Kullanılabilir miktarı olan giriş bulunamadı."
                else -> "${entries.size} uygun giriş bulundu; kaynağı seçin."
            }
        }
    }

    val entry = selectedEntry
    val lpCount = lpCountText.toIntOrNull()
    val quantityPerLp = quantityText.toDoubleOrNull()
    val remainingQuantity = entry?.optDouble("remainingQuantity") ?: 0.0
    val requestedQuantity = (lpCount ?: 0) * (quantityPerLp ?: 0.0)
    val planValid = validLedgerBulkLpPlan(
        lpCount,
        quantityPerLp,
        remainingQuantity,
        entry?.optString("serialNo").orEmpty(),
    )

    com.dynops.bcwms.ui.SheetScaffold(onDismiss = { if (!busy) finish() }) {
        Text("Mevcut Stoktan Toplu LP", fontSize = 21.sp, fontWeight = FontWeight.Bold)
        Text(
            "Madde Defter Girişi tek satır kalır; LP'ler ayrı kayıtlarda aynı girişe bağlanır.",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(10.dp))

        if (completed) {
            StatusText(status)
            Spacer(Modifier.height(12.dp))
            Button(onClick = { onBuilt(createdLpNos) }, modifier = Modifier.fillMaxWidth()) {
                Text("LP Listesine Dön")
            }
            Spacer(Modifier.height(24.dp))
            return@SheetScaffold
        }

        ScanField(
            "Madde No / Madde Defter Giriş No",
            lookup,
            { lookup = it.trimStart() },
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(8.dp))
        OutlinedButton(
            onClick = { findLedgerEntries() },
            enabled = !busy && lookup.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        ) { Text(if (busy) "Aranıyor..." else "Girişleri Getir") }

        if (entries.isNotEmpty()) {
            Spacer(Modifier.height(10.dp))
            Text("Kaynak Madde Defter Girişi", fontWeight = FontWeight.Bold, fontSize = 13.sp)
            entries.take(20).forEach { row ->
                val selected = selectedEntry?.optInt("entryNo") == row.optInt("entryNo")
                Card(
                    onClick = { selectedEntry = row; status = "" },
                    modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = if (selected) MaterialTheme.colorScheme.primaryContainer
                        else MaterialTheme.colorScheme.surface,
                    ),
                    border = androidx.compose.foundation.BorderStroke(
                        1.dp,
                        if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
                    ),
                ) {
                    Column(Modifier.padding(12.dp)) {
                        Text("#${row.optInt("entryNo")} · ${row.optString("itemNo")}", fontWeight = FontWeight.Bold)
                        Text(
                            "Kalan: ${formatLpQuantity(row.optDouble("remainingQuantity"))} " +
                                "${row.optString("baseUnitOfMeasure")} · ${row.optString("locationCode")}",
                            fontSize = 12.sp,
                        )
                        val detail = listOfNotNull(
                            row.optString("lotNo").takeIf(String::isNotBlank)?.let { "Lot $it" },
                            row.optString("serialNo").takeIf(String::isNotBlank)?.let { "Seri $it" },
                            row.optString("documentNo").takeIf(String::isNotBlank)?.let { "Belge $it" },
                        ).joinToString(" · ")
                        if (detail.isNotBlank())
                            Text(detail, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }

        if (entry != null) {
            Spacer(Modifier.height(12.dp))
            ExposedDropdownMenuBox(
                expanded = templateExpanded,
                onExpandedChange = { templateExpanded = !templateExpanded },
            ) {
                OutlinedTextField(
                    value = template,
                    onValueChange = { template = it },
                    readOnly = templates.isNotEmpty(),
                    label = { Text("LP Şablonu") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(templateExpanded) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                )
                ExposedDropdownMenu(expanded = templateExpanded, onDismissRequest = { templateExpanded = false }) {
                    templates.forEach { code ->
                        DropdownMenuItem(text = { Text(code) }, onClick = { template = code; templateExpanded = false })
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = entry.optString("locationCode"),
                onValueChange = {},
                readOnly = true,
                label = { Text("Lokasyon") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(8.dp))
            ScanField("Stok Rafı (Bin)", bin, { bin = it.uppercase() }, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = lpCountText,
                    onValueChange = { lpCountText = it.filter(Char::isDigit).take(3) },
                    label = { Text("LP adedi") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    value = quantityText,
                    onValueChange = { quantityText = lpQuantityText(it) },
                    label = { Text("LP başı miktar") },
                    suffix = { Text(entry.optString("baseUnitOfMeasure")) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
            }
            Text(
                "Toplam: ${formatLpQuantity(requestedQuantity)} / ${formatLpQuantity(remainingQuantity)} " +
                    entry.optString("baseUnitOfMeasure"),
                fontSize = 12.sp,
                color = if (requestedQuantity > remainingQuantity) MaterialTheme.colorScheme.error
                else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = printLabels, onCheckedChange = { printLabels = it })
                Text("Her LP için ayrı etiket yazdır")
            }
        }

        if (status.isNotBlank()) StatusText(status)
        Spacer(Modifier.height(8.dp))
        Button(
            enabled = !busy && entry != null && template.isNotBlank() && bin.isNotBlank() && planValid,
            modifier = Modifier.fillMaxWidth(),
            onClick = {
                val sourceEntry = entry ?: return@Button
                val count = lpCount ?: return@Button
                val perLp = quantityPerLp ?: return@Button
                scope.launch {
                    busy = true
                    status = "LP'ler oluşturuluyor${if (printLabels) " ve etiketleniyor" else ""}..."
                    val safeLocation = sourceEntry.optString("locationCode").replace("'", "''")
                    val safeBin = bin.trim().replace("'", "''")
                    val binPage = BcApi.getAllPages(
                        context,
                        "bins?\$filter=locationCode eq '$safeLocation' and code eq '$safeBin'&\$select=code&\$top=1",
                    )
                    if (!binPage.complete || binPage.rows.isEmpty()) {
                        busy = false
                        status = "HATA: Lokasyon ve stok rafı eşleşmiyor."
                        return@launch
                    }
                    val body = ledgerBulkLpPayload(
                        template,
                        bin,
                        count,
                        perLp,
                        getDefaultPrinter(context, PRINTER_USAGE_LABEL),
                        printLabels,
                    )
                    val result = BcApi.boundActionLongRunning(
                        context,
                        "itemLedgerEntries",
                        "entryNo=${sourceEntry.optInt("entryNo")}",
                        "createLicensePlates",
                        body,
                    )
                    busy = false
                    if (!result.ok) {
                        status = if (result.httpCode == 404 || result.httpCode == 405) {
                            "HATA: Mevcut stoktan toplu LP servisi BC'ye henüz yayımlanmamış. Güncel AL paketini yayınlayın."
                        } else {
                            "HATA: ${BcApi.errorMessage(result.body)} (HTTP ${result.httpCode})"
                        }
                        return@launch
                    }

                    val response = runCatching { JSONObject(BcApi.scalarValue(result.body)) }.getOrNull()
                    if (response == null) {
                        status = "UYARI: İşlem tamamlandı ancak LP numaraları okunamadı. LP listesini yenileyip kontrol edin."
                        completed = true
                        return@launch
                    }
                    val array = response.optJSONArray("createdLpNos") ?: JSONArray()
                    createdLpNos = List(array.length()) { index -> array.optString(index) }.filter(String::isNotBlank)
                    val created = response.optInt("createdCount")
                    val printed = response.optInt("printedCount")
                    val failed = response.optInt("printFailureCount")
                    status = when {
                        printLabels && failed > 0 ->
                            "UYARI: $created LP oluşturuldu; $printed etiket kuyruğa alındı, $failed etiket gönderilemedi. " +
                                "LP listesinden yeniden yazdırabilirsiniz."
                        printLabels -> "TAMAM: $created LP oluşturuldu ve her LP için ayrı etiket kuyruğa alındı."
                        else -> "TAMAM: $created LP oluşturuldu."
                    }
                    completed = true
                }
            },
        ) { Text(if (busy) "İşleniyor..." else "LP'leri Oluştur") }
        Spacer(Modifier.height(24.dp))
    }
}
