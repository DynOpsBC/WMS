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
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Picking — WI §10.3 parity.
 * Lookup (assigned-to-me + show all) -> Pick Document -> Take/Place -> Start/Stop shipping LP ->
 * Short pick (reason) -> Register.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PickingModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selected by remember { mutableStateOf<String?>(null) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var showAll by remember { mutableStateOf(true) }
    var search by remember { mutableStateOf("") }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val assigned = if (showAll) "" else "&\$filter=assignedUserId ne ''"
            val noFilter = if (search.isBlank()) "" else
                (if (assigned.contains("\$filter")) " and " else "&\$filter=") + "startswith(no,'${search.trim().replace("'", "''")}')"
            // Merge assigned + search into a single filter clause if both used.
            val combined = when {
                assigned.isBlank() && noFilter.isBlank() -> ""
                assigned.isBlank() -> noFilter
                noFilter.isBlank() -> assigned
                else -> assigned + noFilter.removePrefix("&\$filter=")
            }
            val r = BcApi.getWithStandardFallback(context, "picks?\$top=100&\$orderby=no desc&\$select=no,locationCode,assignedUserId,sourceNo,status,percentComplete$combined")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Toplama listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "EMPTY: Açık toplama belgesi yok (HTTP ${r.httpCode})"
                else "PASS: ${rows.size} belge (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(showAll) { load() }

    val sel = selected
    if (sel != null) { PickDocument(no = sel, onBack = { selected = null; load() }); return }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
            Spacer(Modifier.width(12.dp))
            FilterChip(selected = !showAll, onClick = { showAll = false }, label = { Text("Bana atanan") })
            Spacer(Modifier.width(6.dp))
            FilterChip(selected = showAll, onClick = { showAll = true }, label = { Text("Tümü") })
        }
        Spacer(Modifier.height(8.dp))
        // PDF Picking §7 / §16: belge no arama eksikti
        OutlinedTextField(
            value = search,
            onValueChange = { search = it },
            singleLine = true,
            label = { Text("Belge no ile ara") },
            trailingIcon = { TextButton(onClick = { load() }) { Text("🔎") } },
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { d ->
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(d.optString("no"), fontWeight = FontWeight.Bold)
                            Text(d.optString("status"), fontSize = 12.sp, color = Color.Gray)
                        }
                        Text("Lokasyon: ${firstValue(d, "locationCode")} · Atanan: ${firstValue(d, "assignedUserId")}", fontSize = 12.sp, color = Color.Gray)
                        val pct = d.optInt("percentComplete")
                        LinearProgressIndicator(progress = { pct / 100f }, modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Açık toplama belgesi yok.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PickDocument(no: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var shipLp by remember { mutableStateOf<String?>(null) }
    var showShort by remember { mutableStateOf(false) }
    var shortLine by remember { mutableStateOf<JSONObject?>(null) }
    // PDF Picking §7: scan-and-verify state. Operatör "Tara & Tamamla"ya
    // bastığında scanLine doluyor; ScanVerifySheet açılıyor; barkod
    // okununca itemNo karşılaştırılıp ya tamamlanıyor ya hata gösteriliyor.
    var scanLine by remember { mutableStateOf<JSONObject?>(null) }

    fun reload() {
        scope.launch {
            busy = true
            val h = BcApi.get(context, "picks('$no')")
            if (h.ok) header = JSONObject(h.body)
            val l = BcApi.get(context, "pickLines?\$filter=no eq '$no'&\$top=100")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    fun action(name: String, body: String, okMsg: String, onResult: (BcApi.ApiResult) -> Unit = {}) {
        scope.launch {
            busy = true; status = "$name..."
            val r = BcApi.boundAction(context, "picks", no, name, body)
            busy = false
            status = if (r.ok) "PASS: $okMsg (HTTP ${r.httpCode})"
                else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
            onResult(r)
            if (r.ok) reload()
        }
    }

    fun updateLine(line: JSONObject, qtyHandled: Double) {
        scope.launch {
            busy = true; status = "Satır güncelleniyor..."
            val body = JSONObject().apply { put("qtyToHandle", qtyHandled) }.toString()
            // Composite key needs a non-blank activityType. Fall back to PICK if BC didn't echo it
            // (some downlevel API page responses omit it from the line projection).
            val actType = line.optString("activityType").ifBlank { BcEnum.WhseActivityType.PICK }
            val r = BcApi.patch(context, "pickLines(activityType='$actType',no='$no',lineNo=${line.optInt("lineNo")})", body)
            busy = false
            status = if (r.ok) "PASS: Satır güncellendi (HTTP ${r.httpCode})"
                else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
            if (r.ok) reload()
        }
    }

    val h = header
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Belge Listesi") }
            DocHeaderCard(
                title = no,
                subtitle = "Lokasyon: ${h?.optString("locationCode") ?: ""} · ${h?.optString("status") ?: ""}" +
                    (shipLp?.let { "\nShipping LP: $it" } ?: ""),
                percent = h?.optDouble("percentComplete")?.toInt() ?: 0
            )
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            if (status.startsWith("🔬")) {
                val navigator = com.dynops.bcwms.LocalNavigator.current
                Spacer(Modifier.height(4.dp))
                OutlinedButton(onClick = { navigator(com.dynops.bcwms.Screen.QualityMgmt) }) {
                    Text("🧫 MS Quality Mgmt'i Aç", fontWeight = FontWeight.Medium)
                }
            }
            Spacer(Modifier.height(4.dp))
            Text("Satırlar (${lines.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(lines) { ln ->
                    val act = ln.optString("actionType")
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(10.dp)) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text("${ln.optString("itemNo")} — ${ln.optString("description")}", fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                                ActionBadge(act)
                            }
                            Text("Bin: ${ln.optString("binCode")} · İşlenecek: ${ln.optDouble("qtyToHandle")} / ${ln.optDouble("quantity")}", fontSize = 12.sp, color = Color.Gray)
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
                                TextButton(onClick = { scanLine = ln }) { Text("📷 Tara & Tamamla") }
                                TextButton(onClick = { updateLine(ln, ln.optDouble("quantity")) }) { Text("Tamamla") }
                                TextButton(onClick = { shortLine = ln; showShort = true }) { Text("Short") }
                            }
                        }
                    }
                }
                if (lines.isEmpty() && !busy) item { EmptyState("Bu belgede satır yok.") }
            }
        }

        BottomActionBar {
            if (shipLp == null) {
                OutlinedButton(onClick = {
                    action("startShippingLP", """{"lpTemplateCode":"PALLET"}""", "Shipping LP başladı") { r ->
                        if (r.ok) shipLp = BcApi.scalarValue(r.body)
                    }
                }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Start Ship LP") }
            } else {
                OutlinedButton(onClick = {
                    val lp = shipLp!!
                    action("stopShippingLP", JSONObject().apply { put("lpNo", lp); put("printLabel", true) }.toString(), "Shipping LP kapandı") { r ->
                        if (r.ok) shipLp = null
                    }
                }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Stop Ship LP") }
            }
            OutlinedButton(onClick = { action("assignToMe", "{}", "Bana atandı") }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Bana Ata") }
        }
        BottomActionBar {
            val canRegister = com.dynops.bcwms.lib.ActionGuards.hasQuantity(lines)
            Button(
                onClick = { action("register", "{}", "Toplama kaydedildi") },
                enabled = !busy && canRegister,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    if (canRegister) "✅ Register Pick" else "Önce satırlara miktar girin",
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }

    if (showShort) {
        ShortPickSheet(line = shortLine, onDismiss = { showShort = false }, onConfirm = { qty, reason ->
            showShort = false
            val ln = shortLine ?: return@ShortPickSheet
            action("markShort", JSONObject().apply {
                put("lineNo", ln.optInt("lineNo")); put("qty", qty); put("reasonCode", reason)
            }.toString(), "Short pick işlendi")
        })
    }

    val scanTarget = scanLine
    if (scanTarget != null) {
        ScanVerifySheet(
            expectedItemNo = scanTarget.optString("itemNo"),
            description = scanTarget.optString("description"),
            onDismiss = { scanLine = null },
            onVerified = {
                scanLine = null
                updateLine(scanTarget, scanTarget.optDouble("quantity"))
            },
            onMismatch = {
                status = "❌ Tarama eşleşmedi: beklenen ${scanTarget.optString("itemNo")}, okunan $it"
            },
        )
    }
}

/**
 * Scan a barcode and confirm it matches the expected item on a pick line.
 * Prevents "wrong item picked" errors that the PDF flagged (§7). Operatör
 * yanlış raftan okutursa updateLine çağrılmaz ve ekrana belirgin hata yazılır.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScanVerifySheet(
    expectedItemNo: String,
    description: String,
    onDismiss: () -> Unit,
    onVerified: () -> Unit,
    onMismatch: (String) -> Unit,
) {
    var raw by remember { mutableStateOf("") }
    var hint by remember { mutableStateOf("Item barkodunu okutun. Beklenen: $expectedItemNo") }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text("Tara & Doğrula", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text("Beklenen: $expectedItemNo · $description", fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(12.dp))
        com.dynops.bcwms.scanner.ScanField(
            "Item / barkod", raw, { raw = it },
            modifier = Modifier.fillMaxWidth(),
            onScanned = { scanned ->
                val resolved = com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve(scanned)
                val readItem = resolved.itemNo ?: scanned
                raw = readItem
                if (readItem.equals(expectedItemNo, ignoreCase = true)) {
                    hint = "✅ Eşleşti — onaylanıyor..."
                    onVerified()
                } else {
                    hint = "❌ Eşleşmedi: $readItem"
                    onMismatch(readItem)
                }
            },
        )
        Spacer(Modifier.height(8.dp))
        Text(hint, fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("Vazgeç") }
            Button(
                enabled = raw.isNotBlank(),
                onClick = {
                    if (raw.trim().equals(expectedItemNo, ignoreCase = true)) onVerified()
                    else { hint = "❌ Eşleşmedi: $raw"; onMismatch(raw.trim()) }
                },
                modifier = Modifier.weight(1f),
            ) { Text("Manuel Onayla") }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun ActionBadge(action: String) {
    val (bg, fg) = when (action) {
        "Take" -> Color(0xFFE3F2FD) to Color(0xFF1565C0)
        "Place" -> Color(0xFFE8F5E9) to Color(0xFF2E7D32)
        else -> Color(0xFFF5F5F5) to Color(0xFF616161)
    }
    Surface(color = bg, shape = RoundedCornerShape(6.dp)) {
        Text(action.ifBlank { "-" }, Modifier.padding(horizontal = 8.dp, vertical = 2.dp), color = fg, fontSize = 11.sp, fontWeight = FontWeight.Medium)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ShortPickSheet(line: JSONObject?, onDismiss: () -> Unit, onConfirm: (qty: Double, reason: String) -> Unit) {
    var qty by remember { mutableStateOf((line?.optDouble("qtyToHandle") ?: 0.0).let { if (it == it.toLong().toDouble()) it.toLong().toString() else it.toString() }) }
    val reasons = listOf("DAMAGED", "NOTFOUND", "SHORTAGE", "EXPIRED")
    var reason by remember { mutableStateOf(reasons.first()) }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text("Short Pick", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text("Item: ${line?.optString("itemNo") ?: "-"}", fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(qty, { qty = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Eksik Miktar") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(10.dp))
        Text("Sebep", fontSize = 12.sp, color = Color.Gray)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            reasons.forEach { FilterChip(selected = it == reason, onClick = { reason = it }, label = { Text(it) }) }
        }
        Spacer(Modifier.height(16.dp))
        Button(modifier = Modifier.fillMaxWidth(), onClick = { onConfirm(qty.toDoubleOrNull() ?: 0.0, reason) }) { Text("Short İşle") }
        Spacer(Modifier.height(24.dp))
    }
}
