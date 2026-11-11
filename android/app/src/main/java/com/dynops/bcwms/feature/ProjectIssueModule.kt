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

// Kitoko/Element4 #3338 (11 Kas 2026): Projeye Çıkış.
// 1) Açık saha iş emrini seç (iş emri no + proje no + görev görünür).
// 2) Lokasyon → raf okut → (isteğe bağlı) LP okut → ürün okut ya da iş emri satırından seç → miktar.
// 3) "Çıkış Yap": BC'de proje kullanımı olarak kaydedilir, stok o projeye düşer.

private const val PROJECT_ISSUE_PREFS = "bcwms_project_issue"
private const val PROJECT_ISSUE_LOCATION = "location"

private fun fmtQ(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else "%.3f".format(v).trimEnd('0').trimEnd('.', ',')

@Composable
fun ProjectIssueModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var orders by remember { mutableStateOf<List<FieldWorkOrder>>(emptyList()) }
    var selected by remember { mutableStateOf<FieldWorkOrder?>(null) }
    var query by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true
            val page = BcApi.getAllPages(context, "fieldWorkOrders")
            loading = false
            orders = if (page.complete) page.rows.map(::parseFieldWorkOrder).sortedBy { it.no } else emptyList()
            status = when {
                !page.complete && page.error?.httpCode == 404 -> "HATA: $PROJECT_ISSUE_BC_MISSING"
                !page.complete -> "HATA: Saha iş emirleri okunamadı. ${page.error?.body?.let(BcApi::errorMessage).orEmpty()}"
                orders.isEmpty() -> "Açık saha iş emri yok. Planlama BC'de iş emrini açınca burada görünür."
                else -> ""
            }
        }
    }

    LaunchedEffect(Unit) { load() }
    selected?.let { wo ->
        key(wo.no) { ProjectIssueDocument(wo, onBack = { selected = null; load() }) }
        return
    }

    val shown = filterFieldWorkOrders(orders, query)
    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)), shape = RoundedCornerShape(12.dp)) {
            Column(Modifier.fillMaxWidth().padding(12.dp)) {
                Text("Projeye Çıkış", fontWeight = FontWeight.Bold)
                Text(
                    "Malzemeyi isteyen hangi iş için istiyorsa o saha iş emrini seçin. Çıkan malzeme o projeye yazılır.",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ScanField("İş emri / proje ara", query, { query = it }, onScanned = { query = it.trim() },
                enabled = !loading, okButton = false, onClear = { query = "" }, modifier = Modifier.weight(1f))
            OutlinedButton(onClick = { load() }, enabled = !loading, modifier = Modifier.height(50.dp)) { WmsRefreshLabel(loading) }
        }
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(shown) { wo ->
                Card(onClick = { selected = wo }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp)) {
                    Column(Modifier.padding(14.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(wo.no, fontWeight = FontWeight.Bold, fontSize = 17.sp, modifier = Modifier.weight(1f))
                            Text(wo.status, fontSize = 13.sp, color = MaterialTheme.colorScheme.primary)
                        }
                        Text("Proje ${wo.projectNo} · Görev ${wo.projectTaskNo.ifBlank { "—" }}", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        if (wo.description.isNotBlank()) Text(wo.description, fontSize = 13.sp)
                        val extra = listOfNotNull(
                            wo.projectDescription.takeIf { it.isNotBlank() },
                            wo.team.takeIf { it.isNotBlank() }?.let { "Ekip: $it" },
                            wo.plannedStart.takeIf { it.isNotBlank() }?.let { "Plan: $it" },
                            "${wo.itemLineCount} malzeme".takeIf { wo.itemLineCount > 0 },
                        ).joinToString(" · ")
                        if (extra.isNotBlank()) Text(extra, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (shown.isEmpty() && orders.isNotEmpty()) item { EmptyState("Aramaya uyan iş emri yok.") }
        }
    }
}

private data class ProjectIssuePending(
    val itemNo: String,
    val variantCode: String,
    val description: String,
    val uom: String,
    val lot: String,
    val lotRequired: Boolean,
    val serialRequired: Boolean,
)

@Composable
private fun ProjectIssueDocument(wo: FieldWorkOrder, onBack: () -> Unit) {
    androidx.activity.compose.BackHandler { onBack() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val prefs = remember { context.getSharedPreferences(PROJECT_ISSUE_PREFS, android.content.Context.MODE_PRIVATE) }
    var lines by remember { mutableStateOf<List<FieldWorkOrderLine>>(emptyList()) }
    var locations by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var location by remember { mutableStateOf(prefs.getString(PROJECT_ISSUE_LOCATION, "").orEmpty()) }
    var locExpanded by remember { mutableStateOf(false) }
    var bin by remember { mutableStateOf("") }
    var binScan by remember { mutableStateOf("") }
    var lp by remember { mutableStateOf("") }
    var lpScan by remember { mutableStateOf("") }
    var lpLines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var itemScan by remember { mutableStateOf("") }
    var pending by remember { mutableStateOf<ProjectIssuePending?>(null) }
    var confirm by remember { mutableStateOf<ProjectIssueRequest?>(null) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var done by remember { mutableStateOf<List<String>>(emptyList()) }
    val itemFocus = remember { androidx.compose.ui.focus.FocusRequester() }
    val binMandatory = locations.firstOrNull { it.optString("code").equals(location, ignoreCase = true) }
        ?.let { it.optBoolean("binMandatory") || it.optBoolean("directedPutAwayAndPick") } == true

    suspend fun reloadLines() {
        val page = BcApi.getAllPages(context, fieldWorkOrderLinesPath(wo.no))
        if (page.complete) lines = parseFieldWorkOrderItemLines(page.rows)
    }

    LaunchedEffect(wo.no) {
        busy = true
        reloadLines()
        val page = BcApi.getAllPages(context, "locations?\$top=200")
        // Yönlendirilmiş lokasyon da listelenir: BC orada çıkışı ambar toplaması üzerinden yapar
        // (planlama satırı → okutulan raftan toplama → Projeye Depo Gözü → proje kullanımı).
        if (page.complete) locations = page.rows.filterNot { it.optBoolean("useAsInTransit") }
            .sortedBy { it.optString("code") }
        if (location.isBlank() && locations.size == 1) location = locations.first().optString("code")
        busy = false
    }

    fun clearLp() { lp = ""; lpLines = emptyList() }

    fun scanLp(raw: String) {
        lpScan = ""
        val resolved = BarcodeIntentResolver.resolve(raw)
        val lpNo = (resolved.value.takeIf { resolved.kind == BarcodeKind.Lp } ?: raw).trim().uppercase()
        if (lpNo.isBlank()) return
        scope.launch {
            busy = true
            val h = BcApi.get(context, "licensePlates('${lpNo.replace("'", "''")}')")
            val header = if (h.ok) runCatching { JSONObject(h.body) }.getOrNull() else null
            if (header == null) { busy = false; clearLp(); status = "HATA: $lpNo LP'si bulunamadı."; return@launch }
            val lpBin = header.optString("binCode")
            val lpLoc = header.optString("locationCode")
            if (location.isNotBlank() && !lpLoc.equals(location, ignoreCase = true)) {
                busy = false; clearLp(); status = "HATA: $lpNo LP'si $location lokasyonunda değil ($lpLoc)."; return@launch
            }
            if (bin.isNotBlank() && !lpBin.equals(bin, ignoreCase = true)) {
                busy = false; clearLp(); status = "HATA: $lpNo LP'si $bin rafında değil (LP rafı: $lpBin)."; return@launch
            }
            if (location.isBlank()) location = lpLoc
            if (bin.isBlank()) bin = lpBin
            val page = BcApi.getAllPages(context, "licensePlateLines?\$filter=lpNo eq '${lpNo.replace("'", "''")}'&\$orderby=lineNo")
            lpLines = if (page.complete) page.rows.filter { it.optDouble("quantity", 0.0) > 0.0 } else emptyList()
            lp = lpNo
            busy = false
            status = if (lpLines.isEmpty()) "UYARI: $lpNo LP'si boş görünüyor." else "LP: $lpNo · şimdi çıkacak ürünü okutun veya aşağıdan seçin"
            runCatching { itemFocus.requestFocus() }
        }
    }

    fun pickItem(itemNo: String, lotFromScan: String = "", variantCode: String = "") {
        val no = itemNo.trim().uppercase()
        if (no.isBlank()) return
        if (location.isBlank()) { status = "HATA: Önce lokasyon seçin."; return }
        if (binMandatory && bin.isBlank()) { status = "HATA: Bu lokasyon raf zorunlu; önce rafı okutun."; return }
        scope.launch {
            busy = true
            val r = BcApi.get(context, "items?\$filter=no eq '${no.replace("'", "''")}'&\$top=1")
            busy = false
            val item = if (r.ok) BcApi.parseValueArray(r.body).firstOrNull() else null
            if (item == null) { status = if (r.ok) "HATA: '$no' BC'de ürün olarak bulunamadı." else "HATA: Ürün okunamadı (${r.httpCode})."; return@launch }
            val lpItemLines = lpLines.filter { it.optString("itemNo").equals(no, ignoreCase = true) }
            val lpLot = lpItemLines.map { it.optString("lotNo") }.distinct().singleOrNull().orEmpty()
            // Varyant: LP satırından seçildiyse o satırın varyantı; okutulduysa LP'de tek varyant varsa o.
            val variant = variantCode.ifBlank { lpItemLines.map { it.optString("variantCode") }.distinct().singleOrNull().orEmpty() }
            status = ""
            pending = ProjectIssuePending(
                itemNo = item.optString("no"),
                variantCode = variant,
                description = item.optString("description"),
                uom = item.optString("baseUnitOfMeasure"),
                lot = lotFromScan.ifBlank { lpLot },
                lotRequired = item.optBoolean("lotTrackingRequired"),
                serialRequired = item.optBoolean("serialTrackingRequired"),
            )
        }
    }

    fun scanItem(raw: String) {
        itemScan = ""
        val resolved = BarcodeIntentResolver.resolve(raw)
        if (resolved.kind == BarcodeKind.Lp || resolved.kind == BarcodeKind.LpTemplate) { scanLp(raw); return }
        val item = (resolved.itemNo ?: resolved.value).trim().ifBlank { raw.trim() }
        pickItem(item, resolved.lotNo.orEmpty())
    }

    fun issue(request: ProjectIssueRequest) {
        scope.launch {
            busy = true
            val r = BcApi.boundActionLongRunning(context, "fieldWorkOrders", wo.no, "issueItem", projectIssueBody(request))
            confirm = null
            if (r.ok) {
                val summary = BcApi.scalarValue(r.body).ifBlank { "${request.itemNo} × ${fmtQ(request.quantity)}" }
                done = listOf(summary) + done
                status = "TAMAM: ${request.itemNo} × ${fmtQ(request.quantity)} ${request.uom} projeye düşüldü (${wo.projectNo})"
                prefs.edit().putString(PROJECT_ISSUE_LOCATION, request.locationCode).apply()
                if (lp.isNotBlank()) {
                    val page = BcApi.getAllPages(context, "licensePlateLines?\$filter=lpNo eq '${lp.replace("'", "''")}'&\$orderby=lineNo")
                    lpLines = if (page.complete) page.rows.filter { it.optDouble("quantity", 0.0) > 0.0 } else emptyList()
                    if (lpLines.isEmpty()) clearLp()
                }
                reloadLines()
            } else status = when {
                r.httpCode == 404 -> "HATA: $PROJECT_ISSUE_BC_MISSING"
                BcApi.isAmbiguousMutationFailure(r) -> "UYARI: Cevap alınamadı. Tekrar basmadan önce BC'de proje kayıtlarını kontrol edin."
                else -> "HATA: ${BcApi.errorMessage(r.body)}"
            }
            busy = false
            runCatching { itemFocus.requestFocus() }
        }
    }

    Column(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    TextButton(onClick = onBack) { Text("‹ Saha İş Emirleri") }
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer), shape = RoundedCornerShape(16.dp)) {
                        Column(Modifier.fillMaxWidth().padding(14.dp)) {
                            Text(wo.no, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                            Text("Proje ${wo.projectNo} · Görev ${wo.projectTaskNo.ifBlank { "—" }}", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                            if (wo.projectDescription.isNotBlank()) Text(wo.projectDescription, fontSize = 13.sp)
                            if (wo.description.isNotBlank()) Text(wo.description, fontSize = 13.sp)
                        }
                    }
                    StatusText(status)
                    Box {
                        OutlinedButton(onClick = { locExpanded = true }, enabled = !busy, modifier = Modifier.fillMaxWidth().height(50.dp)) {
                            Text(if (location.isBlank()) "Lokasyon seç" else "📍 Lokasyon: $location", fontWeight = FontWeight.SemiBold)
                        }
                        DropdownMenu(expanded = locExpanded, onDismissRequest = { locExpanded = false }) {
                            locations.forEach { l ->
                                val code = l.optString("code")
                                DropdownMenuItem(text = { Text("$code · ${l.optString("name")}") }, onClick = {
                                    if (!code.equals(location, ignoreCase = true)) { bin = ""; clearLp() }
                                    location = code; locExpanded = false
                                })
                            }
                        }
                    }
                    if (binMandatory) {
                        ScanField("Raf okut", binScan, { binScan = it },
                            onScanned = { bin = it.trim().uppercase(); binScan = ""; clearLp(); status = "Raf: $bin · LP veya ürün okutun"; runCatching { itemFocus.requestFocus() } },
                            enabled = !busy, modifier = Modifier.fillMaxWidth())
                        if (bin.isNotBlank()) Text("Raf: $bin", fontWeight = FontWeight.Bold)
                    }
                    ScanField("LP okut (palet/kutudan veriyorsanız)", lpScan, { lpScan = it }, onScanned = { scanLp(it) },
                        enabled = !busy, okButton = true, onClear = if (lp.isNotBlank()) ({ clearLp() }) else null, modifier = Modifier.fillMaxWidth())
                    if (lp.isNotBlank()) Text("LP: $lp", fontWeight = FontWeight.Bold)
                    ScanField("Ürün okut", itemScan, { itemScan = it }, onScanned = { scanItem(it) },
                        enabled = !busy && pending == null, autoFocus = true, focusRequester = itemFocus, modifier = Modifier.fillMaxWidth())
                    if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                    if (lpLines.isNotEmpty()) Text("LP içeriği (dokunarak seçin)", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                }
            }
            items(lpLines) { l ->
                OutlinedCard(onClick = { pickItem(l.optString("itemNo"), l.optString("lotNo"), l.optString("variantCode")) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                    Text("${l.optString("itemNo")} · ${fmtQ(l.optDouble("quantity", 0.0))} ${l.optString("unitOfMeasure")}" +
                        l.optString("lotNo").takeIf { it.isNotBlank() }?.let { " · Lot $it" }.orEmpty() +
                        l.optString("itemDescription").takeIf { it.isNotBlank() }?.let { "\n$it" }.orEmpty(),
                        Modifier.padding(10.dp), fontSize = 13.sp)
                }
            }
            item { Text("İş emri malzemeleri (${lines.size})", fontWeight = FontWeight.Bold, fontSize = 15.sp, modifier = Modifier.padding(top = 6.dp)) }
            items(lines) { ln ->
                Card(onClick = { pickItem(ln.itemNo) }, enabled = !busy, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(ln.itemNo, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                            if (ln.description.isNotBlank()) Text(ln.description, fontSize = 13.sp)
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text("${fmtQ(ln.actualQuantity)} / ${fmtQ(ln.quantity)} ${ln.uom}", fontWeight = FontWeight.Bold, fontSize = 15.sp,
                                color = if (ln.remaining <= 0.0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
                            Text("çıkan / planlanan", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            if (lines.isEmpty() && !busy) item { EmptyState("İş emrinde malzeme satırı yok. Ürünü okutarak çıkış yapabilirsiniz.") }
            if (done.isNotEmpty()) {
                item { Text("Bu ekranda yapılan çıkışlar", fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp)) }
                items(done) { d -> Text("✓ $d", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
    }

    pending?.let { p ->
        val planned = lines.firstOrNull { it.itemNo.equals(p.itemNo, ignoreCase = true) }
        QuantityDialogSheet(
            title = "Projeye çıkacak miktar",
            itemNo = p.itemNo + p.variantCode.takeIf { it.isNotBlank() }?.let { " ($it)" }.orEmpty() + p.description.takeIf { it.isNotBlank() }?.let { " · $it" }.orEmpty(),
            initialQty = planned?.remaining?.takeIf { it > 0.0 } ?: 1.0,
            initialUom = planned?.uom?.ifBlank { null } ?: p.uom,
            initialLot = p.lot,
            showLotSerial = p.lotRequired || p.serialRequired,
            showSerial = p.serialRequired,
            lotRequired = p.lotRequired,
            serialRequired = p.serialRequired,
            quantityExactlyOne = p.serialRequired,
            locationCode = location,
            binCode = bin,
            onDismiss = { pending = null; runCatching { itemFocus.requestFocus() } },
            onConfirm = { res ->
                pending = null
                val request = ProjectIssueRequest(
                    workOrderNo = wo.no,
                    itemNo = p.itemNo,
                    variantCode = p.variantCode,
                    quantity = res.quantity,
                    uom = res.uom.ifBlank { p.uom },
                    locationCode = location,
                    binCode = if (binMandatory) bin else "",
                    lpNo = lp,
                    lotNo = res.lotNo,
                    serialNo = res.serialNo,
                    userId = "pending",
                )
                val error = validateProjectIssue(request, binMandatory)
                if (error != null) status = "HATA: $error" else confirm = request
            },
        )
    }

    confirm?.let { req ->
        AlertDialog(
            onDismissRequest = { if (!busy) confirm = null },
            title = { Text("Projeye çıkış yapılsın mı?") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("${req.itemNo}${req.variantCode.takeIf { it.isNotBlank() }?.let { " ($it)" }.orEmpty()} × ${fmtQ(req.quantity)} ${req.uom}", fontWeight = FontWeight.Bold, fontSize = 17.sp)
                    Text("İş emri: ${wo.no}")
                    Text("Proje: ${wo.projectNo} · Görev: ${wo.projectTaskNo}")
                    Text("Nereden: ${req.locationCode}${req.binCode.takeIf { it.isNotBlank() }?.let { " / $it" }.orEmpty()}" +
                        req.lpNo.takeIf { it.isNotBlank() }?.let { " · LP $it" }.orEmpty())
                    if (req.lotNo.isNotBlank()) Text("Lot: ${req.lotNo}")
                    if (req.serialNo.isNotBlank()) Text("Seri: ${req.serialNo}")
                    Text("Stok bu projeye düşülür. Geri almak için BC'de düzeltme gerekir.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            },
            confirmButton = {
                Button(onClick = {
                    scope.launch {
                        val user = BcApi.currentUserId(context).trim()
                        val ready = req.copy(userId = user)
                        val error = validateProjectIssue(ready, binMandatory)
                        if (error != null) { confirm = null; status = "HATA: $error" } else issue(ready)
                    }
                }, enabled = !busy) { Text("Çıkış Yap") }
            },
            dismissButton = { TextButton(onClick = { confirm = null }, enabled = !busy) { Text("Vazgeç") } },
        )
    }
}
