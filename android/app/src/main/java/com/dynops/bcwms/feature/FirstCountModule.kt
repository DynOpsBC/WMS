package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.BarcodeKind
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.EmptyState
import com.dynops.bcwms.ui.QuantityDialogSheet
import com.dynops.bcwms.ui.StatusText
import com.dynops.bcwms.ui.WmsRefreshLabel
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.UUID

// Kitoko (22 Eki 2026): İlk Sayım — rafsız/alansız. Lokasyon seç → madde QR okut →
// adet gir. Aynı madde tekrar okutulursa adetler toplanır. "Stoğa İşle" ile okutulan
// maddelerin lokasyon stoğu sayılan toplama eşitlenir; okutulmayanlara dokunulmaz.
// BC tarafı: BCWMSApp 1.14.3.19 (firstCounts / firstCountLines).

private const val FIRST_COUNT_PREFS = "bcwms_first_count"
private const val FIRST_COUNT_LOCATION = "location"
internal const val FIRST_COUNT_BC_MISSING = "Bu BC sürümünde İlk Sayım yok. BCWMSApp 1.14.3.19 kurulmalı."

/** Ekranda madde başına toplam: aynı madde/varyant/lot/raf satırları toplanır. */
internal data class FirstCountTotal(val itemNo: String, val description: String, val lotNo: String, val binCode: String, val uom: String, val quantity: Double, val scans: Int)

internal fun firstCountTotals(lines: List<JSONObject>): List<FirstCountTotal> =
    lines.groupBy { listOf(it.optString("binCode"), it.optString("itemNo"), it.optString("variantCode"), it.optString("lotNo")) }
        .map { (_, group) ->
            val first = group.first()
            FirstCountTotal(
                itemNo = first.optString("itemNo"),
                description = first.optString("description"),
                lotNo = first.optString("lotNo"),
                binCode = first.optString("binCode"),
                uom = first.optString("unitOfMeasureCode"),
                quantity = group.sumOf { it.optDouble("quantityBase", it.optDouble("quantity", 0.0)) },
                scans = group.size,
            )
        }

/** Madde QR'ı: LP etiketi reddedilir; GS1 içinden madde/lot alınır, düz metin madde no sayılır. */
internal fun firstCountItemFromScan(raw: String): Pair<String, String>? {
    val resolved = BarcodeIntentResolver.resolve(raw)
    if (resolved.kind == BarcodeKind.Lp || resolved.kind == BarcodeKind.LpTemplate) return null
    val item = (resolved.itemNo ?: resolved.value).trim().ifBlank { raw.trim() }
    return item.uppercase() to resolved.lotNo.orEmpty().trim()
}

