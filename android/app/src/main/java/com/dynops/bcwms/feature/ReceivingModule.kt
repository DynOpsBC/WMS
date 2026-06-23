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
 * Mal Kabul (Receiving).
 *
 * Tek bir ana ekran, 2 sekme:
 *  - "Whse Receipt": yönetilen lokasyon (BLUE/SILVER) için varolan Warehouse Receipt belgeleri
 *  - "Purchase Order": yönetilmeyen veya bypass senaryosunda Whse Receipt olmadan PO satırı doğrudan mal kabul
 *
 * Her ikisinde de qty/LP/bin set + post akışı tek dokunuşla biter.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceivingModule() {
    var tab by remember { mutableStateOf(0) }
    val tabs = listOf("📋 Whse Receipt", "🛒 Purchase Order")

    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab) {
            tabs.forEachIndexed { i, title ->
                Tab(selected = tab == i, onClick = { tab = i }, text = { Text(title, fontSize = 13.sp) })
            }
        }
        when (tab) {
            0 -> WhseReceiptTab()
            1 -> PurchaseOrderTab()
        }
    }
}

// ============================================================
// Tab 1: Warehouse Receipt (orijinal akış)
// ============================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WhseReceiptTab() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selected by remember { mutableStateOf<String?>(null) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var search by remember { mutableStateOf("") }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val filter = com.dynops.bcwms.ui.buildODataFilter(com.dynops.bcwms.ui.searchClause("no", search))
            val r = BcApi.getWithStandardFallback(context, "receipts?\$top=100&\$orderby=no desc&\$select=no,locationCode,sourceNo,vendorSourceName,dueDate,percentComplete$filter")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Mal kabul listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "EMPTY: Açık Whse Receipt belgesi yok (HTTP ${r.httpCode})"
                else "PASS: ${rows.size} belge (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(Unit) { load() }

    val sel = selected
    if (sel != null) { ReceiveDocument(no = sel, onBack = { selected = null; load() }); return }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        Spacer(Modifier.height(8.dp))
        com.dynops.bcwms.ui.DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() }, label = "Whse Receipt no ile ara")
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
            if (rows.isEmpty() && !loading) item { EmptyState("Açık Whse Receipt belgesi yok. PO'dan direkt mal kabul için sağdaki sekmeyi kullanın.") }
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
            val canPost = com.dynops.bcwms.lib.ActionGuards.hasQuantity(lines, field = "qtyToReceive")
            Button(
                onClick = { action("post", """{"print":false,"invoice":false}""", "Mal kabul kaydedildi") },
                enabled = !busy && canPost,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    if (canPost) "✅ Post Receipt" else "Önce satırlara miktar girin",
                    fontWeight = FontWeight.Bold,
                )
            }
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

