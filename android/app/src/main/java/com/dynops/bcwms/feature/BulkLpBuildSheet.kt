package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
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
    }
        .distinctBy { it.code.uppercase() }
        .sortedBy { it.code.uppercase() }

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

private fun lpQuantityText(value: String): String {
    var decimalSeen = false
    return buildString {
        value.replace(',', '.').forEach { char ->
            when {
                char.isDigit() -> append(char)
                char == '.' && !decimalSeen -> { append(char); decimalSeen = true }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BulkLpBuildSheet(
    onDismiss: () -> Unit,
    onBuilt: (List<String>) -> Unit,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    var template by remember { mutableStateOf("") }
    var location by remember { mutableStateOf("") }
    var bin by remember { mutableStateOf("") }
    var lpCountText by remember { mutableStateOf("10") }
    var commonQty by remember { mutableStateOf("") }
    var drafts by remember { mutableStateOf(commonLpQuantityDrafts(10, "")) }
    var templates by remember { mutableStateOf<List<String>>(emptyList()) }
    var templateExpanded by remember { mutableStateOf(false) }
    var locations by remember { mutableStateOf<List<BulkLpLocationOption>>(emptyList()) }
    var locationsComplete by remember { mutableStateOf(false) }
    var locationsLoading by remember { mutableStateOf(true) }
    var locationExpanded by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        val page = BcApi.getAllPages(context, "licensePlateTemplates?\$top=50&\$select=code,description")
        if (page.complete) templates = page.rows.map { it.optString("code") }.filter(String::isNotBlank)
        else status = "HATA: LP şablonları alınamadı."

        val locationPage = BcApi.getAllPagesWithStandardFallback(
            context,
            "locations?\$orderby=code&\$select=code,displayName&\$top=200",
        )
        locations = if (locationPage.complete) bulkLpLocationOptions(locationPage.rows) else emptyList()
        locationsComplete = locationPage.complete
        locationsLoading = false
        when {
            !locationsComplete ->
                status = "HATA: Lokasyonlar alınamadı. Bağlantıyı kontrol edip ekranı yeniden açın."
            locations.isEmpty() ->
                status = "HATA: Bu şirkette tanımlı lokasyon bulunamadı."
        }
    }

    val lpCount = lpCountText.toIntOrNull() ?: 0
    val validDrafts = drafts.size == lpCount && drafts.isNotEmpty() && drafts.all {
        val qty = it.quantity.toDoubleOrNull() ?: 0.0
        qty.isFinite() && qty >= 0.0
    }
    val validLocation = validBulkLpLocationSelection(location, locationsComplete, locations)

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().fillMaxHeight(0.95f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            Text("Toplu LP Oluştur", fontSize = 21.sp, fontWeight = FontWeight.Bold)
            Text("Ortak miktarı tüm LP'lere dağıtın; sonra her satırı ayrı ayrı değiştirebilirsiniz.", fontSize = 12.sp)
            Spacer(Modifier.height(10.dp))

            ExposedDropdownMenuBox(expanded = templateExpanded, onExpandedChange = { templateExpanded = !templateExpanded }) {
                OutlinedTextField(
                    value = template,
                    onValueChange = { template = it },
                    readOnly = templates.isNotEmpty(),
                    label = { Text("Şablon Kodu") },
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
            ExposedDropdownMenuBox(
                expanded = locationExpanded,
                onExpandedChange = {
                    if (!busy && locationsComplete && locations.isNotEmpty()) locationExpanded = !locationExpanded
                },
            ) {
                val selectedLocation = locations.firstOrNull { it.code.equals(location, ignoreCase = true) }
                OutlinedTextField(
                    value = selectedLocation?.label.orEmpty(),
                    onValueChange = {},
                    readOnly = true,
                    enabled = !busy && locationsComplete && locations.isNotEmpty(),
                    label = { Text(if (locationsLoading) "Lokasyonlar yükleniyor" else "Lokasyon Seçin") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(locationExpanded) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                )
                ExposedDropdownMenu(expanded = locationExpanded, onDismissRequest = { locationExpanded = false }) {
                    locations.forEach { option ->
                        DropdownMenuItem(
                            text = { Text(option.label) },
                            onClick = {
                                if (!option.code.equals(location, ignoreCase = true)) bin = ""
                                location = option.code
                                locationExpanded = false
                            },
                        )
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            ScanField("Depo Gözü (Bin) — İsteğe bağlı", bin, { bin = it.uppercase() }, modifier = Modifier.fillMaxWidth())
            Text(
                "Boş bırakırsanız depo gözünü daha sonra LP detayından atayabilirsiniz.",
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
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
                    value = commonQty,
                    onValueChange = { commonQty = lpQuantityText(it) },
                    label = { Text("Ortak miktar") },
                    supportingText = { Text("Boş = 0") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
            }
            Button(
                onClick = { drafts = commonLpQuantityDrafts(lpCount, commonQty.ifBlank { "0" }) },
                enabled = lpCount in 1..200,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Miktarı $lpCount LP'ye Uygula") }
            Spacer(Modifier.height(10.dp))

            drafts.forEachIndexed { index, draft ->
                OutlinedTextField(
                    value = draft.quantity,
                    onValueChange = { value ->
                        drafts = drafts.map { if (it.id == draft.id) it.copy(quantity = lpQuantityText(value)) else it }
                    },
                    label = { Text("LP ${index + 1} planlanan miktar") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 6.dp),
                )
            }

            if (status.isNotBlank()) StatusText(status)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(bottom = 18.dp)) {
                OutlinedButton(onClick = onDismiss, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Vazgeç") }
                Button(
                    enabled = !busy && template.isNotBlank() && validLocation && validDrafts,
                    modifier = Modifier.weight(1f),
                    onClick = {
                        scope.launch {
                            busy = true
                            status = "$lpCount LP oluşturuluyor..."
                            val safeLocation = location.trim().replace("'", "''")
                            if (bin.isNotBlank()) {
                                val safeBin = bin.trim().replace("'", "''")
                                val binPage = BcApi.getAllPages(
                                    context,
                                    "bins?\$filter=locationCode eq '$safeLocation' and code eq '$safeBin'&\$select=code&\$top=1",
                                )
                                if (!binPage.complete || binPage.rows.isEmpty()) {
                                    busy = false
                                    status = "HATA: Lokasyon ve depo gözü eşleşmiyor."
                                    return@launch
                                }
                            }
                            val body = bulkLpBuildPayload(location, bin, drafts)
                            val result = BcApi.boundAction(context, "licensePlateTemplates", template.trim(), "buildBulk", body)
                            busy = false
                            if (result.ok) {
                                val raw = BcApi.scalarValue(result.body).trim()
                                val created = runCatching {
                                    val array = JSONArray(raw)
                                    List(array.length()) { i -> array.getJSONObject(i).optString("no") }.filter(String::isNotBlank)
                                }.getOrDefault(emptyList())
                                if (created.size == drafts.size) onBuilt(created)
                                else status = "HATA: LP'ler oluşturuldu ancak numara listesi eksik döndü; listeyi yenileyin."
                            } else {
                                status = if (result.httpCode == 404 || result.httpCode == 405)
                                    "HATA: Toplu LP servisi BC'ye henüz yayımlanmamış. Güncel AL paketini yayınlayın."
                                else "HATA: ${BcApi.errorMessage(result.body)} (HTTP ${result.httpCode})"
                            }
                        }
                    },
                ) { Text(if (busy) "Oluşturuluyor" else "$lpCount LP Oluştur") }
            }
        }
    }
}
