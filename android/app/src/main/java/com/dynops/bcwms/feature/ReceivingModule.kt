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
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
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
    val tabs = listOf("📋 Ambar Mal Kabul", "🛒 Satın Alma Siparişi")

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
    var showAll by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val myUser = if (showAll) "" else BcApi.currentUserId(context)
            // Arama yalnız belge no'ya değil, SATIRLARDAKİ ürün no'ya da bakar:
            // "1002" yazınca 1002'yi içeren belgeler de listede kalır. Belgeler
            // aramasız çekilir, eşleşme istemcide birleştirilir.
            val filter = com.dynops.bcwms.ui.buildODataFilter(
                com.dynops.bcwms.ui.assignedToMeClause(myUser, enabled = !showAll),
            )
            val r = BcApi.getWithStandardFallback(context, "receipts?\$top=100&\$orderby=no desc&\$select=no,locationCode,assignedUserId,sourceNo,vendorSourceName,dueDate,percentComplete$filter")
            val all = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            val q = search.trim()
            var itemHit = 0
            rows = if (q.isBlank()) all else {
                val itemDocsSet = com.dynops.bcwms.ui.docsContainingItem(context, "receiptLines", q)
                all.filter {
                    it.optString("no").contains(q, ignoreCase = true) ||
                        firstValue(it, "sourceNo").contains(q, ignoreCase = true) ||
                        it.optString("no") in itemDocsSet
                }.also { filtered -> itemHit = filtered.count { it.optString("no") in itemDocsSet } }
            }
            loading = false
            status = if (!r.ok) "HATA: Mal kabul listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) (if (q.isNotBlank()) "BOŞ: '$q' ile eşleşen belge/ürün yok" else if (showAll) "BOŞ: Açık ambar mal kabul belgesi yok (HTTP ${r.httpCode})" else "BOŞ: Size atanmış mal kabul yok (HTTP ${r.httpCode})")
                else "TAMAM: ${rows.size} belge" + (if (itemHit > 0) " · 🔎 '$q' ürününü içerenler dahil" else "")
        }
    }
    LaunchedEffect(showAll) { load() }

    var itemDocs by remember { mutableStateOf<Pair<String, Set<String>>?>(null) }
    val sel = selected
    if (sel != null) { ReceiveDocument(no = sel, onBack = { selected = null; load() }); return }

    // Belge listesinde ürün okut → o ürünü içeren belgeleri bul (girme-çıkma yok).
    DocListScanHandler(
        enabled = true,
        linesEndpoint = "receiptLines",
        documentsEndpoint = "receipts",
        acceptDocTypes = setOf("receipt"),
        onDocument = { selected = it },
    ) { item, docs ->
        when { docs.isEmpty() -> status = "⚠️ '$item' açık belgede yok"; docs.size == 1 -> selected = docs.first(); else -> { itemDocs = item to docs; status = "TAMAM: '$item' → ${docs.size} belge" } }
    }
    val shownRows = itemDocs?.let { f -> rows.filter { it.optString("no") in f.second } } ?: rows

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
            Spacer(Modifier.width(12.dp))
            FilterChip(selected = !showAll, onClick = { showAll = false }, label = { Text("Bana atanan") })
            Spacer(Modifier.width(6.dp))
            FilterChip(selected = showAll, onClick = { showAll = true }, label = { Text("Tümü") })
        }
        Spacer(Modifier.height(8.dp))
        com.dynops.bcwms.ui.DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() }, label = "Mal kabul no ile ara")
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        if (itemDocs != null) { ScanFilterChip("${itemDocs!!.first} → ${itemDocs!!.second.size} belge") { itemDocs = null } }
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(shownRows) { d ->
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text(d.optString("no"), fontWeight = FontWeight.Bold)
                        Text("Lokasyon: ${firstValue(d, "locationCode")} · Kaynak: ${firstValue(d, "sourceNo")} · 👤 Atanan Kullanıcı: ${firstValue(d, "assignedUserId").ifBlank { "-" }}", fontSize = 12.sp, color = Color.Gray)
                        val pct = d.optInt("percentComplete")
                        LinearProgressIndicator(progress = { pct / 100f }, modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState(if (showAll) "Açık ambar mal kabul belgesi yok. PO'dan direkt mal kabul için sağdaki sekmeyi kullanın." else "Size atanmış mal kabul yok. Tümünü görmek için \"Tümü\" seçin.") }
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
    // İki adımlı kabul: önce "Hazır", sonra "Kaydet (post)".
    var readyMarked by remember(no) { mutableStateOf(false) }

    var showScan by remember { mutableStateOf(false) }
    var showQty by remember { mutableStateOf(false) }
    var scannedItem by remember { mutableStateOf("") }
    var scannedLine by remember { mutableStateOf<JSONObject?>(null) }
    // "Paletten ekrana": donanım tarayıcı ile okutunca ilgili satırı bul/filtrele.
    var scanFilter by remember { mutableStateOf("") }
    var scanLot by remember { mutableStateOf("") }
    var scanSerial by remember { mutableStateOf("") }
    // İade birleştirme: aynı ürün+bin satırlarını tek grupta göster, tek okutmada dağıt.
    var merge by remember { mutableStateOf(false) }
    var groupTarget by remember { mutableStateOf<LineGroup?>(null) }
    // Konfigüre edilebilir kolonlar (WI "Choose Columns").
    var columns by remember { mutableStateOf(ColumnPrefs.get(context, "receipt", GridColumns.receipt)) }
    var showColumns by remember { mutableStateOf(false) }

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
            status = if (r.ok) "TAMAM: $okMsg (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            onResult(r)
            if (r.ok) reload()
        }
    }

    val h = header
    // Donanım tarayıcı: satırı okut → 1 eşleşme miktar ekranını açar, çok eşleşme
    // listeyi o ürüne filtreler, eşleşme yoksa uyarı. Dialog/sheet açıkken kapalı.
    DocumentScanHandler(
        enabled = !showQty && !showScan,
        lines = lines,
        onSingleMatch = { line, r ->
            scannedItem = line.optString("itemNo"); scannedLine = line
            // BC'de satıra zaten atanmış lot/seri varsa onu kullan; yoksa barkoddan (GS1 AI) gelen değere düş.
            scanLot = line.optString("lotNo").ifBlank { r.lotNo ?: "" }
            scanSerial = line.optString("serialNo").ifBlank { r.serialNo ?: "" }
            scanFilter = ""
            showQty = true
        },
        onMultiMatch = { itemNo, _ -> scanFilter = itemNo; status = "TAMAM: '$itemNo' için birden fazla satır — birini seçin" },
        onNoMatch = { r -> status = "⚠️ '${r.itemNo ?: r.value}' bu belgede yok" },
    )
    val displayLines = if (scanFilter.isBlank()) lines else lines.filter { matchLinesByBarcode(listOf(it), com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve(scanFilter)).isNotEmpty() }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Belge Listesi") }
            DocHeaderCard(
                title = no,
                subtitle = "Lokasyon: ${h?.optString("locationCode") ?: ""} · Kaynak: ${h?.optString("sourceNo") ?: "-"}" +
                    (activeLp?.let { "\nAktif LP: $it" } ?: ""),
                badge = firstValue(h ?: JSONObject(), "assignedUserId").ifBlank { "Atanmadı" },
                percent = h?.optDouble("percentComplete")?.toInt() ?: 0
            )
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            Spacer(Modifier.height(4.dp))
            val capReceipt: (JSONObject) -> Double = { l ->
                val q = l.optDouble("quantity"); val rec = l.optDouble("qtyReceived")
                if (q > 0) (q - rec).coerceAtLeast(0.0) else (l.optDouble("qtyToReceive").takeIf { it > 0 } ?: 1.0)
            }
            val groups = if (merge) groupLines(displayLines, capReceipt) else emptyList()
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (merge) "Gruplar (${groups.size})" else "Satırlar (${displayLines.size}/${lines.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.weight(1f))
                if (!merge) { TextButton(onClick = { showColumns = true }) { Text("⚙ Kolonlar", fontSize = 12.sp) } }
                FilterChip(selected = merge, onClick = { merge = !merge }, label = { Text("🔗 Birleştir", fontSize = 12.sp) })
            }
            if (scanFilter.isNotBlank()) { ScanFilterChip(scanFilter) { scanFilter = "" }; Spacer(Modifier.height(4.dp)) }
            if (merge) {
                LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(groups) { g ->
                        val staged = g.lines.sumOf { it.optDouble("qtyToReceive") }
                        val done = staged > 0
                        Card(onClick = { groupTarget = g }, modifier = Modifier.fillMaxWidth(), colors = doneCardColors(done)) {
                            Column(Modifier.padding(14.dp)) {
                                Text("${donePrefix(done)}${g.itemNo} — ${g.description}", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                                Text("${g.count} satır · Toplam kalan: ${fmtNum(g.totalOutstanding)}" + if (staged > 0) " · Girilen: ${fmtNum(staged)}" else "", fontSize = 12.sp, color = Color.Gray)
                            }
                        }
                    }
                    if (groups.isEmpty() && !busy) item { EmptyState("Grup yok.") }
                }
            } else {
                // WI-benzeri konfigüre edilebilir kolonlu grid.
                LineGrid(
                    defs = GridColumns.receipt,
                    columns = columns,
                    rows = displayLines,
                    modifier = Modifier.weight(1f),
                    isDone = { lineDone(it, LineModule.RECEIPT) },
                    onRowClick = { ln ->
                        scannedItem = ln.optString("itemNo"); scannedLine = ln
                        scanLot = ln.optString("lotNo"); scanSerial = ln.optString("serialNo")
                        showQty = true
                    },
                )
            }
        }

        BottomActionBar {
            OutlinedButton(onClick = {
                scope.launch {
                    busy = true; status = "Atanıyor..."
                    val me = BcApi.currentUserId(context)
                    val r = if (me.isBlank()) BcApi.ApiResult(false, 0, "Kullanıcı çözülemedi")
                        else BcApi.boundAction(context, "receipts", no, "assignToUser", JSONObject().apply { put("userId", me) }.toString())
                    busy = false
                    status = if (r.ok) "TAMAM: Bana atandı (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                    if (r.ok) reload()
                }
            }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Bana Ata") }
            Button(onClick = { showScan = true }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("📷 Tara") }
            if (activeLp == null) {
                OutlinedButton(onClick = {
                    action("startLP", """{"lpTemplateCode":"CARTON-S"}""", "LP başlatıldı") { r ->
                        if (r.ok) activeLp = BcApi.scalarValue(r.body)
                    }
                }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("LP Başlat") }
            } else {
                OutlinedButton(onClick = {
                    val lp = activeLp!!
                    action("stopLP", JSONObject().apply { put("lpNo", lp); put("printLabel", true) }.toString(), "LP kapatıldı") { r ->
                        if (r.ok) activeLp = null
                    }
                }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("LP Kapat") }
            }
        }
        BottomActionBar {
            val canPost = com.dynops.bcwms.lib.ActionGuards.hasQuantity(lines, field = "qtyToReceive")
            // İKİ ADIM: operatör miktarları girer ve "Hazır" der (BC'ye postalanmaz,
            // belge hazır durumda bekler); postalamayı sorumlu BC'den ya da
            // buradaki ikinci butondan yapar. Eskiden tek dokunuşla anında
            // postalanıyordu, geri alınamıyordu.
            if (!readyMarked) {
                Button(
                    onClick = {
                        readyMarked = true
                        status = "Mal kabul HAZIR — sorumlu onaylayınca kaydedilecek."
                    },
                    enabled = !busy && canPost,
                    modifier = Modifier.fillMaxWidth().height(54.dp),
                ) {
                    Text(
                        if (canPost) "Hazır olarak işaretle" else "Önce satırlara miktar girin",
                        fontWeight = FontWeight.Bold,
                    )
                }
            } else {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = { readyMarked = false; status = "" },
                        enabled = !busy,
                        modifier = Modifier.weight(1f).height(54.dp),
                    ) { Text("Geri al") }
                    Button(
                        onClick = { action("post", """{"print":false,"invoice":false}""", "Mal kabul kaydedildi") },
                        enabled = !busy && canPost,
                        modifier = Modifier.weight(1.4f).height(54.dp),
                    ) { Text("Kaydet (post)", fontWeight = FontWeight.Bold) }
                }
            }
        }
    }

    if (showScan) {
        ScanItemSheet(title = "Ürün Tara", onDismiss = { showScan = false }, onItem = { item, line ->
            scannedItem = item; scannedLine = line
            scanLot = line?.optString("lotNo") ?: ""; scanSerial = line?.optString("serialNo") ?: ""
            showScan = false; showQty = true
        }, lines = lines, matchKey = "itemNo")
    }
    if (showQty) {
        val line = scannedLine
        QuantityDialogSheet(
            title = "Alınan Miktar",
            itemNo = scannedItem,
            initialQty = line?.optDouble("qtyToReceive")?.takeIf { it > 0 } ?: 1.0,
            initialUom = line?.optString("unitOfMeasureCode") ?: "",
            initialLot = scanLot,
            initialSerial = scanSerial,
            onDismiss = { showQty = false; scanLot = ""; scanSerial = "" },
            onConfirm = { res ->
                showQty = false; scanLot = ""; scanSerial = ""
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
                    status = if (r.ok) "TAMAM: Satır güncellendi (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                    if (r.ok) reload()
                }
            }
        )
    }
    val gt = groupTarget
    if (gt != null) {
        val capReceipt: (JSONObject) -> Double = { l ->
            val q = l.optDouble("quantity"); val rec = l.optDouble("qtyReceived")
            if (q > 0) (q - rec).coerceAtLeast(0.0) else (l.optDouble("qtyToReceive").takeIf { it > 0 } ?: 1.0)
        }
        QuantityDialogSheet(
            title = "İade Miktarı (${gt.count} satıra dağıtılır)",
            itemNo = gt.itemNo,
            initialQty = gt.totalOutstanding.takeIf { it > 0 } ?: 1.0,
            initialUom = gt.lines.first().optString("unitOfMeasureCode"),
            onDismiss = { groupTarget = null },
            onConfirm = { res ->
                groupTarget = null
                scope.launch {
                    busy = true; status = "Grup dağıtılıyor..."
                    val plan = distributeQty(gt, res.quantity, capReceipt)
                    var okCount = 0
                    for ((ln, q) in plan) {
                        val body = JSONObject().apply {
                            put("qtyToReceive", q)
                            activeLp?.let { put("licensePlateNo", it) }
                        }.toString()
                        val r = BcApi.patch(context, "receiptLines(no='$no',lineNo=${ln.optInt("lineNo")})", body)
                        if (r.ok) okCount++
                    }
                    busy = false
                    status = "TAMAM: $okCount/${plan.size} satıra dağıtıldı (toplam ${fmtNum(res.quantity)})"
                    reload()
                }
            }
        )
    }
    if (showColumns) {
        ChooseColumnsSheet(
            defs = GridColumns.receipt,
            initial = columns,
            onDismiss = { showColumns = false },
            onSave = { newCols -> columns = newCols; ColumnPrefs.save(context, "receipt", newCols); showColumns = false },
        )
    }
}

