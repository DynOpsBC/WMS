package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
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
 * Ad-Hoc Move — WI §10.5.
 * Single screen: scan from-bin -> scan item/LP -> scan to-bin -> qty -> Confirm.
 * Posts to movements/Microsoft.NAV.adhoc (warehouse/v2.0, live since v1.0.8.0).
 */
@Composable
fun AdHocMoveModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var fromBin by remember { mutableStateOf("") }
    var itemOrLp by remember { mutableStateOf("") }
    var toBin by remember { mutableStateOf("") }
    var qty by remember { mutableStateOf("1") }
    var lotNo by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().padding(16.dp).verticalScroll(rememberScrollState())) {
        Text("Ad-Hoc Bin-to-Bin Hareket", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Spacer(Modifier.height(12.dp))
        ScanField("Kaynak Bin", fromBin, { fromBin = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            fromBin = BarcodeIntentResolver.resolve(it).value
        })
        Spacer(Modifier.height(8.dp))
        ScanField("Item / LP", itemOrLp, { itemOrLp = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            val r = BarcodeIntentResolver.resolve(it)
            itemOrLp = r.value
            if (r.lotNo != null) lotNo = r.lotNo
        })
        Spacer(Modifier.height(8.dp))
        ScanField("Hedef Bin", toBin, { toBin = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            toBin = BarcodeIntentResolver.resolve(it).value
        })
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(qty, { qty = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Miktar") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(lotNo, { lotNo = it }, label = { Text("Lot No (opsiyonel)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Button(
            enabled = !busy && fromBin.isNotBlank() && toBin.isNotBlank() && itemOrLp.isNotBlank(),
            modifier = Modifier.fillMaxWidth().height(52.dp),
            onClick = {
                scope.launch {
                    busy = true; status = "Hareket gönderiliyor..."
                    val resolved = BarcodeIntentResolver.resolve(itemOrLp)
                    val isLp = resolved.kind == com.dynops.bcwms.scanner.BarcodeKind.Lp
                    val body = JSONObject().apply {
                        put("fromBin", fromBin.trim()); put("toBin", toBin.trim())
                        put("quantity", qty.toDoubleOrNull() ?: 0.0)
                        if (isLp) put("lpNo", itemOrLp.trim()) else put("itemNo", itemOrLp.trim())
                        if (lotNo.isNotBlank()) put("lotNo", lotNo.trim())
                    }.toString()
                    val r = BcApi.post(context, "movements/Microsoft.NAV.adhoc", body)
                    busy = false
                    status = if (r.ok) "PASS: Hareket kaydedildi (HTTP ${r.httpCode})"
                        else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                }
            }
        ) { Text(if (busy) "Gönderiliyor..." else "✅ Hareketi Onayla", fontWeight = FontWeight.Bold) }
        Spacer(Modifier.height(12.dp))
        StatusText(status)
    }
}

/**
 * Inventory Count — WI §10.6 parity (basic + advanced/blind).
 * Sheet list -> Count Document -> per-line recordCount (counter slot, blind hides system qty)
 * -> Start Recount / Post. BC: countSheets / countSheetLines (warehouse/v2.0, live since v1.0.8.0).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CountModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selected by remember { mutableStateOf<String?>(null) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Sayım sayfaları yükleniyor..."
            val r = BcApi.get(context, "countSheets?\$top=100&\$orderby=createdDateTime desc&\$select=no,locationCode,mode,status,createdDateTime")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Sayım listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "EMPTY: Sayım sayfası yok (HTTP ${r.httpCode})"
                else "PASS: ${rows.size} sayfa (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(Unit) { load() }

    val sel = selected
    if (sel != null) { CountDocument(no = sel, onBack = { selected = null; load() }); return }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { d ->
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(firstValue(d, "no", "batchName"), fontWeight = FontWeight.Bold)
                            Text(firstValue(d, "mode") + " · " + firstValue(d, "status"), fontSize = 12.sp, color = Color.Gray)
                        }
                        Text("Lokasyon: ${firstValue(d, "locationCode")}", fontSize = 12.sp, color = Color.Gray)
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Sayım sayfası yok.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CountDocument(no: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var countLine by remember { mutableStateOf<JSONObject?>(null) }

    fun reload() {
        scope.launch {
            busy = true
            val h = BcApi.get(context, "countSheets('$no')")
            if (h.ok) header = JSONObject(h.body)
            val l = BcApi.get(context, "countSheetLines?\$filter=sheetNo eq '$no'&\$top=200")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    fun action(name: String, okMsg: String) {
        scope.launch {
            busy = true; status = "$name..."
            val r = BcApi.boundAction(context, "countSheets", no, name, "{}")
            busy = false
            status = if (r.ok) "PASS: $okMsg (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            if (r.ok) reload()
        }
    }

    val h = header
    val blind = firstValue(h ?: JSONObject(), "mode").contains("Blind", ignoreCase = true)
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Sayfa Listesi") }
            DocHeaderCard(
                title = no,
                subtitle = "Lokasyon: ${h?.optString("locationCode") ?: ""} · Mod: ${firstValue(h ?: JSONObject(), "mode")} · ${firstValue(h ?: JSONObject(), "status")}",
                badge = if (blind) "BLIND" else null
            )
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            Spacer(Modifier.height(4.dp))
            Text("Satırlar (${lines.size}) — saymak için dokunun", fontWeight = FontWeight.Bold, fontSize = 14.sp)
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(lines) { ln ->
                    val recount = ln.optBoolean("recountRequired")
                    Card(onClick = { countLine = ln }, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(10.dp)) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text("${ln.optString("itemNo")} · Bin ${firstValue(ln, "binCode")}", fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                                if (recount) Text("⟳ recount", fontSize = 11.sp, color = Color(0xFFEF6C00))
                            }
                            val counts = listOf(ln.optDouble("countedQty1"), ln.optDouble("countedQty2"), ln.optDouble("countedQty3"))
                                .filter { it != 0.0 }.joinToString(" / ") { fmtq(it) }.ifBlank { "—" }
                            val sysPart = if (blind) "" else " · Sistem: ${fmtq(ln.optDouble("systemQty"))} · Fark: ${fmtq(ln.optDouble("variance"))}"
                            Text("Sayımlar: $counts$sysPart", fontSize = 12.sp, color = Color.Gray)
                        }
                    }
                }
                if (lines.isEmpty() && !busy) item { EmptyState("Bu sayfada satır yok.") }
            }
        }
        BottomActionBar {
            // Generate lines from bin content when the sheet is empty (the count flow needs lines).
            OutlinedButton(onClick = { action("generateLines", "Satırlar üretildi") }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("➕ Satır Üret") }
            OutlinedButton(onClick = { action("startRecount", "Recount başlatıldı") }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("⟳ Recount") }
            Button(onClick = { action("postSheet", "Sayım kaydedildi") }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("✅ Post", fontWeight = FontWeight.Bold) }
        }
    }

    val cl = countLine
    if (cl != null) {
        CountEntrySheet(line = cl, blind = blind, onDismiss = { countLine = null }, onConfirm = { slot, qty ->
            countLine = null
            scope.launch {
                busy = true; status = "Sayım kaydediliyor..."
                val body = JSONObject().apply { put("counterSlot", slot); put("qty", qty) }.toString()
                val sheetNo = cl.optString("sheetNo").ifBlank { no }
                val lineNo = cl.optInt("lineNo")
                val r = BcApi.post(context, "countSheetLines(sheetNo='$sheetNo',lineNo=$lineNo)/Microsoft.NAV.recordCount", body)
                busy = false
                status = if (r.ok) "PASS: Sayım kaydedildi (slot $slot) (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                if (r.ok) reload()
            }
        })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CountEntrySheet(line: JSONObject, blind: Boolean, onDismiss: () -> Unit, onConfirm: (slot: Int, qty: Double) -> Unit) {
    var slot by remember { mutableStateOf(1) }
    var qty by remember { mutableStateOf("") }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text("Sayım Gir — ${line.optString("itemNo")}", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text("Bin: ${firstValue(line, "binCode")}" + if (blind) " · BLIND (sistem miktarı gizli)" else " · Sistem: ${fmtq(line.optDouble("systemQty"))}", fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(12.dp))
        Text("Sayıcı slotu", fontSize = 12.sp, color = Color.Gray)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            (1..3).forEach { s -> FilterChip(selected = slot == s, onClick = { slot = s }, label = { Text("Sayıcı $s") }) }
        }
        Spacer(Modifier.height(10.dp))
        OutlinedTextField(qty, { qty = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Sayılan Miktar") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Button(modifier = Modifier.fillMaxWidth(), enabled = qty.isNotBlank(), onClick = {
            onConfirm(slot, qty.toDoubleOrNull() ?: 0.0)
        }) { Text("Sayımı Kaydet") }
        Spacer(Modifier.height(24.dp))
    }
}

/**
 * Directed Movement — WI §10.5 (directed variant).
 * Lists warehouse movement documents -> Register. BC: movements / register (warehouse/v2.0).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DirectedMoveModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Hareket belgeleri yükleniyor..."
            val r = BcApi.get(context, "movements?\$top=100&\$orderby=no desc&\$select=no,locationCode,assignedUserId,status")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Hareket listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "EMPTY: Açık yönlendirilmiş hareket belgesi yok (HTTP ${r.httpCode})"
                else "PASS: ${rows.size} belge (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(Unit) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { d ->
                val no = d.optString("no")
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text(no, fontWeight = FontWeight.Bold)
                        Text("Lokasyon: ${firstValue(d, "locationCode")} · Atanan: ${firstValue(d, "assignedUserId")}", fontSize = 12.sp, color = Color.Gray)
                        TextButton(onClick = {
                            scope.launch {
                                loading = true; status = "Register $no..."
                                val r = BcApi.boundAction(context, "movements", no, "register", "{}")
                                loading = false
                                status = if (r.ok) "PASS: $no kaydedildi (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                                if (r.ok) load()
                            }
                        }) { Text("✅ Register") }
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Açık yönlendirilmiş hareket belgesi yok.") }
        }
    }
}

private fun fmtq(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()

/** A simple "coming soon" placeholder for Phase 2 modules. */
@Composable
fun ComingSoonScreen(title: String, note: String) {
    Column(Modifier.fillMaxSize().padding(24.dp)) {
        Text(title, fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Spacer(Modifier.height(12.dp))
        Card(colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF3E0))) {
            Column(Modifier.padding(16.dp)) {
                Text("Yakında (Faz 2)", fontWeight = FontWeight.Bold, color = Color(0xFFEF6C00))
                Spacer(Modifier.height(6.dp))
                Text(note, fontSize = 13.sp)
            }
        }
    }
}