// ============================================================
// Tab 2: Purchase Order direct receive
// ============================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PurchaseOrderTab() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selected by remember { mutableStateOf<String?>(null) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var releasedOnly by remember { mutableStateOf(true) }
    var search by remember { mutableStateOf("") }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            // PDF §3: belge no arama yoktu. Sabit "Released" filter ile birleşik clause.
            val clauses = buildList {
                if (releasedOnly) add("status eq 'Released'")
                if (search.isNotBlank()) add("startswith(no,'${search.trim().replace("'", "''")}')")
            }
            val filter = if (clauses.isEmpty()) "" else "&\$filter=" + clauses.joinToString(" and ")
            val r = BcApi.get(
                context,
                "purchaseSources?\$top=100&\$orderby=no desc$filter&\$select=no,vendorNo,vendorName,locationCode,expectedReceiptDate,status,lineCount,outstandingQty,percentComplete,requiresWhseReceipt,directReceiveAllowed"
            )
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: PO listesi alınamadı (HTTP ${r.httpCode}) — ${BcApi.errorMessage(r.body).take(120)}"
                else if (rows.isEmpty()) "EMPTY: ${if (releasedOnly) "Released" else "Açık"} PO yok (HTTP ${r.httpCode})"
                else "PASS: ${rows.size} satınalma siparişi (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(releasedOnly) { load() }

    val sel = selected
    if (sel != null) { ReceivePurchaseOrder(no = sel, onBack = { selected = null; load() }); return }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
            Spacer(Modifier.width(12.dp))
            FilterChip(
                selected = releasedOnly,
                onClick = { releasedOnly = !releasedOnly },
                label = { Text(if (releasedOnly) "Sadece Released" else "Tüm Durumlar", fontSize = 12.sp) }
            )
        }
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(
            value = search,
            onValueChange = { search = it },
            singleLine = true,
            label = { Text("PO no ile ara (örn: 106040)") },
            trailingIcon = { TextButton(onClick = { load() }) { Text("🔎") } },
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { d ->
                val requiresWhse = d.optBoolean("requiresWhseReceipt", false)
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(d.optString("no"), fontWeight = FontWeight.Bold)
                            Row {
                                if (requiresWhse) Text("⚠ Whse Rcpt", fontSize = 11.sp, color = Color(0xFFD97706), modifier = Modifier.padding(end = 6.dp))
                                Text(firstValue(d, "status"), fontSize = 12.sp, color = Color.Gray)
                            }
                        }
                        Text("Tedarikçi: ${firstValue(d, "vendorName")} (${firstValue(d, "vendorNo")})", fontSize = 12.sp, color = Color.Gray)
                        Text("Lokasyon: ${firstValue(d, "locationCode")} · Satır: ${d.optInt("lineCount")} · Kalan: ${d.optDouble("outstandingQty")}", fontSize = 12.sp, color = Color.Gray)
                        val pct = d.optInt("percentComplete")
                        if (pct > 0) LinearProgressIndicator(progress = { pct / 100f }, modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Uygun satınalma siparişi yok.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReceivePurchaseOrder(no: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var invoiceToo by remember { mutableStateOf(false) }
    var qtyLine by remember { mutableStateOf<JSONObject?>(null) }
    var showScan by remember { mutableStateOf(false) }

    fun reload() {
        scope.launch {
            busy = true
            val h = BcApi.get(context, "purchaseSources('$no')")
            if (h.ok) header = JSONObject(h.body)
            val l = BcApi.get(context, "purchaseSourceLines?\$filter=no eq '$no' and type eq 'Item'&\$top=200&\$orderby=lineNo")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    val h = header
    val directAllowed = h?.let { it.optBoolean("directReceiveAllowed", true) } ?: true
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ PO Listesi") }
            DocHeaderCard(
                title = no,
                subtitle = "Tedarikçi: ${firstValue(h ?: JSONObject(), "vendorName")} (${firstValue(h ?: JSONObject(), "vendorNo")})\n" +
                    "Lokasyon: ${firstValue(h ?: JSONObject(), "locationCode")} · Durum: ${firstValue(h ?: JSONObject(), "status")}",
                percent = h?.optDouble("percentComplete")?.toInt() ?: 0
            )
            if (h != null && !directAllowed) {
                Spacer(Modifier.height(8.dp))
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = Color(0xFFFEF3C7)),
                ) {
                    Text(
                        "⚠ Bu lokasyon (${firstValue(h, "locationCode")}) Warehouse Receipt zorunlu kılıyor. " +
                            "Direkt Post Receive yapılamaz. Whse Receipt sekmesinden ilgili belgeyi açıp mal kabulü tamamlayın.",
                        modifier = Modifier.padding(10.dp),
                        fontSize = 12.sp,
                        color = Color(0xFF92400E),
                    )
                }
            }
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            Spacer(Modifier.height(4.dp))
            Text("Satırlar (${lines.size}) — qty/bin için dokunun", fontWeight = FontWeight.Bold, fontSize = 14.sp)
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(lines) { ln ->
                    val outstanding = ln.optDouble("outstandingQuantity")
                    val toReceive = ln.optDouble("qtyToReceive")
                    val received = ln.optDouble("qtyReceived")
                    Card(
                        onClick = { if (directAllowed) qtyLine = ln },
                        enabled = directAllowed,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(Modifier.padding(10.dp)) {
                            Text("${ln.optString("itemNo")} — ${ln.optString("description")}", fontWeight = FontWeight.Medium)
                            Text("Kalan: $outstanding · Alınacak: $toReceive · Alınan: $received", fontSize = 12.sp, color = Color.Gray)
                            Text("Bin: ${firstValue(ln, "binCode").ifBlank { "-" }} · UoM: ${firstValue(ln, "unitOfMeasureCode")}", fontSize = 12.sp, color = Color.Gray)
                        }
                    }
                }
                if (lines.isEmpty() && !busy) item { EmptyState("Bu PO'da satır yok (veya tümü tamamlandı).") }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = invoiceToo, onCheckedChange = { invoiceToo = it })
                Text("Aynı zamanda faturalandır", fontSize = 13.sp)
            }
        }

        BottomActionBar {
            OutlinedButton(onClick = { showScan = true }, enabled = !busy && directAllowed, modifier = Modifier.weight(1f)) { Text("📷 Item Tara") }
        }
        BottomActionBar {
            Button(
                onClick = {
                    scope.launch {
                        busy = true; status = "Post-Receive..."
                        val body = JSONObject().apply { put("invoice", invoiceToo) }.toString()
                        val r = BcApi.boundAction(context, "purchaseSources", no, "receive", body)
                        busy = false
                        status = if (r.ok) "PASS: PO mal kabul kaydedildi (HTTP ${r.httpCode})"
                            else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                        if (r.ok) reload()
                    }
                },
                enabled = !busy && directAllowed, modifier = Modifier.fillMaxWidth()
            ) { Text(if (invoiceToo) "✅ Post Receive & Invoice" else "✅ Post Receive", fontWeight = FontWeight.Bold) }
        }
    }

    val ql = qtyLine
    if (ql != null) {
        QuantityDialogSheet(
            title = "Alınacak Miktar",
            itemNo = ql.optString("itemNo"),
            initialQty = ql.optDouble("qtyToReceive").takeIf { it > 0 }
                ?: ql.optDouble("outstandingQuantity").takeIf { it > 0 } ?: 1.0,
            initialUom = ql.optString("unitOfMeasureCode"),
            showLotSerial = true,
            onDismiss = { qtyLine = null },
            onConfirm = { res ->
                qtyLine = null
                scope.launch {
                    busy = true; status = "Satır güncelleniyor..."
                    val lineNo = ql.optInt("lineNo")
                    val body = JSONObject().apply {
                        put("qtyToReceive", res.quantity)
                    }.toString()
                    val r = BcApi.patch(
                        context,
                        "purchaseSourceLines(documentType='Order',no='$no',lineNo=$lineNo)",
                        body
                    )
                    busy = false
                    status = if (r.ok) "PASS: PO satırı qty=${res.quantity} (HTTP ${r.httpCode})"
                        else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                    if (r.ok) reload()
                }
            }
        )
    }

    if (showScan) {
        ScanItemSheet(title = "Item Tara (PO)", onDismiss = { showScan = false }, onItem = { _, line ->
            showScan = false
            qtyLine = line
        }, lines = lines, matchKey = "itemNo")
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
    var item by remember { mutableStateOf("") }
    var hint by remember { mutableStateOf("") }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
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