private fun fmtNum(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()

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
            // PDF §3: belge no arama yoktu. Arama artık belge no + satıcı adı +
            // SATIRLARDAKİ ürün no'ya bakar ("1002" → 1002 içeren PO'lar).
            val filter = if (releasedOnly) "&\$filter=status eq 'Released'" else ""
            val r = BcApi.get(
                context,
                "purchaseSources?\$top=100&\$orderby=no desc$filter&\$select=no,vendorNo,vendorName,locationCode,expectedReceiptDate,status,lineCount,outstandingQty,percentComplete,requiresWhseReceipt,directReceiveAllowed"
            )
            val all = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            val q = search.trim()
            var itemHit = 0
            rows = if (q.isBlank()) all else {
                val itemDocsSet = com.dynops.bcwms.ui.docsContainingItem(context, "purchaseSourceLines", q)
                all.filter {
                    it.optString("no").contains(q, ignoreCase = true) ||
                        firstValue(it, "vendorName").contains(q, ignoreCase = true) ||
                        firstValue(it, "vendorNo").contains(q, ignoreCase = true) ||
                        it.optString("no") in itemDocsSet
                }.also { filtered -> itemHit = filtered.count { it.optString("no") in itemDocsSet } }
            }
            loading = false
            status = if (!r.ok) "HATA: PO listesi alınamadı (HTTP ${r.httpCode}) — ${BcApi.errorMessage(r.body).take(120)}"
                else if (rows.isEmpty()) (if (q.isNotBlank()) "BOŞ: '$q' ile eşleşen PO/ürün yok" else "BOŞ: ${if (releasedOnly) "serbest bırakılmış" else "açık"} PO yok (HTTP ${r.httpCode})")
                else "TAMAM: ${rows.size} satınalma siparişi" + (if (itemHit > 0) " · 🔎 '$q' ürününü içerenler dahil" else "")
        }
    }
    LaunchedEffect(releasedOnly) { load() }

    var itemDocs by remember { mutableStateOf<Pair<String, Set<String>>?>(null) }
    val sel = selected
    if (sel != null) { ReceivePurchaseOrder(no = sel, onBack = { selected = null; load() }); return }

    DocListScanHandler(
        enabled = true,
        linesEndpoint = "purchaseSourceLines",
        documentsEndpoint = "purchaseSources",
        acceptDocTypes = setOf("purchaseOrder"),
        onDocument = { selected = it },
    ) { item, docs ->
        when { docs.isEmpty() -> status = "⚠️ '$item' açık PO'da yok"; docs.size == 1 -> selected = docs.first(); else -> { itemDocs = item to docs; status = "TAMAM: '$item' → ${docs.size} PO" } }
    }
    val shownRows = itemDocs?.let { f -> rows.filter { it.optString("no") in f.second } } ?: rows

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
            Spacer(Modifier.width(12.dp))
            FilterChip(
                selected = releasedOnly,
                onClick = { releasedOnly = !releasedOnly },
                label = { Text(if (releasedOnly) "Sadece Serbest" else "Tüm Durumlar", fontSize = 12.sp) }
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
        if (itemDocs != null) { ScanFilterChip("${itemDocs!!.first} → ${itemDocs!!.second.size} PO") { itemDocs = null } }
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(shownRows) { d ->
                val requiresWhse = d.optBoolean("requiresWhseReceipt", false)
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(d.optString("no"), fontWeight = FontWeight.Bold)
                            Row {
                                if (requiresWhse) Text("⚠ Ambar Girişi", fontSize = 11.sp, color = Color(0xFFD97706), modifier = Modifier.padding(end = 6.dp))
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
    var scanFilter by remember { mutableStateOf("") }
    // İki adımlı kabul: önce "Hazır", sonra kayıt.
    var readyMarked by remember(no) { mutableStateOf(false) }
    // Ambar Mal Kabul'deki gibi konfigüre edilebilir kolonlar (kendi tercihi:
    // PO satırlarının alan adları farklı olduğu için ayrı kolon seti + ayrı anahtar).
    var columns by remember { mutableStateOf(ColumnPrefs.get(context, "purchaseOrder", GridColumns.purchaseOrder)) }
    var showColumns by remember { mutableStateOf(false) }

    fun reload() {
        scope.launch {
            busy = true
            // Başlık ve satırlar bağımsız — paralel çek.
            coroutineScope {
                val hJob = async { BcApi.get(context, "purchaseSources('$no')") }
                val lJob = async { BcApi.get(context, "purchaseSourceLines?\$filter=no eq '$no' and type eq 'Item'&\$top=200&\$orderby=lineNo") }
                val h = hJob.await()
                if (h.ok) header = JSONObject(h.body)
                val l = lJob.await()
                lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            }
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    val h = header
    val directAllowed = h?.let { it.optBoolean("directReceiveAllowed", true) } ?: true
    DocumentScanHandler(
        enabled = qtyLine == null && !showScan,
        lines = lines,
        onSingleMatch = { line, _ -> if (directAllowed) { scanFilter = ""; qtyLine = line } },
        onMultiMatch = { itemNo, _ -> scanFilter = itemNo; status = "TAMAM: '$itemNo' için birden fazla satır — birini seçin" },
        onNoMatch = { r -> status = "⚠️ '${r.itemNo ?: r.value}' bu PO'da yok" },
    )
    val displayLines = if (scanFilter.isBlank()) lines else lines.filter { matchLinesByBarcode(listOf(it), com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve(scanFilter)).isNotEmpty() }
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
                        "⚠ Bu lokasyon (${firstValue(h, "locationCode")}) Ambar Mal Kabul belgesi zorunlu kılıyor. " +
                            "Doğrudan mal kabul yapılamaz. Ambar Mal Kabul sekmesinden ilgili belgeyi açıp mal kabulü tamamlayın.",
                        modifier = Modifier.padding(10.dp),
                        fontSize = 12.sp,
                        color = Color(0xFF92400E),
                    )
                }
            }
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Satırlar (${displayLines.size}/${lines.size}) — qty/bin için dokunun", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                if (scanFilter.isNotBlank()) { Spacer(Modifier.width(8.dp)); ScanFilterChip(scanFilter) { scanFilter = "" } }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { showColumns = true }) { Text("Kolonlar", fontSize = 12.sp) }
            }
            if (displayLines.isEmpty() && !busy) {
                EmptyState(if (scanFilter.isNotBlank()) "Filtreyle eşleşen satır yok." else "Bu PO'da satır yok (veya tümü tamamlandı).")
            } else {
                // Ambar Mal Kabul ile aynı konfigüre edilebilir kolonlu grid.
                LineGrid(
                    defs = GridColumns.purchaseOrder,
                    columns = columns,
                    rows = displayLines,
                    modifier = Modifier.weight(1f),
                    isDone = { lineDone(it, LineModule.PURCHASE) },
                    onRowClick = { ln -> if (directAllowed) qtyLine = ln },
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = invoiceToo, onCheckedChange = { invoiceToo = it })
                Text("Aynı zamanda faturalandır", fontSize = 13.sp)
            }
        }

        BottomActionBar {
            OutlinedButton(onClick = { showScan = true }, enabled = !busy && directAllowed, modifier = Modifier.weight(1f)) { Text("📷 Ürün Tara") }
        }
        BottomActionBar {
            // İki adım (bkz. Ambar Mal Kabul): önce "Hazır", sonra kayıt.
            if (!readyMarked) {
                Button(
                    onClick = { readyMarked = true; status = "Mal kabul HAZIR — onaylayınca kaydedilecek." },
                    enabled = !busy && directAllowed,
                    modifier = Modifier.fillMaxWidth().height(54.dp),
                ) { Text("Hazır olarak işaretle", fontWeight = FontWeight.Bold) }
            } else Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { readyMarked = false; status = "" },
                    enabled = !busy,
                    modifier = Modifier.weight(1f).height(54.dp),
                ) { Text("Geri al") }
                Button(
                    onClick = {
                        scope.launch {
                            busy = true; status = "Mal kabul kaydı..."
                            val body = JSONObject().apply { put("invoice", invoiceToo) }.toString()
                            val r = BcApi.boundAction(context, "purchaseSources", no, "receive", body)
                            busy = false
                            status = if (r.ok) "TAMAM: PO mal kabul kaydedildi (HTTP ${r.httpCode})"
                                else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                            if (r.ok) { readyMarked = false; reload() }
                        }
                    },
                    enabled = !busy && directAllowed,
                    modifier = Modifier.weight(1.4f).height(54.dp),
                ) { Text(if (invoiceToo) "Kaydet ve Faturala" else "Kaydet (post)", fontWeight = FontWeight.Bold) }
            }
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
                    status = if (r.ok) "TAMAM: PO satırı qty=${res.quantity} (HTTP ${r.httpCode})"
                        else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                    if (r.ok) reload()
                }
            }
        )
    }

    if (showScan) {
        ScanItemSheet(title = "Ürün Tara (PO)", onDismiss = { showScan = false }, onItem = { _, line ->
            showScan = false
            qtyLine = line
        }, lines = lines, matchKey = "itemNo")
    }
    if (showColumns) {
        ChooseColumnsSheet(
            defs = GridColumns.purchaseOrder,
            initial = columns,
            onDismiss = { showColumns = false },
            onSave = { newCols -> columns = newCols; ColumnPrefs.save(context, "purchaseOrder", newCols); showColumns = false },
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
    var item by remember { mutableStateOf("") }
    var hint by remember { mutableStateOf("") }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text(title, fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Spacer(Modifier.height(12.dp))
        ScanField("Ürün No.", item, { item = it }, modifier = Modifier.fillMaxWidth(), onScanned = { raw ->
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
