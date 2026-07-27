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
 * Put-Away — WI §10.2 parity.
 * Lookup -> Put-Away Document -> per-line suggest bin / set bin+qty -> Register.
 * BC: putAways / putAwayLines (warehouse/v2.0), bound actions suggestBin + register.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PutAwayModule() {
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
            val r = BcApi.get(context, "putAways?\$top=100&\$orderby=no desc&\$select=no,locationCode,assignedUserId,status$filter")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Yerleştirme listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "BOŞ: Açık yerleştirme belgesi yok (HTTP ${r.httpCode})"
                else "TAMAM: ${rows.size} belge (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(Unit) { load() }

    var itemDocs by remember { mutableStateOf<Pair<String, Set<String>>?>(null) }
    val sel = selected
    if (sel != null) { PutAwayDocument(no = sel, onBack = { selected = null; load() }); return }

    DocListScanHandler(
        enabled = true,
        linesEndpoint = "putAwayLines",
        documentsEndpoint = "putAways",
        acceptDocTypes = setOf("putaway"),
        onDocument = { selected = it },
    ) { item, docs ->
        when { docs.isEmpty() -> status = "⚠️ '$item' açık yerleştirmede yok"; docs.size == 1 -> selected = docs.first(); else -> { itemDocs = item to docs; status = "TAMAM: '$item' → ${docs.size} belge" } }
    }
    val shownRows = itemDocs?.let { f -> rows.filter { it.optString("no") in f.second } } ?: rows

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        Spacer(Modifier.height(8.dp))
        com.dynops.bcwms.ui.DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() })
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        if (itemDocs != null) { ScanFilterChip("${itemDocs!!.first} → ${itemDocs!!.second.size} belge") { itemDocs = null } }
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(shownRows) { d ->
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(d.optString("no"), fontWeight = FontWeight.Bold)
                            Text(firstValue(d, "status"), fontSize = 12.sp, color = Color.Gray)
                        }
                        Text("Lokasyon: ${firstValue(d, "locationCode")} · 👤 Atanan Kullanıcı: ${firstValue(d, "assignedUserId")}", fontSize = 12.sp, color = Color.Gray)
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Açık yerleştirme belgesi yok.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PutAwayDocument(no: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var binLine by remember { mutableStateOf<JSONObject?>(null) }
    var scanFilter by remember { mutableStateOf("") }
    var showBulkBin by remember { mutableStateOf(false) }
    var showBins by remember { mutableStateOf(false) }
    var stagedLineNos by remember(no) { mutableStateOf<Set<Int>>(emptySet()) }

    fun reload() {
        scope.launch {
            busy = true
            val h = BcApi.get(context, "putAways('$no')")
            if (h.ok) header = JSONObject(h.body)
            val l = BcApi.get(context, "putAwayLines?\$filter=no eq '$no'&\$top=100")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    suspend fun patchPutAwayLine(line: JSONObject, qty: Double, targetBin: String? = null): Boolean {
        val lineNo = line.optInt("lineNo")
        val actType = BcEnum.decodeOData(firstValue(line, "activityType")).ifBlank { BcEnum.WhseActivityType.PUT_AWAY }
        val body = JSONObject().apply {
            put("qtyToHandle", qty)
            if (targetBin != null && isPutAwayPlaceLine(line)) put("binCode", targetBin)
        }.toString()
        val r = BcApi.patch(context, "putAwayLines(activityType='$actType',no='$no',lineNo=$lineNo)", body)
        if (!r.ok) status = QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
        return r.ok
    }

    suspend fun prepareRegisterLines(): Boolean {
        if (stagedLineNos.isEmpty()) {
            status = "HATA: Önce yerleştirilecek satıra miktar/bin girin."
            return false
        }

        val staged = lines.filter { it.optInt("lineNo") in stagedLineNos }
        if (staged.isEmpty()) {
            status = "HATA: Seçilen satırlar artık listede yok. Yenileyip tekrar deneyin."
            return false
        }

        val qtyByPair = mutableMapOf<String, Double>()
        staged.forEach { ln ->
            val qty = ln.optDouble("qtyToHandle", 0.0)
            if (qty > 0) qtyByPair[putAwayPairKey(ln)] = qty
        }
        if (qtyByPair.isEmpty()) {
            status = "HATA: Kaydedilecek pozitif miktar yok."
            return false
        }

        for (ln in lines) {
            val desiredQty = qtyByPair[putAwayPairKey(ln)] ?: 0.0
            val currentQty = ln.optDouble("qtyToHandle", 0.0)
            if (kotlin.math.abs(currentQty - desiredQty) > 0.00001) {
                if (!patchPutAwayLine(ln, desiredQty)) return false
            }
        }
        return true
    }

    fun register() {
        scope.launch {
            busy = true; status = "Kayıt hazırlanıyor..."
            if (!prepareRegisterLines()) {
                busy = false
                return@launch
            }
            status = "Kaydediliyor..."
            val r = BcApi.boundAction(context, "putAways", no, "register", "{}")
            if (!r.ok) {
                busy = false
                status = QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                return@launch
            }
            // Kalan durumunu ANINDA doğru anlat: reload'u bekle, sonra mesaj ver.
            val l = BcApi.get(context, "putAwayLines?\$filter=no eq '$no'&\$top=100")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            val h2 = BcApi.get(context, "putAways('$no')")
            if (h2.ok) header = JSONObject(h2.body)
            busy = false
            stagedLineNos = emptySet()
            val remaining = lines.sumOf { it.optDouble("qtyOutstanding", 0.0) }
            status = when {
                lines.isEmpty() -> "TAMAM: Tüm satırlar yerleştirildi — belge tamamlandı ✅"
                remaining > 0 -> "TAMAM: Kısmi kayıt yapıldı — kalan ${fmtNum(remaining)} adet listede (sarı satırlar)"
                else -> "TAMAM: Yerleştirme kaydedildi (HTTP ${r.httpCode})"
            }
        }
    }

    // Toplu bin: iadelerde/çok satırda tüm satırları tek seferde aynı bine yerleştir.
    fun bulkAssignBin(bin: String) {
        scope.launch {
            busy = true; status = "Tüm satırlar → $bin..."
            var okCount = 0
            for (ln in lines) {
                val qty = ln.optDouble("qtyToHandle", 0.0).takeIf { it > 0 }
                    ?: ln.optDouble("qtyOutstanding", 0.0).takeIf { it > 0 }
                    ?: ln.optDouble("quantity", 0.0)
                if (patchPutAwayLine(ln, qty, bin)) okCount++
            }
            stagedLineNos = lines.map { it.optInt("lineNo") }.toSet()
            busy = false
            status = "TAMAM: $okCount/${lines.size} satır → $bin"
            reload()
        }
    }

    val h = header
    DocumentScanHandler(
        enabled = binLine == null && !showBulkBin,
        lines = lines,
        onSingleMatch = { line, _ -> scanFilter = ""; binLine = line },
        onMultiMatch = { itemNo, _ -> scanFilter = itemNo; status = "TAMAM: '$itemNo' için birden fazla satır — birini seçin" },
        onNoMatch = { r -> status = "⚠️ '${r.itemNo ?: r.value}' bu belgede yok" },
    )
    val displayLines = if (scanFilter.isBlank()) lines else lines.filter { matchLinesByBarcode(listOf(it), com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve(scanFilter)).isNotEmpty() }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Belge Listesi") }
            DocHeaderCard(
                title = no,
                subtitle = "Lokasyon: ${h?.optString("locationCode") ?: ""} · ${firstValue(h ?: JSONObject(), "status")}",
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
            val pairs = groupPutAwayPairs(displayLines)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Yerleştirmeler (${pairs.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { showBins = true }) { Text("📍 Binler", fontSize = 12.sp) }
            }
            Text("Bir yerleştirmeye dokunun → hedef bini ve miktarı onaylayın.", fontSize = 12.sp, color = Color.Gray)
            if (scanFilter.isNotBlank()) { ScanFilterChip(scanFilter) { scanFilter = "" }; Spacer(Modifier.height(4.dp)) }
            Spacer(Modifier.height(8.dp))
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(pairs) { pair -> PutAwayPairCard(pair, staged = pair.place.optInt("lineNo") in stagedLineNos) { binLine = pair.place } }
                if (pairs.isEmpty() && !busy) item { EmptyState("Yerleştirilecek satır yok.") }
            }
        }
        BottomActionBar {
            OutlinedButton(onClick = { showBulkBin = true }, enabled = !busy && lines.isNotEmpty(), modifier = Modifier.weight(1f).height(54.dp)) { Text("📦 Tümünü Bir Bine") }
            val canRegister = stagedLineNos.isNotEmpty()
            Button(
                onClick = { register() },
                enabled = !busy && canRegister,
                modifier = Modifier.weight(1f).height(54.dp),
            ) {
                Text(
                    if (canRegister) "✅ Yerleştirmeyi Kaydet" else "Önce dokunun",
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }

    if (showBulkBin) {
        BulkBinSheet(
            locationCode = h?.optString("locationCode") ?: "",
            lineCount = lines.size,
            onDismiss = { showBulkBin = false },
            onConfirm = { bin -> showBulkBin = false; bulkAssignBin(bin) },
        )
    }
    if (showBins) {
        BinBrowserSheet(
            locationCode = h?.optString("locationCode") ?: "",
            onDismiss = { showBins = false },
            onSelect = null,
        )
    }
    val bl = binLine
    if (bl != null) {
        PutAwayBinSheet(
            line = bl,
            locationCode = h?.optString("locationCode") ?: "",
            onDismiss = { binLine = null },
            onConfirm = { bin, qty ->
                binLine = null
                scope.launch {
                    busy = true; status = "Satır güncelleniyor..."
                    var okCount = 0
                    val affected = putAwayPairLines(bl, lines)
                    for (ln in affected) {
                        if (patchPutAwayLine(ln, qty, bin)) okCount++
                    }
                    busy = false
                    if (okCount == affected.size) {
                        stagedLineNos = stagedLineNos + affected.map { it.optInt("lineNo") }
                        status = "TAMAM: ${affected.size} satır hazırlandı → $bin"
                        reload()
                    }
                }
            }
        )
    }
}

private fun putAwayAction(line: JSONObject): String =
    BcEnum.decodeOData(firstValue(line, "actionType")).lowercase()

private fun isPutAwayPlaceLine(line: JSONObject): Boolean {
    val action = putAwayAction(line)
    return action.isBlank() || action.contains("place")
}

private fun putAwayPairKey(line: JSONObject): String {
    val sourceNo = firstValue(line, "sourceNo", "whseDocumentNo")
    val sourceLineNo = firstValue(line, "sourceLineNo", "whseDocumentLineNo")
    val whseDocNo = firstValue(line, "whseDocumentNo")
    val whseDocLineNo = firstValue(line, "whseDocumentLineNo")
    return listOf(
        sourceNo,
        sourceLineNo,
        whseDocNo,
        whseDocLineNo,
        firstValue(line, "itemNo"),
        firstValue(line, "variantCode"),
        firstValue(line, "unitOfMeasureCode"),
    ).joinToString("|")
}

private fun putAwayPairLines(seed: JSONObject, lines: List<JSONObject>): List<JSONObject> {
    val key = putAwayPairKey(seed)
    val matched = lines.filter { putAwayPairKey(it) == key }
    return matched.ifEmpty { listOf(seed) }
}

/**
 * Bir yerleştirme hareketi = BC'nin Take (kaynak bin'den al) + Place (hedef bin'e koy)
 * satır çifti. Operatör için tek bir "nereden → nereye" işlemi olduğundan, ekranda da
 * tek kartta gösterilir. [place] her zaman miktar+bin girilecek satırdır.
 */
private data class PutAwayPair(
    val take: JSONObject?,
    val place: JSONObject,
    val itemNo: String,
    val description: String,
)

private fun groupPutAwayPairs(lines: List<JSONObject>): List<PutAwayPair> {
    val byKey = LinkedHashMap<String, MutableList<JSONObject>>()
    for (ln in lines) byKey.getOrPut(putAwayPairKey(ln)) { mutableListOf() }.add(ln)
    return byKey.values.map { group ->
        val place = group.firstOrNull { isPutAwayPlaceLine(it) } ?: group.first()
        val take = group.firstOrNull { !isPutAwayPlaceLine(it) }
        PutAwayPair(take, place, place.optString("itemNo"), place.optString("description"))
    }
}

/** Take/Place çiftini "nereden → nereye" tek kart olarak gösteren, tıklanabilir satır. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PutAwayPairCard(pair: PutAwayPair, staged: Boolean, onClick: () -> Unit) {
    val place = pair.place
    val done = staged || lineDone(place, LineModule.PUTAWAY)
    val sourceBin = pair.take?.optString("binCode")?.ifBlank { null } ?: "-"
    val targetBin = place.optString("binCode").ifBlank { "" }
    val toHandle = place.optDouble("qtyToHandle", 0.0)
    val outstanding = place.optDouble("qtyOutstanding", place.optDouble("quantity", 0.0))
    val uom = firstValue(place, "unitOfMeasureCode")

    Card(onClick = onClick, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp), colors = doneCardColors(done)) {
        Column(Modifier.padding(14.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("${donePrefix(done)}${pair.itemNo}${if (pair.description.isNotBlank()) " — ${pair.description}" else ""}", fontWeight = FontWeight.SemiBold, fontSize = 15.sp, modifier = Modifier.weight(1f))
                Surface(shape = RoundedCornerShape(50), color = if (done) Color(0xFF16A34A).copy(alpha = 0.16f) else Color(0xFFEA580C).copy(alpha = 0.14f)) {
                    Text(if (done) "✓ Hazır" else "Dokunun", Modifier.padding(horizontal = 10.dp, vertical = 4.dp), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = if (done) Color(0xFF15803D) else Color(0xFFC2410C))
                }
            }
            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                BinPill("📤 Al", sourceBin, Color(0xFF64748B))
                Text("  →  ", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color(0xFF6366F1))
                BinPill("📥 Koy", targetBin.ifBlank { "Bin seç" }, if (targetBin.isBlank()) Color(0xFFEA580C) else Color(0xFF16A34A))
                Spacer(Modifier.weight(1f))
                Text("›", fontSize = 26.sp, color = Color.Gray)
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "Miktar: ${fmtNum(if (toHandle > 0) toHandle else outstanding)} · Kalan: ${fmtNum(outstanding)} $uom".trim(),
                fontSize = 12.sp, color = Color.Gray,
            )
        }
    }
}

@Composable
private fun BinPill(label: String, bin: String, accent: Color) {
    Column {
        Text(label, fontSize = 10.sp, color = Color.Gray)
        Surface(shape = RoundedCornerShape(8.dp), color = accent.copy(alpha = 0.12f)) {
            Text(bin, Modifier.padding(horizontal = 10.dp, vertical = 5.dp), fontSize = 15.sp, fontWeight = FontWeight.Bold, color = accent)
        }
    }
}

private fun odataLiteral(value: String): String = value.replace("'", "''")

/** Bottom sheet: scan/enter target bin (with "Öner" = suggestBin) + qty. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PutAwayBinSheet(line: JSONObject, locationCode: String, onDismiss: () -> Unit, onConfirm: (bin: String, qty: Double) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var bin by remember { mutableStateOf(line.optString("binCode")) }
    var showBinList by remember { mutableStateOf(false) }
    // Öndeğer = KALAN miktar (kısmi register'dan sonra kaldığı yerden devam).
    val outstanding = line.optDouble("qtyOutstanding", Double.NaN)
    val handled = line.optDouble("qtyHandled", 0.0)
    val prefill = when {
        !outstanding.isNaN() && outstanding > 0 -> outstanding
        line.optDouble("qtyToHandle", 0.0) > 0 -> line.optDouble("qtyToHandle", 0.0)
        else -> line.optDouble("quantity", 0.0)
    }
    var qty by remember { mutableStateOf(prefill.let { if (it == it.toLong().toDouble()) it.toLong().toString() else it.toString() }) }
    var hint by remember { mutableStateOf("") }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        if (showBinList) {
            TextButton(onClick = { showBinList = false }) { Text("‹ Hedef Bin") }
            BinListContent(
                locationCode = locationCode,
                onSelect = {
                    bin = it
                    showBinList = false
                },
            )
        } else {
            Text("Hedef Bin", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Text(
                buildString {
                    append("Ürün: ${line.optString("itemNo")}")
                    if (!outstanding.isNaN()) append(" · Kalan: ${fmtNum(outstanding)}")
                    if (handled > 0) append(" · Konan: ${fmtNum(handled)}")
                },
                fontSize = 12.sp, color = Color.Gray
            )
            if (!outstanding.isNaN() && (handled > 0 || outstanding > 0)) {
                Text(
                    "Kısmi miktar girebilirsiniz — kalan, kayıt sonrası listede sarı satır olarak devam eder.",
                    fontSize = 11.sp, color = Color.Gray
                )
            }
            Spacer(Modifier.height(12.dp))
            ScanField("Bin", bin, { bin = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
                bin = BarcodeIntentResolver.resolve(it).value
            })
            Spacer(Modifier.height(6.dp))
            OutlinedButton(onClick = {
                scope.launch {
                    hint = "Bin öneriliyor..."
                    val body = JSONObject().apply {
                        put("itemNo", line.optString("itemNo"))
                        put("qty", qty.toDoubleOrNull() ?: 0.0)
                        put("locationCode", locationCode)
                    }.toString()
                    // suggestBin is bound to a record; call on the line's parent put-away header is not
                    // possible, so target the entity set generically with the line key context.
                    val r = BcApi.post(context, "putAways('${line.optString("no")}')/Microsoft.NAV.suggestBin", body)
                    hint = if (r.ok) {
                        val suggested = BcApi.scalarValue(r.body)
                        if (suggested.isNotBlank()) { bin = suggested; "Önerilen bin: $suggested" } else "Öneri boş döndü"
                    } else "Öneri alınamadı (HTTP ${r.httpCode})"
                }
            }) { Text("🎯 Bin Öner") }
            Spacer(Modifier.height(6.dp))
            OutlinedButton(onClick = { showBinList = true }, modifier = Modifier.fillMaxWidth()) { Text("📍 Bin Listesinden Seç") }
            if (hint.isNotBlank()) { Spacer(Modifier.height(4.dp)); Text(hint, fontSize = 12.sp, color = Color.Gray) }
            Spacer(Modifier.height(10.dp))
            OutlinedTextField(qty, { qty = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Miktar") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(16.dp))
            Button(enabled = bin.isNotBlank(), modifier = Modifier.fillMaxWidth(), onClick = {
                onConfirm(bin.trim(), qty.toDoubleOrNull() ?: 0.0)
            }) { Text("Onayla") }
            Spacer(Modifier.height(24.dp))
        }
    }
}

/** Toplu bin sheet: bir bin okut/gir → belgedeki tüm satırlara uygula. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BulkBinSheet(locationCode: String, lineCount: Int, onDismiss: () -> Unit, onConfirm: (bin: String) -> Unit) {
    var bin by remember { mutableStateOf("") }
    var showBinList by remember { mutableStateOf(false) }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        if (showBinList) {
            TextButton(onClick = { showBinList = false }) { Text("‹ Toplu Bin") }
            BinListContent(
                locationCode = locationCode,
                onSelect = {
                    bin = it
                    showBinList = false
                },
            )
        } else {
        Text("Tümünü Bir Bine Yerleştir", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text("$lineCount satırın hepsi seçilen bine atanır.", fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(12.dp))
        ScanField("Hedef Bin", bin, { bin = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            bin = BarcodeIntentResolver.resolve(it).value
        })
        Spacer(Modifier.height(8.dp))
        OutlinedButton(onClick = { showBinList = true }, modifier = Modifier.fillMaxWidth()) { Text("📍 Bin Listesinden Seç") }
        Spacer(Modifier.height(16.dp))
        Button(enabled = bin.isNotBlank(), modifier = Modifier.fillMaxWidth(), onClick = { onConfirm(bin.trim()) }) {
            Text("Tümüne Uygula ($lineCount)")
        }
        Spacer(Modifier.height(24.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BinBrowserSheet(locationCode: String, onDismiss: () -> Unit, onSelect: ((String) -> Unit)?) {
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text("Binler", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text("Lokasyon: ${locationCode.ifBlank { "-" }}", fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(12.dp))
        BinListContent(locationCode = locationCode, onSelect = onSelect)
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun BinListContent(locationCode: String, onSelect: ((String) -> Unit)?) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var bins by remember(locationCode) { mutableStateOf<List<JSONObject>>(emptyList()) }
    var loading by remember(locationCode) { mutableStateOf(false) }
    var status by remember(locationCode) { mutableStateOf("") }
    var search by remember { mutableStateOf("") }

    fun loadBins() {
        scope.launch {
            loading = true
            val filter = if (locationCode.isNotBlank()) "?\$filter=locationCode eq '${odataLiteral(locationCode)}'&\$orderby=code&\$top=200" else "?\$orderby=code&\$top=200"
            val r = BcApi.get(context, "bins$filter")
            bins = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (r.ok) "TAMAM: ${bins.size} bin" else "HATA: Bin listesi alınamadı (HTTP ${r.httpCode})"
            loading = false
        }
    }

    LaunchedEffect(locationCode) { loadBins() }
    OutlinedTextField(
        value = search,
        onValueChange = { search = it },
        label = { Text("Bin ara") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(6.dp))
    StatusText(if (loading) "Binler yükleniyor..." else status)
    Spacer(Modifier.height(8.dp))
    val shown = bins.filter {
        val q = search.trim()
        q.isBlank() ||
            it.optString("code").contains(q, ignoreCase = true) ||
            it.optString("description").contains(q, ignoreCase = true) ||
            it.optString("zoneCode").contains(q, ignoreCase = true) ||
            it.optString("warehouseClassCode").contains(q, ignoreCase = true)
    }
    LazyColumn(Modifier.heightIn(max = 360.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        items(shown) { b ->
            val code = b.optString("code")
            val block = b.optString("blockMovement")
            val blocked = block.equals("All", true) || block.equals("Inbound", true)
            Card(
                onClick = { if (!blocked) onSelect?.invoke(code) },
                enabled = !blocked,
                colors = CardDefaults.cardColors(
                    containerColor = if (blocked) MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.35f) else MaterialTheme.colorScheme.surfaceVariant,
                ),
            ) {
                Column(Modifier.fillMaxWidth().padding(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(code, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        val cls = b.optString("warehouseClassCode").ifBlank { "Sınıf yok" }
                        Text(cls, fontSize = 12.sp, color = if (cls == "Sınıf yok") Color.Gray else MaterialTheme.colorScheme.primary)
                    }
                    Text(
                        listOf(
                            b.optString("description"),
                            "Zone ${b.optString("zoneCode").ifBlank { "-" }}",
                            "Tip ${b.optString("binTypeCode").ifBlank { "-" }}",
                            "Rank ${b.optInt("binRanking", 0)}",
                            if (block.isBlank() || block == " ") "Blok yok" else "Blok $block",
                        ).filter { it.isNotBlank() }.joinToString(" · "),
                        fontSize = 12.sp,
                        color = Color.Gray,
                    )
                }
            }
        }
        if (shown.isEmpty() && !loading) item { EmptyState("Uygun bin bulunamadı.") }
    }
}

/** Tote (yeniden kullanılabilir LP) okutma sheet'i — pick'te topla / sevke bağla. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ToteScanSheet(title: String, hint: String, onDismiss: () -> Unit, onScanned: (String) -> Unit) {
    var lp by remember { mutableStateOf("") }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text(title, fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text(hint, fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(12.dp))
        ScanField("Tote / LP", lp, { lp = it }, modifier = Modifier.fillMaxWidth(), onScanned = { lp = BarcodeIntentResolver.resolve(it).value })
        Spacer(Modifier.height(16.dp))
        Button(enabled = lp.isNotBlank(), modifier = Modifier.fillMaxWidth().height(50.dp), onClick = { onScanned(lp.trim()) }) { Text("Onayla") }
        Spacer(Modifier.height(24.dp))
    }
}

/**
 * Sevkiyat (Shipping). 2 sekme:
 *  - "Whse Shipment": Pick'lenmiş, Released Warehouse Shipment'lardan post
 *  - "Sales Order": yönetilmeyen lokasyonda doğrudan SO satırı sevk + post
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShippingModule() {
    val context = LocalContext.current
    // Sipariş bazlı (Sales Order) sekmesi Setup'tan opsiyonel (varsayılan açık).
    var showSo by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        val r = BcApi.get(context, "movementOps('')?\$select=showSoShipment")
        if (r.ok) runCatching { showSo = JSONObject(r.body).optBoolean("showSoShipment", true) }
    }
    var tab by remember { mutableStateOf(0) }
    var requestedPickNo by remember { mutableStateOf(com.dynops.bcwms.WhsePickNavigation.consume()) }
    val tabs = if (showSo) listOf("📦 Ambar Toplama", "📋 Ambar Sevkiyatı", "🛒 Satış Siparişi") else listOf("📦 Ambar Toplama", "📋 Ambar Sevkiyatı")
    if (tab >= tabs.size) tab = 0

    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab) {
            tabs.forEachIndexed { i, title ->
                Tab(selected = tab == i, onClick = { tab = i }, text = { Text(title, fontSize = 13.sp) })
            }
        }
        when (tab) {
            0 -> WhsePickTab(initialPickNo = requestedPickNo, onInitialPickConsumed = { requestedPickNo = null })
            1 -> WhseShipmentTab(onPickCreated = { pickNo -> requestedPickNo = pickNo; tab = 0 })
            2 -> SalesOrderTab()
        }
    }
}

// ============================================================
// Tab 1: Warehouse Pick (sevkiyat öncesi ambar çekmeleri)
// ============================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WhsePickTab(initialPickNo: String? = null, onInitialPickConsumed: () -> Unit = {}) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selected by remember { mutableStateOf<String?>(null) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var showAll by remember { mutableStateOf(true) }
    var search by remember { mutableStateOf("") }

    LaunchedEffect(initialPickNo) {
        if (!initialPickNo.isNullOrBlank()) {
            selected = initialPickNo
            onInitialPickConsumed()
        }
    }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val myUser = if (showAll) "" else BcApi.currentUserId(context)
            val filter = buildODataFilter(
                assignedToMeClause(myUser, enabled = !showAll),
                searchClause("no", search),
            )
            val r = BcApi.getWithStandardFallback(context, "picks?\$top=100&\$orderby=no desc&\$select=no,locationCode,assignedUserId,sourceNo,status,percentComplete$filter")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Ambar çekme listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "BOŞ: Açık ambar çekme yok (HTTP ${r.httpCode})"
                else "TAMAM: ${rows.size} ambar çekme (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(showAll) { load() }

    var itemDocs by remember { mutableStateOf<Pair<String, Set<String>>?>(null) }
    val sel = selected
    if (sel != null) { WhsePickDocument(no = sel, onBack = { selected = null; load() }); return }

    DocListScanHandler(
        enabled = true,
        linesEndpoint = "pickLines",
        documentsEndpoint = "picks",
        acceptDocTypes = setOf("pick"),
        onDocument = { selected = it },
    ) { item, docs ->
        when {
            docs.isEmpty() -> status = "⚠️ '$item' açık ambar çekmede yok"
            docs.size == 1 -> selected = docs.first()
            else -> { itemDocs = item to docs; status = "TAMAM: '$item' → ${docs.size} ambar çekme" }
        }
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
        com.dynops.bcwms.ui.DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() }, label = "Pick no ile ara")
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        if (itemDocs != null) { ScanFilterChip("${itemDocs!!.first} → ${itemDocs!!.second.size} belge") { itemDocs = null } }
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(shownRows) { d ->
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(d.optString("no"), fontWeight = FontWeight.Bold)
                            Text(bcStatusLabelTr(d.optString("status")), fontSize = 12.sp, color = Color.Gray)
                        }
                        Text("Lokasyon: ${firstValue(d, "locationCode")} · Kaynak: ${firstValue(d, "sourceNo")} · 👤 Atanan Kullanıcı: ${firstValue(d, "assignedUserId")}", fontSize = 12.sp, color = Color.Gray)
                        val pct = d.optInt("percentComplete")
                        LinearProgressIndicator(progress = { pct / 100f }, modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Açık ambar çekme yok.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WhsePickDocument(no: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var qtyLine by remember { mutableStateOf<JSONObject?>(null) }
    var scanFilter by remember { mutableStateOf("") }
    var sortByBin by remember { mutableStateOf(true) }
    // v2: Lot No. varsayılan olarak Item No.'nun yanında görünür.
    var columns by remember { mutableStateOf(ColumnPrefs.get(context, "shippingPickLotV2", GridColumns.pick)) }
    var showColumns by remember { mutableStateOf(false) }
    // ELOG müşteri isteği: bin+item aynı olan satırları tek satırda göster,
    // girilen miktarı alt satırlara dağıt (bkz. LineGrouping/LineGroupCards).
    var merge by remember { mutableStateOf(false) }
    var groupTarget by remember { mutableStateOf<LineGroup?>(null) }
    // ELOG raf modu: raf (bin) barkodu okutulunca liste o rafın satırlarına iner.
    var binFilter by remember { mutableStateOf("") }

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

    fun action(name: String, body: String, okMsg: String) {
        scope.launch {
            busy = true; status = "$name..."
            val r = BcApi.boundAction(context, "picks", no, name, body)
            busy = false
            status = if (r.ok) "TAMAM: $okMsg (HTTP ${r.httpCode})" else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
            if (r.ok) reload()
        }
    }

    fun updateLine(line: JSONObject, qty: Double, lotNo: String) {
        scope.launch {
            busy = true; status = "Satır güncelleniyor..."
            val actType = BcEnum.decodeOData(line.optString("activityType")).ifBlank { BcEnum.WhseActivityType.PICK }
            val body = JSONObject().apply {
                put("qtyToHandle", qty)
                put("lotNo", lotNo)
            }.toString()
            val r = BcApi.patch(context, "pickLines(activityType='$actType',no='$no',lineNo=${line.optInt("lineNo")})", body)
            busy = false
            status = if (r.ok) "TAMAM: Satır güncellendi (HTTP ${r.httpCode})" else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
            if (r.ok) reload()
        }
    }

    val h = header
    val takeLines = lines.filter { !BcEnum.decodeOData(it.optString("actionType")).equals("Place", ignoreCase = true) }
    DocumentScanHandler(
        enabled = qtyLine == null && groupTarget == null && !busy,
        lines = takeLines,
        onSingleMatch = { line, _ ->
            scanFilter = ""
            val g = if (merge) groupLines(takeLines, ::pickLineCapacity)
                .firstOrNull { grp -> grp.lines.any { it.optInt("lineNo") == line.optInt("lineNo") } } else null
            if (g != null && g.count > 1) groupTarget = g else qtyLine = line
        },
        onMultiMatch = { itemNo, _ -> scanFilter = itemNo; status = "TAMAM: '$itemNo' için birden fazla satır — birini seçin" },
        onNoMatch = { r ->
            val scanned = r.value.trim()
            val bin = takeLines.firstOrNull { it.optString("binCode").equals(scanned, ignoreCase = true) }?.optString("binCode")
            if (!bin.isNullOrBlank()) {
                binFilter = bin
                status = "📍 Raf $bin — bu raftan alınacak satırlar"
            } else status = "⚠️ '${r.itemNo ?: r.value}' bu ambar çekmede yok"
        },
    )
    val binLines = if (binFilter.isBlank()) takeLines else takeLines.filter { it.optString("binCode").equals(binFilter, ignoreCase = true) }
    val filteredLines = if (scanFilter.isBlank()) binLines else binLines.filter { matchLinesByBarcode(listOf(it), com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve(scanFilter)).isNotEmpty() }
    val displayLines = if (sortByBin) filteredLines.sortedBy { it.optString("binCode") } else filteredLines
    val displayGroups = if (merge) groupLines(displayLines, ::pickLineCapacity) else emptyList()

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Belge Listesi") }
            DocHeaderCard(
                title = no,
                subtitle = "Lokasyon: ${h?.optString("locationCode") ?: ""} · ${bcStatusLabelTr(h?.optString("status") ?: "")}",
                percent = h?.optDouble("percentComplete")?.toInt() ?: 0,
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
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (merge) "Gruplar (${displayGroups.size})" else "Satırlar (${displayLines.size}/${takeLines.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.weight(1f))
                FilterChip(selected = merge, onClick = { merge = !merge }, label = { Text("🔗 Birleştir", fontSize = 12.sp) })
                FilterChip(selected = sortByBin, onClick = { sortByBin = !sortByBin }, label = { Text("🧭 Bin", fontSize = 12.sp) })
                if (!merge) { TextButton(onClick = { showColumns = true }) { Text("⚙ Kolonlar", fontSize = 12.sp) } }
            }
            if (binFilter.isNotBlank()) { ScanFilterChip("📍 Raf $binFilter") { binFilter = "" }; Spacer(Modifier.height(4.dp)) }
            if (scanFilter.isNotBlank()) { ScanFilterChip(scanFilter) { scanFilter = "" }; Spacer(Modifier.height(4.dp)) }
            if (merge) {
                LineGroupCards(
                    groups = displayGroups,
                    staged = { it.optDouble("qtyToHandle", 0.0) },
                    modifier = Modifier.weight(1f),
                    onGroupClick = { if (!busy) groupTarget = it },
                )
            } else {
                LineGrid(
                    defs = GridColumns.pick,
                    columns = columns,
                    rows = displayLines,
                    modifier = Modifier.weight(1f),
                    isDone = { lineDone(it, LineModule.PICK) },
                    isPartial = { linePartial(it, LineModule.PICK) },
                    onRowClick = { qtyLine = it },
                )
            }
        }
        BottomActionBar {
            OutlinedButton(onClick = { action("assignToMe", "{}", "Bana atandı") }, enabled = !busy, modifier = Modifier.weight(1f).height(54.dp)) {
                Text("Bana Ata")
            }
            val canRegister = com.dynops.bcwms.lib.ActionGuards.hasQuantity(lines)
            Button(onClick = { action("register", "{}", "Ambar çekme kaydedildi") }, enabled = !busy && canRegister, modifier = Modifier.weight(1f).height(54.dp)) {
                Text(if (canRegister) "✅ Toplamayı Kaydet" else "Miktar girin", fontWeight = FontWeight.Bold)
            }
        }
    }

    val ql = qtyLine
    if (ql != null) {
        QuantityDialogSheet(
            title = "Çekme Miktarı",
            itemNo = ql.optString("itemNo"),
            initialQty = ql.optDouble("qtyOutstanding").takeIf { it > 0 } ?: ql.optDouble("quantity").takeIf { it > 0 } ?: 1.0,
            initialUom = ql.optString("unitOfMeasureCode"),
            initialLot = ql.optString("lotNo"),
            showLotSerial = true,
            showSerial = false,
            onDismiss = { qtyLine = null },
            onConfirm = { res ->
                qtyLine = null
                updateLine(ql, res.quantity, res.lotNo)
            },
        )
    }
    val gt = groupTarget
    if (gt != null) {
        QuantityDialogSheet(
            title = "Çekme Miktarı (${gt.count} satıra dağıtılır)",
            itemNo = gt.itemNo,
            initialQty = gt.totalOutstanding.takeIf { it > 0 } ?: 1.0,
            initialUom = gt.lines.first().optString("unitOfMeasureCode"),
            initialLot = gt.lines.first().optString("lotNo"),
            showLotSerial = true,
            showSerial = false,
            onDismiss = { groupTarget = null },
            onConfirm = { res ->
                groupTarget = null
                scope.launch {
                    busy = true; status = "Grup dağıtılıyor..."
                    val plan = distributeQty(gt, res.quantity, ::pickLineCapacity)
                    var okCount = 0
                    var firstErr: String? = null
                    for ((ln, q) in plan) {
                        val actType = BcEnum.decodeOData(ln.optString("activityType")).ifBlank { BcEnum.WhseActivityType.PICK }
                        val body = JSONObject().apply {
                            put("qtyToHandle", q)
                            put("lotNo", res.lotNo)
                        }.toString()
                        val r = BcApi.patch(context, "pickLines(activityType='$actType',no='$no',lineNo=${ln.optInt("lineNo")})", body)
                        if (r.ok) okCount++ else if (firstErr == null) firstErr = BcApi.errorMessage(r.body)
                    }
                    busy = false
                    status = if (firstErr == null) "TAMAM: $okCount/${plan.size} satıra dağıtıldı"
                        else "HATA: $okCount/${plan.size} satır yazıldı — $firstErr"
                    reload()
                }
            },
        )
    }
    if (showColumns) {
        ChooseColumnsSheet(GridColumns.pick, columns, onDismiss = { showColumns = false }) { c -> columns = c; ColumnPrefs.save(context, "shippingPickLotV2", c); showColumns = false }
    }
}

// ============================================================
// Tab 2: Warehouse Shipment (orijinal akış)
// ============================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WhseShipmentTab(onPickCreated: (String) -> Unit) {
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
            val filter = com.dynops.bcwms.ui.buildODataFilter(
                assignedToMeClause(myUser, enabled = !showAll),
                com.dynops.bcwms.ui.searchClause("no", search),
            )
            val r = BcApi.get(context, "shipments?\$top=100&\$orderby=shipmentDate desc&\$select=no,locationCode,assignedUserId,status,shipmentDate,sourceNo,shipTo,lineCount$filter")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Sevkiyat listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) (if (showAll) "BOŞ: Serbest bırakılmış Ambar Sevkiyatı yok (HTTP ${r.httpCode})" else "BOŞ: Size atanmış sevkiyat yok (HTTP ${r.httpCode})")
                else "TAMAM: ${rows.size} belge (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(showAll) { load() }

    var itemDocs by remember { mutableStateOf<Pair<String, Set<String>>?>(null) }
    val sel = selected
    if (sel != null) { ShipDocument(no = sel, onBack = { selected = null; load() }, onPickCreated = onPickCreated); return }

    DocListScanHandler(
        enabled = true,
        linesEndpoint = "shipmentLines",
        documentsEndpoint = "shipments",
        acceptDocTypes = setOf("shipment"),
        onDocument = { selected = it },
    ) { item, docs ->
        when { docs.isEmpty() -> status = "⚠️ '$item' açık sevkiyatta yok"; docs.size == 1 -> selected = docs.first(); else -> { itemDocs = item to docs; status = "TAMAM: '$item' → ${docs.size} belge" } }
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
        com.dynops.bcwms.ui.DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() })
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        if (itemDocs != null) { ScanFilterChip("${itemDocs!!.first} → ${itemDocs!!.second.size} belge") { itemDocs = null } }
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(shownRows) { d ->
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(d.optString("no"), fontWeight = FontWeight.Bold)
                            Text(firstValue(d, "status"), fontSize = 12.sp, color = Color.Gray)
                        }
                        Text("Sevk: ${firstValue(d, "shipTo")} · Kaynak: ${firstValue(d, "sourceNo")} · 👤 Atanan Kullanıcı: ${firstValue(d, "assignedUserId")}", fontSize = 12.sp, color = Color.Gray)
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState(if (showAll) "Serbest bırakılmış Ambar Sevkiyatı yok. Siparişten direkt sevkiyat için sağdaki sekmeyi kullanın." else "Size atanmış sevkiyat yok. Tümünü görmek için \"Tümü\" seçin.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ShipDocument(no: String, onBack: () -> Unit, onPickCreated: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var printSlip by remember { mutableStateOf(true) }
    var invoice by remember { mutableStateOf(false) }
    var qtyLine by remember { mutableStateOf<JSONObject?>(null) }
    var scanFilter by remember { mutableStateOf("") }
    var columns by remember { mutableStateOf(ColumnPrefs.get(context, "shipment", GridColumns.shipment)) }
    var showColumns by remember { mutableStateOf(false) }

    fun reload() {
        scope.launch {
            busy = true
            val h = BcApi.get(context, "shipments('$no')")
            if (h.ok) header = JSONObject(h.body)
            val l = BcApi.get(context, "shipmentLines?\$filter=no eq '$no'&\$top=100")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    val h = header
    DocumentScanHandler(
        enabled = qtyLine == null,
        lines = lines,
        onSingleMatch = { line, _ -> scanFilter = ""; qtyLine = line },
        onMultiMatch = { itemNo, _ -> scanFilter = itemNo; status = "TAMAM: '$itemNo' için birden fazla satır — birini seçin" },
        onNoMatch = { r -> status = "⚠️ '${r.itemNo ?: r.value}' bu belgede yok" },
    )
    val displayLines = if (scanFilter.isBlank()) lines else lines.filter { matchLinesByBarcode(listOf(it), com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve(scanFilter)).isNotEmpty() }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Belge Listesi") }
            DocHeaderCard(
                title = no,
                subtitle = "Sevk: ${firstValue(h ?: JSONObject(), "shipTo")} · ${firstValue(h ?: JSONObject(), "status")} · 👤 Atanan Kullanıcı: ${firstValue(h ?: JSONObject(), "assignedUserId").ifBlank { "-" }}",
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
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Satırlar (${displayLines.size}/${lines.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { showColumns = true }) { Text("⚙ Kolonlar", fontSize = 12.sp) }
            }
            if (scanFilter.isNotBlank()) { ScanFilterChip(scanFilter) { scanFilter = "" }; Spacer(Modifier.height(4.dp)) }
            LineGrid(
                defs = GridColumns.shipment, columns = columns, rows = displayLines,
                modifier = Modifier.weight(1f),
                isDone = { lineDone(it, LineModule.SHIPMENT) },
                onRowClick = { qtyLine = it },
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = printSlip, onCheckedChange = { printSlip = it })
                Text("İrsaliye yazdır", fontSize = 13.sp)
                Spacer(Modifier.width(12.dp))
                Checkbox(checked = invoice, onCheckedChange = { invoice = it })
                Text("Faturalandır", fontSize = 13.sp)
            }
        }
        BottomActionBar {
            OutlinedButton(
                onClick = {
                    scope.launch {
                        busy = true; status = "Ambar Toplama oluşturuluyor..."
                        val r = BcApi.boundAction(context, "shipments", no, "createPick", "{}")
                        val pickNo = if (r.ok) BcApi.scalarValue(r.body) else ""
                        busy = false
                        if (r.ok && pickNo.isNotBlank()) {
                            status = "TAMAM: Ambar Toplama $pickNo oluşturuldu"
                            onPickCreated(pickNo)
                        } else {
                            status = if (r.ok) "HATA: Pick numarası alınamadı"
                                else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                        }
                    }
                },
                enabled = !busy && lines.isNotEmpty(),
                modifier = Modifier.weight(1f).height(54.dp),
            ) {
                Text("📦 Pick Oluştur", fontWeight = FontWeight.Bold)
            }
            Button(
                onClick = {
                    scope.launch {
                        busy = true; status = "Sevk kaydı..."
                        val body = JSONObject().apply { put("print", printSlip); put("invoice", invoice) }.toString()
                        val r = BcApi.boundAction(context, "shipments", no, "post", body)
                        busy = false
                        status = if (r.ok) "TAMAM: Sevkiyat kaydedildi (HTTP ${r.httpCode})" else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                        if (r.ok) reload()
                    }
                },
                enabled = !busy && com.dynops.bcwms.lib.ActionGuards.hasQuantity(lines, field = "qtyToShip"),
                modifier = Modifier.weight(1f).height(54.dp),
            ) {
                Text(
                    if (com.dynops.bcwms.lib.ActionGuards.hasQuantity(lines, field = "qtyToShip")) "✅ Sevkiyatı Kaydet" else "Önce satırlara miktar girin",
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }

    val ql = qtyLine
    if (ql != null) {
        QuantityDialogSheet(
            title = "Sevk Miktarı + Lot",
            itemNo = ql.optString("itemNo"),
            initialQty = ql.optDouble("qtyOutstanding").takeIf { it > 0 } ?: 1.0,
            initialUom = ql.optString("uomCode"),
            initialLot = ql.optString("lotNo"),
            showLotSerial = true,
            showSerial = false,
            onDismiss = { qtyLine = null },
            onConfirm = { res ->
                qtyLine = null
                scope.launch {
                    busy = true; status = "Satır güncelleniyor..."
                    val body = JSONObject().apply {
                        put("qtyToShip", res.quantity)
                        put("lotNo", res.lotNo)
                        val lineBin = firstValue(ql, "binCode")
                        if (lineBin.isNotBlank()) put("binCode", lineBin)
                    }.toString()
                    val lineNo = ql.optInt("lineNo")
                    val r = BcApi.patch(context, "shipmentLines(no='$no',lineNo=$lineNo)", body)
                    busy = false
                    status = if (r.ok) "TAMAM: Satır güncellendi (HTTP ${r.httpCode})" else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                    if (r.ok) reload()
                }
            }
        )
    }
    if (showColumns) {
        ChooseColumnsSheet(GridColumns.shipment, columns, onDismiss = { showColumns = false }) { c -> columns = c; ColumnPrefs.save(context, "shipment", c); showColumns = false }
    }
}

// ============================================================
// Tab 2: Sales Order direct ship
// ============================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SalesOrderTab() {
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
            val filter = com.dynops.bcwms.ui.buildODataFilter(
                "status eq 'Released'".takeIf { releasedOnly },
                com.dynops.bcwms.ui.searchClause("no", search),
            )
            val r = BcApi.get(
                context,
                "salesSources?\$top=100&\$orderby=shipmentDate desc$filter&\$select=no,customerNo,customerName,shipToName,locationCode,shipmentDate,status,lineCount,outstandingQty,percentComplete,requiresWhseShipment,directShipAllowed"
            )
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: SO listesi alınamadı (HTTP ${r.httpCode}) — ${BcApi.errorMessage(r.body).take(120)}"
                else if (rows.isEmpty()) "BOŞ: ${if (releasedOnly) "Released" else "Açık"} SO yok (HTTP ${r.httpCode})"
                else "TAMAM: ${rows.size} satış siparişi (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(releasedOnly) { load() }

    var itemDocs by remember { mutableStateOf<Pair<String, Set<String>>?>(null) }
    val sel = selected
    if (sel != null) { ShipSalesOrder(no = sel, onBack = { selected = null; load() }); return }

    DocListScanHandler(
        enabled = true,
        linesEndpoint = "salesSourceLines",
        documentsEndpoint = "salesSources",
        acceptDocTypes = setOf("salesOrder"),
        onDocument = { selected = it },
    ) { item, docs ->
        when { docs.isEmpty() -> status = "⚠️ '$item' açık SO'da yok"; docs.size == 1 -> selected = docs.first(); else -> { itemDocs = item to docs; status = "TAMAM: '$item' → ${docs.size} SO" } }
    }
    val shownRows = itemDocs?.let { f -> rows.filter { it.optString("no") in f.second } } ?: rows

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
        com.dynops.bcwms.ui.DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() }, label = "SO no ile ara")
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        if (itemDocs != null) { ScanFilterChip("${itemDocs!!.first} → ${itemDocs!!.second.size} SO") { itemDocs = null } }
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(shownRows) { d ->
                val requiresWhse = d.optBoolean("requiresWhseShipment", false)
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(d.optString("no"), fontWeight = FontWeight.Bold)
                            Row {
                                if (requiresWhse) Text("⚠ Ambar Sevk", fontSize = 11.sp, color = Color(0xFFD97706), modifier = Modifier.padding(end = 6.dp))
                                Text(firstValue(d, "status"), fontSize = 12.sp, color = Color.Gray)
                            }
                        }
                        Text("Müşteri: ${firstValue(d, "customerName")} (${firstValue(d, "customerNo")})", fontSize = 12.sp, color = Color.Gray)
                        val st = firstValue(d, "shipToName")
                        if (st.isNotBlank() && st != firstValue(d, "customerName")) {
                            Text("Sevk: $st", fontSize = 12.sp, color = Color.Gray)
                        }
                        Text("Lokasyon: ${firstValue(d, "locationCode")} · Satır: ${d.optInt("lineCount")} · Kalan: ${d.optDouble("outstandingQty")}", fontSize = 12.sp, color = Color.Gray)
                        val pct = d.optInt("percentComplete")
                        if (pct > 0) LinearProgressIndicator(progress = { pct / 100f }, modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Uygun satış siparişi yok.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ShipSalesOrder(no: String, onBack: () -> Unit) {
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
    var columns by remember { mutableStateOf(ColumnPrefs.get(context, "salesSource", GridColumns.salesSource)) }
    var showColumns by remember { mutableStateOf(false) }

    fun reload() {
        scope.launch {
            busy = true
            val h = BcApi.get(context, "salesSources('$no')")
            if (h.ok) header = JSONObject(h.body)
            val l = BcApi.get(context, "salesSourceLines?\$filter=no eq '$no' and type eq 'Item'&\$top=200&\$orderby=lineNo")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    val h = header
    val directAllowed = h?.let { it.optBoolean("directShipAllowed", true) } ?: true
    DocumentScanHandler(
        enabled = qtyLine == null && !showScan,
        lines = lines,
        onSingleMatch = { line, _ -> if (directAllowed) { scanFilter = ""; qtyLine = line } },
        onMultiMatch = { itemNo, _ -> scanFilter = itemNo; status = "TAMAM: '$itemNo' için birden fazla satır — birini seçin" },
        onNoMatch = { r -> status = "⚠️ '${r.itemNo ?: r.value}' bu SO'da yok" },
    )
    val displayLines = if (scanFilter.isBlank()) lines else lines.filter { matchLinesByBarcode(listOf(it), com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve(scanFilter)).isNotEmpty() }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ SO Listesi") }
            DocHeaderCard(
                title = no,
                subtitle = "Müşteri: ${firstValue(h ?: JSONObject(), "customerName")} (${firstValue(h ?: JSONObject(), "customerNo")})\n" +
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
                        "⚠ Bu lokasyon (${firstValue(h, "locationCode")}) Ambar Sevkiyatı zorunlu kılıyor. " +
                            "Direkt sevkiyat yapılamaz. Ambar Sevkiyatı sekmesinden ilgili belgeyi açıp sevkiyatı tamamlayın.",
                        modifier = Modifier.padding(10.dp),
                        fontSize = 12.sp,
                        color = Color(0xFF92400E),
                    )
                }
            }
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
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Satırlar (${displayLines.size}/${lines.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { showColumns = true }) { Text("⚙ Kolonlar", fontSize = 12.sp) }
            }
            if (scanFilter.isNotBlank()) { ScanFilterChip(scanFilter) { scanFilter = "" }; Spacer(Modifier.height(4.dp)) }
            LineGrid(
                defs = GridColumns.salesSource, columns = columns, rows = displayLines,
                modifier = Modifier.weight(1f),
                isDone = { lineDone(it, LineModule.SALES) },
                onRowClick = { if (directAllowed) qtyLine = it },
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = invoiceToo, onCheckedChange = { invoiceToo = it })
                Text("Aynı zamanda faturalandır", fontSize = 13.sp)
            }
        }

        BottomActionBar {
            OutlinedButton(onClick = { showScan = true }, enabled = !busy && directAllowed, modifier = Modifier.weight(1f)) { Text("📷 Ürün Tara") }
        }
        BottomActionBar {
            Button(
                onClick = {
                    scope.launch {
                        busy = true; status = "Sevk kaydı..."
                        val body = JSONObject().apply { put("invoice", invoiceToo) }.toString()
                        val r = BcApi.boundAction(context, "salesSources", no, "ship", body)
                        busy = false
                        status = if (r.ok) "TAMAM: SO sevkiyat kaydedildi (HTTP ${r.httpCode})"
                            else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                        if (r.ok) reload()
                    }
                },
                enabled = !busy && directAllowed && com.dynops.bcwms.lib.ActionGuards.hasQuantity(lines, field = "qtyToShip"),
                modifier = Modifier.fillMaxWidth().height(54.dp),
            ) {
                Text(
                    when {
                        !directAllowed -> "Direkt sevkiyat yapılamaz"
                        !com.dynops.bcwms.lib.ActionGuards.hasQuantity(lines, field = "qtyToShip") -> "Önce satırlara miktar girin"
                        else -> if (invoiceToo) "✅ Sevk Et ve Faturalandır" else "✅ Sevk Et"
                    },
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }

    val ql = qtyLine
    if (ql != null) {
        QuantityDialogSheet(
            title = "Sevk Edilecek Miktar",
            itemNo = ql.optString("itemNo"),
            initialQty = ql.optDouble("qtyToShip").takeIf { it > 0 }
                ?: ql.optDouble("outstandingQuantity").takeIf { it > 0 } ?: 1.0,
            initialUom = ql.optString("unitOfMeasureCode"),
            showLotSerial = false,
            onDismiss = { qtyLine = null },
            onConfirm = { res ->
                qtyLine = null
                scope.launch {
                    busy = true; status = "Satır güncelleniyor..."
                    val lineNo = ql.optInt("lineNo")
                    val body = JSONObject().apply {
                        put("qtyToShip", res.quantity)
                    }.toString()
                    val r = BcApi.patch(
                        context,
                        "salesSourceLines(documentType='Order',no='$no',lineNo=$lineNo)",
                        body
                    )
                    busy = false
                    status = if (r.ok) "TAMAM: SO satırı qty=${res.quantity} (HTTP ${r.httpCode})"
                        else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                    if (r.ok) reload()
                }
            }
        )
    }

    if (showScan) {
        ScanItemSheet(title = "Ürün Tara (SO)", onDismiss = { showScan = false }, onItem = { _, line ->
            showScan = false
            qtyLine = line
        }, lines = lines, matchKey = "itemNo")
    }
    if (showColumns) {
        ChooseColumnsSheet(GridColumns.salesSource, columns, onDismiss = { showColumns = false }) { c -> columns = c; ColumnPrefs.save(context, "salesSource", c); showColumns = false }
    }
}

private fun fmtNum(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()
