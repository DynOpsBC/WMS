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
 * Receiving — WI §10.1 parity.
 * Lookup -> Receive Document -> scan item -> qty -> Start/Stop LP -> Post Receipt.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceivingModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selected by remember { mutableStateOf<String?>(null) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val r = BcApi.getWithStandardFallback(context, "receipts?\$top=30&\$select=no,locationCode,sourceNo,vendorSourceName,dueDate,percentComplete")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Mal kabul listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "EMPTY: Açık mal kabul belgesi yok (HTTP ${r.httpCode})"
                else "PASS: ${rows.size} belge (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(Unit) { load() }

    val sel = selected
    if (sel != null) { ReceiveDocument(no = sel, onBack = { selected = null; load() }); return }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { d ->
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text(d.optString("no"), fontWeight = FontWeight.Bold)
                        Text("Lokasyon: ${firstValue(d, "locationCode")} · Kaynak: ${firstValue(d, "sourceNo")}", fontSize = 12.sp, color = Color.Gray)
                        val pct = d.optInt("percentComplete")
                        LinearProgressIndicator(progress = { pct / 100f }, modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Açık mal kabul belgesi yok.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReceiveDocument(no: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var activeLp by remember { mutableStateOf<String?>(null) }

    var showScan by remember { mutableStateOf(false) }
    var showQty by remember { mutableStateOf(false) }
    var scannedItem by remember { mutableStateOf("") }
    var scannedLine by remember { mutableStateOf<JSONObject?>(null) }

    fun reload() {
        scope.launch {
            busy = true
            val h = BcApi.get(context, "receipts('$no')")
            if (h.ok) header = JSONObject(h.body)
            val l = BcApi.get(context, "receiptLines?\$filter=no eq '$no'&\$top=100")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    fun action(name: String, body: String, okMsg: String, onResult: (BcApi.ApiResult) -> Unit = {}) {
        scope.launch {
            busy = true; status = "$name..."
            val r = BcApi.boundAction(context, "receipts", no, name, body)
            busy = false
            status = if (r.ok) "PASS: $okMsg (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            onResult(r)
            if (r.ok) reload()
        }
    }

    val h = header
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Belge Listesi") }
            DocHeaderCard(
                title = no,
                subtitle = "Lokasyon: ${h?.optString("locationCode") ?: ""} · Kaynak: ${h?.optString("sourceNo") ?: "-"}" +
                    (activeLp?.let { "\nAktif LP: $it" } ?: ""),
                percent = h?.optDouble("percentComplete")?.toInt() ?: 0
            )
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            Spacer(Modifier.height(4.dp))
            Text("Satırlar (${lines.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(lines) { ln ->
                    val toReceive = ln.optDouble("qtyToReceive")
                    val received = ln.optDouble("qtyReceived")
                    Card(onClick = {
                        scannedItem = ln.optString("itemNo"); scannedLine = ln; showQty = true
                    }, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(10.dp)) {
                            Text("${ln.optString("itemNo")} — ${ln.optString("description")}", fontWeight = FontWeight.Medium)
                            Text("Kalan: $toReceive · Alınan: $received", fontSize = 12.sp, color = Color.Gray)
                        }
                    }
                }
                if (lines.isEmpty() && !busy) item { EmptyState("Bu belgede satır yok.") }
            }
        }

        BottomActionBar {
            Button(onClick = { showScan = true }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("📷 Scan") }
            if (activeLp == null) {
                OutlinedButton(onClick = {
                    action("startLP", """{"lpTemplateCode":"CARTON-S"}""", "LP başlatıldı") { r ->
                        if (r.ok) activeLp = BcApi.scalarValue(r.body)
                    }
                }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Start LP") }
            } else {
                OutlinedButton(onClick = {
                    val lp = activeLp!!
                    action("stopLP", JSONObject().apply { put("lpNo", lp); put("printLabel", true) }.toString(), "LP kapatıldı") { r ->
                        if (r.ok) activeLp = null
                    }
                }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Stop LP") }
            }
        }
        BottomActionBar {
            Button(
                onClick = { action("post", """{"print":false,"invoice":false}""", "Mal kabul kaydedildi") },
                enabled = !busy, modifier = Modifier.fillMaxWidth()
            ) { Text("✅ Post Receipt", fontWeight = FontWeight.Bold) }
        }
    }

    if (showScan) {
        ScanItemSheet(title = "Item Tara", onDismiss = { showScan = false }, onItem = { item, line ->
            scannedItem = item; scannedLine = line; showScan = false; showQty = true
        }, lines = lines, matchKey = "itemNo")
    }
    if (showQty) {
        val line = scannedLine
        QuantityDialogSheet(
            title = "Alınan Miktar",
            itemNo = scannedItem,
            initialQty = line?.optDouble("qtyToReceive")?.takeIf { it > 0 } ?: 1.0,
            initialUom = line?.optString("unitOfMeasureCode") ?: "",
            onDismiss = { showQty = false },
            onConfirm = { res ->
                showQty = false
                val ln = scannedLine
                if (ln == null) { status = "HATA: Satır eşleşmedi — listeden seçin"; return@QuantityDialogSheet }
                scope.launch {
                    busy = true; status = "Satır güncelleniyor..."
                    val body = JSONObject().apply {
                        put("qtyToReceive", res.quantity)
                        if (res.lotNo.isNotBlank()) put("lotNo", res.lotNo)
                        if (res.serialNo.isNotBlank()) put("serialNo", res.serialNo)
                        activeLp?.let { put("licensePlateNo", it) }
                    }.toString()
                    val lineNo = ln.optInt("lineNo")
                    val r = BcApi.patch(context, "receiptLines(no='$no',lineNo=$lineNo)", body)
                    busy = false
                    status = if (r.ok) "PASS: Satır güncellendi (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                    if (r.ok) reload()
                }
            }
        )
    }
}

/** Generic scan sheet that tries to match the scanned item against existing lines. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScanItemSheet(
    title: String,
    onDismiss: () -> Unit,
    onItem: (item: String, line: JSONObject?) -> Unit,
    lines: List<JSONObject> = emptyList(),
    matchKey: String = "itemNo",
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var item by remember { mutableStateOf("") }
    var hint by remember { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().padding(20.dp)) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Spacer(Modifier.height(12.dp))
            ScanField("Item No", item, { item = it }, modifier = Modifier.fillMaxWidth(), onScanned = { raw ->
                val resolved = BarcodeIntentResolver.resolve(raw)
                item = resolved.itemNo ?: raw
                hint = "Tarandı: ${resolved.kind} → ${resolved.value}"
            })
            if (hint.isNotBlank()) { Spacer(Modifier.height(6.dp)); Text(hint, fontSize = 12.sp, color = Color.Gray) }
            Spacer(Modifier.height(16.dp))
            Button(enabled = item.isNotBlank(), modifier = Modifier.fillMaxWidth(), onClick = {
                val match = lines.firstOrNull { it.optString(matchKey).equals(item.trim(), ignoreCase = true) }
                onItem(item.trim(), match)
            }) { Text("Devam") }
            Spacer(Modifier.height(24.dp))
        }
    }
}
