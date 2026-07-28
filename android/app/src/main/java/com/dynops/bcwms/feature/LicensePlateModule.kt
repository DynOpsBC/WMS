package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * License Plate management — WI §10.10 parity.
 * Lookup list -> document (header + lines) -> actions:
 *   Build new · Add line (scan + qty) · Stop (-> SSCC + print) · Transfer · Unbuild · Print · Partial-use.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LicensePlateModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var selected by remember { mutableStateOf<String?>(null) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var showBuild by remember { mutableStateOf(false) }
    var search by remember { mutableStateOf("") }

    fun loadList() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val filter = com.dynops.bcwms.ui.buildODataFilter(com.dynops.bcwms.ui.searchClause("no", search))
            val r = BcApi.getWithStandardFallback(context, "licensePlates?\$top=200&\$orderby=no desc&\$select=no,status,locationCode,binCode,templateCode,sscc$filter")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: LP listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "BOŞ: LP kaydı yok (HTTP ${r.httpCode})"
                else "TAMAM: ${rows.size} LP (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(Unit) { loadList() }

    val sel = selected
    if (sel != null) {
        LpDocument(lpNo = sel, onBack = { selected = null; loadList() })
        return
    }

    if (showBuild) {
        LpBuildSheet(
            onDismiss = { showBuild = false },
            onBuilt = { newNo -> showBuild = false; loadList(); selected = newNo }
        )
    }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { loadList() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
            Spacer(Modifier.width(8.dp))
            Button(onClick = { showBuild = true }, enabled = !loading) { Text("➕ LP Oluştur") }
        }
        Spacer(Modifier.height(8.dp))
        com.dynops.bcwms.ui.DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { loadList() }, label = "LP no ile ara")
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { lp ->
                Card(onClick = { selected = lp.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(lp.optString("no"), fontWeight = FontWeight.Bold)
                            StatusBadge(lp.optString("status"))
                        }
                        Text("${lp.optString("templateCode")} · ${lp.optString("locationCode")}/${lp.optString("binCode")}", fontSize = 12.sp, color = Color.Gray)
                        if (lp.optString("sscc").isNotBlank())
                            Text("SSCC: ${lp.optString("sscc")}", fontSize = 11.sp, color = Color.Gray)
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("LP kaydı bulunamadı.") }
        }
    }
}

// BC LP durum değeri (wire) → operatöre gösterilen Türkçe etiket. Karşılaştırma/
// renk seçimi ham değerle yapılır; ekranda hep bu etiket görünür.
internal fun lpStatusLabel(status: String): String = when (status) {
    "Built" -> "Oluşturuldu"
    "Assigned" -> "Atandı"
    "Used" -> "Kullanıldı"
    "Unbuilt" -> "Bozuldu"
    "" -> "Açık"
    else -> status
}