private fun fmtQty(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()

@Composable
fun FirstCountModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val prefs = remember { context.getSharedPreferences(FIRST_COUNT_PREFS, android.content.Context.MODE_PRIVATE) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var selected by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var showCreate by remember { mutableStateOf(false) }
    var location by remember { mutableStateOf(prefs.getString(FIRST_COUNT_LOCATION, "").orEmpty()) }
    var locations by remember { mutableStateOf<List<String>>(emptyList()) }
    var locExpanded by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true
            val page = BcApi.getAllPages(context, "firstCounts?\$filter=status eq 'Open'&\$top=50")
            loading = false
            rows = if (page.complete) page.rows.sortedByDescending { it.optString("createdDateTime") } else emptyList()
            status = when {
                !page.complete -> "HATA: $FIRST_COUNT_BC_MISSING"
                rows.isEmpty() -> "Açık İlk Sayım yok. \"Yeni İlk Sayım\" ile başlayın."
                else -> ""
            }
        }
    }

    fun loadLocations() {
        scope.launch {
            val page = BcApi.getAllPages(context, "locations?\$top=200")
            if (page.complete) locations = page.rows.filterNot { it.optBoolean("useAsInTransit") || it.optBoolean("directedPutAwayAndPick") }
                .map { it.optString("code") }.filter(String::isNotBlank).sorted()
        }
    }

    fun create() {
        val loc = location.trim().uppercase()
        if (loc.isBlank()) return
        scope.launch {
            loading = true
            val user = BcApi.currentUserId(context).trim()
            val r = BcApi.post(context, "firstCounts", JSONObject().put("locationCode", loc).put("createdBy", user).toString())
            loading = false
            showCreate = false
            if (r.ok) {
                prefs.edit().putString(FIRST_COUNT_LOCATION, loc).apply()
                selected = runCatching { JSONObject(r.body).optString("no") }.getOrDefault("").ifBlank { null }
                if (selected == null) load()
            } else status = if (r.httpCode == 404) "HATA: $FIRST_COUNT_BC_MISSING" else "HATA: ${BcApi.errorMessage(r.body)}"
        }
    }

    LaunchedEffect(Unit) { load() }
    selected?.let { no ->
        key(no) { FirstCountDocument(no, onBack = { selected = null; load() }) }
        return
    }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)), shape = RoundedCornerShape(12.dp)) {
            Column(Modifier.fillMaxWidth().padding(12.dp)) {
                Text("İlk Sayım — sadece madde", fontWeight = FontWeight.Bold)
                Text(
                    "Raf ve alan yok: madde QR'ını okutun, adedi girin. Aynı madde tekrar okutulursa adetler toplanır. " +
                        "Stoğa İşle deyince okutulan maddelerin lokasyon stoğu sayılan adede eşitlenir; okutulmayanlara dokunulmaz.",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { showCreate = true; loadLocations() }, enabled = !loading, modifier = Modifier.weight(1f).height(50.dp)) { Text("➕ Yeni İlk Sayım") }
            OutlinedButton(onClick = { load() }, enabled = !loading, modifier = Modifier.height(50.dp)) { WmsRefreshLabel(loading) }
        }
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { r ->
                Card(onClick = { selected = r.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp)) {
                    Column(Modifier.padding(14.dp)) {
                        Text(r.optString("no"), fontWeight = FontWeight.Bold, fontSize = 16.sp)
                        Text("📍 ${r.optString("locationCode")} · ${r.optInt("lineCount")} okutma · ${r.optString("createdBy")}", fontSize = 13.sp)
                    }
                }
            }
        }
    }

    if (showCreate) AlertDialog(
        onDismissRequest = { if (!loading) showCreate = false },
        title = { Text("Yeni İlk Sayım") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Box {
                    OutlinedTextField(
                        value = location,
                        onValueChange = { location = it.uppercase() },
                        label = { Text("Lokasyon") },
                        singleLine = true,
                        trailingIcon = { if (locations.isNotEmpty()) TextButton(onClick = { locExpanded = true }) { Text("Seç") } },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    DropdownMenu(expanded = locExpanded, onDismissRequest = { locExpanded = false }) {
                        locations.forEach { code -> DropdownMenuItem(text = { Text(code) }, onClick = { location = code; locExpanded = false }) }
                    }
                }
            }
        },
        confirmButton = { Button(onClick = { create() }, enabled = !loading && location.isNotBlank()) { Text("Oluştur ve Aç") } },
        dismissButton = { TextButton(onClick = { showCreate = false }, enabled = !loading) { Text("Vazgeç") } },
    )
}

private data class FirstCountPending(val itemNo: String, val description: String, val uom: String, val lot: String, val lotRequired: Boolean)

@Composable
private fun FirstCountDocument(no: String, onBack: () -> Unit) {
    androidx.activity.compose.BackHandler { onBack() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var itemScan by remember { mutableStateOf("") }
    var binScan by remember { mutableStateOf("") }
    var bin by remember { mutableStateOf("") }
    var pending by remember { mutableStateOf<FirstCountPending?>(null) }
    var deleteLine by remember { mutableStateOf<JSONObject?>(null) }
    var showPost by remember { mutableStateOf(false) }
    val itemFocus = remember { androidx.compose.ui.focus.FocusRequester() }
    val binMandatory = header?.optBoolean("binMandatory") == true
    val open = header?.optString("status").orEmpty().equals("Open", ignoreCase = true)

    suspend fun reload(): Boolean {
        val safe = no.replace("'", "''")
        val h = BcApi.get(context, "firstCounts('$safe')")
        val page = BcApi.getAllPages(context, "firstCountLines?\$filter=countNo eq '$safe'&\$top=1000")
        if (!h.ok || !page.complete) { status = "HATA: İlk Sayım okunamadı. Yenileyin."; return false }
        header = runCatching { JSONObject(h.body) }.getOrNull()
        lines = page.rows
        return true
    }
    LaunchedEffect(no) { busy = true; reload(); busy = false }

    fun scanItem(raw: String) {
        itemScan = ""
        if (busy || !open) return
        if (binMandatory && bin.isBlank()) { status = "HATA: Bu lokasyon raf zorunlu; önce rafı okutun."; return }
        val parsed = firstCountItemFromScan(raw) ?: run { status = "HATA: LP etiketi okuttunuz. Maddenin QR'ını okutun."; return }
        scope.launch {
            busy = true
            val r = BcApi.get(context, "items?\$filter=no eq '${parsed.first.replace("'", "''")}'&\$top=1")
            busy = false
            val item = if (r.ok) BcApi.parseValueArray(r.body).firstOrNull() else null
            if (item == null) { status = if (r.ok) "HATA: '${parsed.first}' BC'de madde olarak bulunamadı." else "HATA: Madde okunamadı (${r.httpCode})."; return@launch }
            if (item.optBoolean("serialTrackingRequired")) { status = "HATA: ${parsed.first} seri takipli; İlk Sayım'da sayılamaz."; return@launch }
            status = ""
            pending = FirstCountPending(item.optString("no"), item.optString("description"), item.optString("baseUnitOfMeasure"),
                parsed.second, item.optBoolean("lotTrackingRequired"))
        }
    }

    fun addLine(p: FirstCountPending, qty: Double, uom: String, lot: String) {
        scope.launch {
            busy = true
            val body = JSONObject().apply {
                put("scanId", UUID.randomUUID().toString())
                put("itemNo", p.itemNo)
                put("variantCode", "")
                put("binCode", if (binMandatory) bin else "")
                put("lotNo", lot.trim())
                put("unitOfMeasureCode", uom)
                put("quantity", qty)
                put("userId", BcApi.currentUserId(context).trim())
            }.toString()
            val r = BcApi.boundAction(context, "firstCounts", no, "addLine", body)
            if (r.ok) {
                reload()
                val total = firstCountTotals(lines).filter { it.itemNo == p.itemNo && it.lotNo == lot.trim() && it.binCode == (if (binMandatory) bin else "") }.sumOf { it.quantity }
                status = "TAMAM: ${p.itemNo} +${fmtQty(qty)} · toplam ${fmtQty(total)} ${p.uom}"
            } else status = "HATA: ${BcApi.errorMessage(r.body)}"
            busy = false
            runCatching { itemFocus.requestFocus() }
        }
    }

    fun removeLine(line: JSONObject) {
        scope.launch {
            busy = true
            val r = BcApi.boundAction(context, "firstCounts", no, "deleteLine", JSONObject().put("lineNo", line.optInt("lineNo")).toString())
            if (r.ok) { reload(); status = "TAMAM: ${line.optString("itemNo")} × ${fmtQty(line.optDouble("quantity"))} silindi" }
            else status = "HATA: ${BcApi.errorMessage(r.body)}"
            busy = false
        }
    }

    fun post() {
        scope.launch {
            busy = true
            val r = BcApi.boundActionLongRunning(context, "firstCounts", no, "post", JSONObject().put("userId", BcApi.currentUserId(context).trim()).toString())
            showPost = false
            if (r.ok) {
                reload()
                status = "TAMAM: Stok güncellendi · ${BcApi.scalarValue(r.body).ifBlank { "0" }} madde satırında fark işlendi"
            } else status = if (BcApi.isAmbiguousMutationFailure(r)) "UYARI: Cevap alınamadı. Tekrar basmadan önce Yenile ile durumu kontrol edin."
                else "HATA: ${BcApi.errorMessage(r.body)}"
            busy = false
        }
    }

    val totals = firstCountTotals(lines)
    Column(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    TextButton(onClick = onBack) { Text("‹ İlk Sayımlar") }
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer), shape = RoundedCornerShape(16.dp)) {
                        Column(Modifier.fillMaxWidth().padding(14.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(no, fontWeight = FontWeight.Bold, fontSize = 20.sp, modifier = Modifier.weight(1f))
                                Text(if (open) "Açık" else "İşlendi", fontWeight = FontWeight.SemiBold)
                            }
                            Text("📍 ${header?.optString("locationCode").orEmpty()}", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                            Text("${totals.size} madde · ${lines.size} okutma", fontSize = 14.sp)
                        }
                    }
                    StatusText(status)
                    if (open) {
                        if (binMandatory) {
                            ScanField("Raf okut (raf zorunlu lokasyon)", binScan, { binScan = it },
                                onScanned = { bin = it.trim().uppercase(); binScan = ""; status = "Raf: $bin · şimdi madde okutun"; runCatching { itemFocus.requestFocus() } },
                                enabled = !busy, modifier = Modifier.fillMaxWidth())
                            if (bin.isNotBlank()) Text("Raf: $bin", fontWeight = FontWeight.Bold)
                        }
                        ScanField("Madde QR'ını okut", itemScan, { itemScan = it }, onScanned = { scanItem(it) },
                            enabled = !busy && pending == null, autoFocus = true, focusRequester = itemFocus, modifier = Modifier.fillMaxWidth())
                    }
                    if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                    Text("Sayılanlar (${totals.size})", fontWeight = FontWeight.Bold, fontSize = 15.sp)
                }
            }
            items(totals) { t ->
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(t.itemNo, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                            if (t.description.isNotBlank()) Text(t.description, fontSize = 13.sp)
                            val extra = listOfNotNull(t.lotNo.takeIf { it.isNotBlank() }?.let { "Lot $it" }, t.binCode.takeIf { it.isNotBlank() }?.let { "Raf $it" },
                                "${t.scans} okutma".takeIf { t.scans > 1 }).joinToString(" · ")
                            if (extra.isNotBlank()) Text(extra, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text("${fmtQty(t.quantity)} ${t.uom}", fontWeight = FontWeight.Bold, fontSize = 17.sp, color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
            if (lines.isNotEmpty() && open) item {
                Text("Okutmalar (silmek için dokunun)", fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
            }
            if (open) items(lines.sortedByDescending { it.optInt("lineNo") }) { ln ->
                OutlinedCard(onClick = { deleteLine = ln }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                    Text("${ln.optString("itemNo")} × ${fmtQty(ln.optDouble("quantity"))} ${ln.optString("unitOfMeasureCode")}" +
                        ln.optString("lotNo").takeIf { it.isNotBlank() }?.let { " · Lot $it" }.orEmpty(), Modifier.padding(10.dp), fontSize = 13.sp)
                }
            }
            if (lines.isEmpty() && !busy) item { EmptyState("Henüz okutma yok. Madde QR'ını okutun.") }
        }
        if (open) Surface(tonalElevation = 3.dp, shadowElevation = 4.dp) {
            Button(
                onClick = { showPost = true },
                enabled = !busy && lines.isNotEmpty(),
                modifier = Modifier.fillMaxWidth().padding(12.dp).height(54.dp),
            ) { Text("✅ Stoğa İşle (${totals.size} madde)", fontWeight = FontWeight.Bold) }
        }
    }

    pending?.let { p ->
        QuantityDialogSheet(
            title = "Sayılan adet",
            itemNo = p.itemNo + p.description.takeIf { it.isNotBlank() }?.let { " · $it" }.orEmpty(),
            initialQty = 1.0,
            initialUom = p.uom,
            initialLot = p.lot,
            showLotSerial = p.lotRequired,
            showSerial = false,
            lotRequired = p.lotRequired,
            onDismiss = { pending = null; runCatching { itemFocus.requestFocus() } },
            onConfirm = { res -> pending = null; addLine(p, res.quantity, res.uom.ifBlank { p.uom }, res.lotNo) },
        )
    }
    deleteLine?.let { ln ->
        AlertDialog(
            onDismissRequest = { deleteLine = null },
            title = { Text("Okutma silinsin mi?") },
            text = { Text("${ln.optString("itemNo")} × ${fmtQty(ln.optDouble("quantity"))} ${ln.optString("unitOfMeasureCode")}") },
            confirmButton = { TextButton(onClick = { deleteLine = null; removeLine(ln) }) { Text("Sil", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { deleteLine = null }) { Text("Vazgeç") } },
        )
    }
    if (showPost) AlertDialog(
        onDismissRequest = { if (!busy) showPost = false },
        title = { Text("Stoğa işlensin mi?") },
        text = { Text("${totals.size} maddenin ${header?.optString("locationCode").orEmpty()} stoğu sayılan adetlere eşitlenecek. Okutulmayan maddelere dokunulmaz. Bu işlem geri alınamaz.") },
        confirmButton = { Button(onClick = { post() }, enabled = !busy) { Text("Onayla ve İşle") } },
        dismissButton = { TextButton(onClick = { showPost = false }, enabled = !busy) { Text("Vazgeç") } },
    )
}