@Composable
private fun StatusBadge(status: String) {
    val (bg, fg) = when (status) {
        "Built" -> Color(0xFFE3F2FD) to Color(0xFF1565C0)
        "Assigned" -> Color(0xFFFFF3E0) to Color(0xFFEF6C00)
        "Used" -> Color(0xFFE8F5E9) to Color(0xFF2E7D32)
        "Unbuilt" -> Color(0xFFFFEBEE) to Color(0xFFC62828)
        else -> Color(0xFFF5F5F5) to Color(0xFF616161)
    }
    Surface(color = bg, shape = RoundedCornerShape(6.dp)) {
        Text(lpStatusLabel(status), Modifier.padding(horizontal = 8.dp, vertical = 2.dp), color = fg, fontSize = 11.sp, fontWeight = FontWeight.Medium)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LpBuildSheet(onDismiss: () -> Unit, onBuilt: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var template by remember { mutableStateOf("CARTON-S") }
    var location by remember { mutableStateOf("SILVER") }
    var bin by remember { mutableStateOf("S-1-01") }
    var busy by remember { mutableStateOf(false) }
    var err by remember { mutableStateOf("") }
    // PDF LP §5: Template alanı serbest text idi — operatör "CARTON-S"
    // yerine "CARTONS" yazıp sessizce yanlış kayıt yaratıyordu. Dropdown
    // ile mevcut template'lerden seçtirilir.
    var templates by remember { mutableStateOf<List<String>>(emptyList()) }
    LaunchedEffect(Unit) {
        val r = BcApi.get(context, "licensePlateTemplates?\$top=50&\$select=code,description")
        if (r.ok) templates = BcApi.parseValueArray(r.body).map { it.optString("code") }.filter { it.isNotBlank() }
    }
    var templateExpanded by remember { mutableStateOf(false) }

    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text("Yeni LP Oluştur", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Spacer(Modifier.height(12.dp))
        ExposedDropdownMenuBox(expanded = templateExpanded, onExpandedChange = { templateExpanded = !templateExpanded }) {
            OutlinedTextField(
                value = template,
                onValueChange = { template = it },
                readOnly = templates.isNotEmpty(),
                label = { Text("Şablon Kodu") },
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = templateExpanded) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().menuAnchor(),
            )
            if (templates.isNotEmpty()) {
                ExposedDropdownMenu(expanded = templateExpanded, onDismissRequest = { templateExpanded = false }) {
                    templates.forEach { code ->
                        DropdownMenuItem(text = { Text(code) }, onClick = { template = code; templateExpanded = false })
                    }
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        ScanField("Lokasyon", location, { location = it }, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        ScanField("Bin", bin, { bin = it }, modifier = Modifier.fillMaxWidth())
        if (err.isNotBlank()) { Spacer(Modifier.height(8.dp)); StatusText(err) }
        Spacer(Modifier.height(16.dp))
        Button(
            enabled = !busy && template.isNotBlank(),
            modifier = Modifier.fillMaxWidth().height(50.dp),
            onClick = {
                scope.launch {
                    busy = true; err = ""
                    val body = JSONObject().apply {
                        put("templateCode", template.trim())
                        put("locationCode", location.trim())
                        put("binCode", bin.trim())
                    }.toString()
                    val r = BcApi.post(context, "licensePlates", body)
                    busy = false
                    if (r.ok) {
                        val no = JSONObject(r.body).optString("no")
                        onBuilt(no)
                    } else err = "HATA: ${BcApi.errorMessage(r.body)}"
                }
            }
        ) { Text(if (busy) "Oluşturuluyor..." else "Oluştur") }
        Spacer(Modifier.height(24.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LpDocument(lpNo: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }

    // dialogs — ELOG akışı: LP okut (belge açık) → ürün okut → adet → KAYNAK BİN okut → kaydet.
    var showAddLine by remember { mutableStateOf(false) }
    var showQty by remember { mutableStateOf(false) }
    var scannedItem by remember { mutableStateOf("") }
    var pendingQty by remember { mutableStateOf<com.dynops.bcwms.ui.QuantityResult?>(null) }
    var showSourceBin by remember { mutableStateOf(false) }
    var showTransfer by remember { mutableStateOf(false) }
    var showPartial by remember { mutableStateOf(false) }

    fun reload() {
        scope.launch {
            busy = true
            val h = BcApi.get(context, "licensePlates('$lpNo')")
            if (h.ok) header = JSONObject(h.body)
            val l = BcApi.get(context, "licensePlateLines?\$filter=lpNo eq '$lpNo'&\$top=100")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            busy = false
        }
    }
    LaunchedEffect(lpNo) { reload() }

    fun action(name: String, body: String = "{}", okMsg: String) {
        scope.launch {
            busy = true; status = "$name çalışıyor..."
            val r = BcApi.boundAction(context, "licensePlates", lpNo, name, body)
            busy = false
            status = if (r.ok) "TAMAM: $okMsg (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            if (r.ok) reload()
        }
    }

    val h = header
    val st = h?.optString("status") ?: ""

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ LP Listesi") }
            val isTote = h?.optBoolean("reusable") == true
            DocHeaderCard(
                title = lpNo,
                subtitle = "${h?.optString("templateCode") ?: ""}${if (isTote) " · ♻ Tote" else ""} · ${h?.optString("locationCode") ?: ""}/${h?.optString("binCode") ?: ""}" +
                    (h?.optString("sscc")?.takeIf { it.isNotBlank() }?.let { "\nSSCC: $it" } ?: ""),
                badge = lpStatusLabel(st)
            )
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            // Tote (yeniden kullanılabilir LP): iş bitince Release → tekrar Built.
            if (st.equals("Assigned", ignoreCase = true)) {
                Spacer(Modifier.height(6.dp))
                Button(
                    onClick = { action("release", "{}", "LP serbest bırakıldı — yeniden kullanılabilir") },
                    enabled = !busy, modifier = Modifier.fillMaxWidth().height(48.dp),
                ) { Text(if (isTote) "♻ Tote'u Serbest Bırak" else "Serbest Bırak (Release)", fontWeight = FontWeight.SemiBold) }
            }
            Spacer(Modifier.height(6.dp))
            Text("Satırlar (${lines.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(lines) { ln ->
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(10.dp)) {
                            Text("${ln.optString("itemNo")} × ${ln.optDouble("quantity")}", fontWeight = FontWeight.Medium)
                            val extra = listOfNotNull(
                                ln.optString("sourceBinCode").takeIf { it.isNotBlank() && it != "null" }?.let { "📍 $it" },
                                ln.optString("lotNo").takeIf { it.isNotBlank() }?.let { "Lot $it" },
                                ln.optString("serialNo").takeIf { it.isNotBlank() }?.let { "Seri $it" },
                                ln.optString("unitOfMeasure").takeIf { it.isNotBlank() }
                            ).joinToString(" · ")
                            if (extra.isNotBlank()) Text(extra, fontSize = 11.sp, color = Color.Gray)
                        }
                    }
                }
                if (lines.isEmpty() && !busy) item { EmptyState("Henüz satır yok. ➕ ile item ekleyin.") }
            }
        }

        BottomActionBar {
            Button(onClick = { showAddLine = true }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("➕ Satır") }
            Button(onClick = { action("stop", """{"printLabel":true}""", "LP Stop + SSCC") }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("⏹ Stop") }
            OutlinedButton(onClick = { showTransfer = true }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Transfer") }
        }
        BottomActionBar {
            OutlinedButton(
                onClick = {
                    // Use the default printer registered in the Printers screen
                    // (per-device SharedPreferences). Empty printerId would
                    // make BC PrintDispatcher default to BCNative PDF.
                    val defaultPrinter = getDefaultPrinter(context)
                    val payload = JSONObject().apply {
                        put("printerId", defaultPrinter)
                        put("copies", 1)
                    }.toString()
                    action("printLabel", payload, if (defaultPrinter.isBlank()) "Etiket BCNative'e gönderildi (default printer ayarlanmadı)" else "Etiket $defaultPrinter yazıcısına gönderildi")
                },
                enabled = !busy,
                modifier = Modifier.weight(1f),
            ) { Text("🖨 Yazdır") }
            OutlinedButton(onClick = { showPartial = true }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Kısmi") }
            OutlinedButton(onClick = { action("unbuild", "{}", "LP bozuldu") }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Boz") }
        }
    }

    // Add line: scan item -> qty dialog
    if (showAddLine) {
        AddLineScanSheet(
            onDismiss = { showAddLine = false },
            onItem = { item -> scannedItem = item; showAddLine = false; showQty = true }
        )
    }
    if (showQty) {
        QuantityDialogSheet(
            title = "Satır Ekle",
            itemNo = scannedItem,
            onDismiss = { showQty = false },
            onConfirm = { res ->
                // Adet girildi — kayıttan önce ürünün alındığı KAYNAK BİN okutulur.
                showQty = false
                pendingQty = res
                showSourceBin = true
            }
        )
    }
    if (showSourceBin) {
        ToteScanSheet(
            title = "Kaynak Bin Okutun",
            hint = "Ürünün alındığı raf gözünün (bin) barkodunu okutun",
            onDismiss = { showSourceBin = false; pendingQty = null },
            onScanned = { scannedBin ->
                showSourceBin = false
                val res = pendingQty ?: return@ToteScanSheet
                pendingQty = null
                scope.launch {
                    busy = true; status = "Satır ekleniyor..."
                    val body = JSONObject().apply {
                        put("lpNo", lpNo); put("itemNo", scannedItem); put("quantity", res.quantity)
                        put("sourceBinCode", scannedBin.trim())
                        if (res.uom.isNotBlank()) put("unitOfMeasure", res.uom)
                        if (res.lotNo.isNotBlank()) put("lotNo", res.lotNo)
                        if (res.serialNo.isNotBlank()) put("serialNo", res.serialNo)
                    }.toString()
                    var r = BcApi.post(context, "licensePlateLines", body)
                    if (r.httpCode == 400) {
                        // Eski publish'te sourceBinCode alanı yok — alansız gönder.
                        val legacy = JSONObject(body).apply { remove("sourceBinCode") }.toString()
                        r = BcApi.post(context, "licensePlateLines", legacy)
                    }
                    busy = false
                    status = if (r.ok) "TAMAM: ${scannedItem} × ${res.quantity} eklendi (bin: ${scannedBin.trim()})"
                        else "HATA: ${BcApi.errorMessage(r.body)}"
                    if (r.ok) reload()
                }
            }
        )
    }
    if (showTransfer) {
        TransferSheet(onDismiss = { showTransfer = false }, onConfirm = { target ->
            showTransfer = false
            // Tüm satırları açıkça gönder — eski publish'te boş linesJson hiçbir
            // satır taşımadan başarı dönüyordu (LPApi.ParseLines boş çıkışı).
            val linesJson = org.json.JSONArray().apply {
                lines.forEach { ln -> put(JSONObject().apply { put("lineNo", ln.optInt("lineNo")) }) }
            }.toString()
            action("transfer", JSONObject().apply { put("targetLpNo", target); put("linesJson", linesJson) }.toString(), "Transfer tamamlandı (${lines.size} satır)")
        })
    }
    if (showPartial) {
        PartialUseSheet(onDismiss = { showPartial = false }, onConfirm = { mode, qty, lineNo ->
            showPartial = false
            action("usePartial", JSONObject().apply { put("action", mode); put("qty", qty); put("lineNo", lineNo) }.toString(), "Kısmi kullanım ($mode) tamamlandı")
        })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddLineScanSheet(onDismiss: () -> Unit, onItem: (String) -> Unit) {
    var item by remember { mutableStateOf("") }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text("Ürün Tara / Gir", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Spacer(Modifier.height(12.dp))
        ScanField("Ürün No.", item, { item = it }, modifier = Modifier.fillMaxWidth(), onScanned = { raw ->
            item = BarcodeIntentResolver.resolve(raw).itemNo ?: raw
        })
        Spacer(Modifier.height(16.dp))
        Button(enabled = item.isNotBlank(), modifier = Modifier.fillMaxWidth(), onClick = { onItem(item.trim()) }) { Text("Devam → Miktar") }
        Spacer(Modifier.height(24.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TransferSheet(onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    var target by remember { mutableStateOf("") }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text("LP Transferi", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text("İçeriği hedef LP'ye taşı (boş = yeni LP).", fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(12.dp))
        ScanField("Hedef LP No", target, { target = it }, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Button(modifier = Modifier.fillMaxWidth(), onClick = { onConfirm(target.trim()) }) { Text("Transfer Et") }
        Spacer(Modifier.height(24.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PartialUseSheet(onDismiss: () -> Unit, onConfirm: (mode: String, qty: Double, lineNo: Int) -> Unit) {
    val modes = listOf("consume", "ship", "move", "produce")
    var mode by remember { mutableStateOf(modes.first()) }
    var qty by remember { mutableStateOf("1") }
    var lineNo by remember { mutableStateOf("10000") }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text("Kısmi Kullanım", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Spacer(Modifier.height(8.dp))
        Text("Mod", fontSize = 12.sp, color = Color.Gray)
        FlowRowChips(options = modes, selected = mode, onSelect = { mode = it })
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(qty, { qty = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Miktar") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(lineNo, { lineNo = it.filter { c -> c.isDigit() } }, label = { Text("Satır No") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Button(modifier = Modifier.fillMaxWidth(), onClick = {
            onConfirm(mode, qty.toDoubleOrNull() ?: 0.0, lineNo.toIntOrNull() ?: 0)
        }) { Text("Uygula") }
        Spacer(Modifier.height(24.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FlowRowChips(options: List<String>, selected: String, onSelect: (String) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        options.forEach { opt ->
            FilterChip(selected = opt == selected, onClick = { onSelect(opt) }, label = { Text(opt) })
        }
    }
}
