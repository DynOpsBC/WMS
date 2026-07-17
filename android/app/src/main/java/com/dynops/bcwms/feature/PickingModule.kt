package com.dynops.bcwms.feature

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
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
    // ELOG akışı: depocu multi/bulk/batch moduna göre bekleyen pick'leri görür
    // ve listeden üstüne alır (pickMode damgası MultiOrderPick'ten gelir).
    var modeFilter by remember { mutableStateOf("") }
    var pendingOnly by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val myUser = if (showAll) "" else BcApi.currentUserId(context)
            val baseClauses = arrayOf(
                assignedToMeClause(myUser, enabled = !showAll),
                searchClause("no", search),
                if (pendingOnly) "assignedUserId eq ''" else null,
            )
            val combined = buildODataFilter(
                *baseClauses,
                if (modeFilter.isNotBlank()) "pickMode eq '$modeFilter'" else null,
            )
            var r = BcApi.getWithStandardFallback(context, "picks?\$top=100&\$orderby=no desc&\$select=no,locationCode,assignedUserId,pickMode,sourceNo,status,percentComplete$combined")
            var modeUnsupported = false
            if (r.httpCode == 400) {
                // Eski publish'te pickMode alanı yok — alansız/filtre­siz sorguya düş.
                modeUnsupported = true
                val legacy = buildODataFilter(*baseClauses)
                r = BcApi.getWithStandardFallback(context, "picks?\$top=100&\$orderby=no desc&\$select=no,locationCode,assignedUserId,sourceNo,status,percentComplete$legacy")
            }
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Toplama listesi alınamadı (HTTP ${r.httpCode})"
                else if (modeUnsupported && modeFilter.isNotBlank()) "⚠️ Mod filtresi sunucuda henüz yok (publish bekliyor) — tümü listelendi"
                else if (rows.isEmpty()) "EMPTY: Açık toplama belgesi yok (HTTP ${r.httpCode})"
                else "PASS: ${rows.size} belge (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(showAll, modeFilter, pendingOnly) { load() }

    // Listeden "Üzerime Al": paylaşımlı BC lisansında atama BC hesabına değil
    // oturumdaki WMS kullanıcısına yazılır (reassign); WMS girişi yoksa
    // assignToMe'ye düşer.
    fun takeOver(no: String) {
        scope.launch {
            loading = true; status = "Üzerine alınıyor..."
            val me = BcApi.currentUserId(context)
            val r = if (me.isNotBlank())
                BcApi.boundAction(context, "picks", no, "reassign",
                    JSONObject().apply { put("userId", me); put("reason", "terminalden üstlenildi") }.toString())
            else BcApi.boundAction(context, "picks", no, "assignToMe", "{}")
            status = if (r.ok) "PASS: $no üzerinize alındı${if (me.isNotBlank()) " ($me)" else ""}"
                else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            load()
        }
    }

    var itemDocs by remember { mutableStateOf<Pair<String, Set<String>>?>(null) }
    val sel = selected
    if (sel != null) { PickDocument(no = sel, onBack = { selected = null; load() }); return }

    DocListScanHandler(
        enabled = true,
        linesEndpoint = "pickLines",
        documentsEndpoint = "picks",
        acceptDocTypes = setOf("pick"),
        onDocument = { selected = it },
    ) { item, docs ->
        when { docs.isEmpty() -> status = "⚠️ '$item' açık toplamada yok"; docs.size == 1 -> selected = docs.first(); else -> { itemDocs = item to docs; status = "PASS: '$item' → ${docs.size} belge" } }
    }
    val shownRows = itemDocs?.let { f -> rows.filter { it.optString("no") in f.second } } ?: rows

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            FilterChip(selected = !showAll, onClick = { showAll = false }, label = { Text("👤 Bana atanan") })
            Spacer(Modifier.width(6.dp))
            FilterChip(selected = showAll, onClick = { showAll = true }, label = { Text("Tümü") })
            Spacer(Modifier.weight(1f))
            OutlinedButton(
                onClick = { load() },
                enabled = !loading,
                shape = RoundedCornerShape(50),
                contentPadding = PaddingValues(horizontal = 14.dp),
            ) { Text(if (loading) "…" else "🔄", fontSize = 15.sp) }
        }
        Spacer(Modifier.height(6.dp))
        // ELOG: multi/bulk/batch mod sekmeleri + atanmayı bekleyenler.
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            FilterChip(selected = modeFilter == "Multi", onClick = { modeFilter = if (modeFilter == "Multi") "" else "Multi" }, label = { Text("🧍 Multi") })
            FilterChip(selected = modeFilter == "Bulk", onClick = { modeFilter = if (modeFilter == "Bulk") "" else "Bulk" }, label = { Text("📚 Bulk") })
            FilterChip(selected = modeFilter == "Batch", onClick = { modeFilter = if (modeFilter == "Batch") "" else "Batch" }, label = { Text("1️⃣ Batch") })
            FilterChip(selected = pendingOnly, onClick = { pendingOnly = !pendingOnly }, label = { Text("⏳ Bekleyen") })
        }
        Spacer(Modifier.height(10.dp))
        // PDF Picking §7 / §16: belge no arama eksikti
        OutlinedTextField(
            value = search,
            onValueChange = { search = it },
            singleLine = true,
            label = { Text("Belge no ile ara") },
            shape = RoundedCornerShape(14.dp),
            trailingIcon = { TextButton(onClick = { load() }) { Text("🔎") } },
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        if (itemDocs != null) { ScanFilterChip("${itemDocs!!.first} → ${itemDocs!!.second.size} belge") { itemDocs = null } }
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(shownRows) { d ->
                PickListCard(
                    d = d,
                    busy = loading,
                    onOpen = { selected = d.optString("no") },
                    onTake = { takeOver(d.optString("no")) },
                )
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Açık toplama belgesi yok.") }
        }
    }
}

private fun pickModeEmoji(mode: String): String = when (mode.lowercase()) {
    "multi" -> "🧍 "
    "bulk" -> "📚 "
    "batch" -> "1️⃣ "
    else -> ""
}

private val PickAccent = Color(0xFF6C5CE7) // Ana menü "Giden" kategorisiyle aynı vurgu.
private val PendingOrange = Color(0xFFE65100)

/** Ana menü kart diliyle pick satırı: mod ikonu, ilerleme, atanma durumu, Üzerime Al. */
@Composable
private fun PickListCard(d: JSONObject, busy: Boolean, onOpen: () -> Unit, onTake: () -> Unit) {
    val assigned = firstValue(d, "assignedUserId")
    // BC boş enum değeri sürüme göre "-", " " ya da "_x0020_" dönebiliyor.
    val mode = firstValue(d, "pickMode").trim().takeIf { it.isNotBlank() && it != "-" && it != "_x0020_" } ?: ""
    val pct = d.optInt("percentComplete").coerceIn(0, 100)
    Card(
        onClick = onOpen,
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.4f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp, pressedElevation = 4.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(44.dp).clip(RoundedCornerShape(13.dp)).background(PickAccent.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center,
            ) { Text(pickModeEmoji(mode).trim().ifBlank { "🚚" }, fontSize = 20.sp) }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text(d.optString("no"), fontWeight = FontWeight.Bold, fontSize = 15.sp)
                    if (mode.isNotBlank()) {
                        Box(
                            Modifier.clip(RoundedCornerShape(50)).background(PickAccent.copy(alpha = 0.12f))
                                .padding(horizontal = 8.dp, vertical = 2.dp),
                        ) { Text(mode, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = PickAccent) }
                    }
                }
                Spacer(Modifier.height(2.dp))
                Text(
                    "📍 ${firstValue(d, "locationCode").ifBlank { "—" }}" +
                        if (assigned.isNotBlank()) "   👤 $assigned" else "",
                    fontSize = 11.sp, color = Color.Gray,
                )
                Spacer(Modifier.height(6.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    LinearProgressIndicator(
                        progress = { pct / 100f },
                        modifier = Modifier.weight(1f).height(5.dp).clip(RoundedCornerShape(3.dp)),
                        color = PickAccent,
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("%$pct", fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = Color.Gray)
                }
                if (assigned.isBlank()) {
                    Spacer(Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            Modifier.clip(RoundedCornerShape(50)).background(PendingOrange.copy(alpha = 0.10f))
                                .padding(horizontal = 8.dp, vertical = 3.dp),
                        ) { Text("⏳ Atanmayı bekliyor", fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = PendingOrange) }
                        Spacer(Modifier.weight(1f))
                        Button(
                            onClick = onTake,
                            enabled = !busy,
                            shape = RoundedCornerShape(50),
                            contentPadding = PaddingValues(horizontal = 14.dp, vertical = 4.dp),
                            modifier = Modifier.height(34.dp),
                        ) { Text("✋ Üzerime Al", fontSize = 12.sp, fontWeight = FontWeight.Bold) }
                    }
                }
            }
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
    var scanFilter by remember { mutableStateOf("") }
    // Pick sıralama (hafif wave/rota): bin koduna göre sırala → depoda gereksiz
    // gidip-gelme azalır.
    var sortByBin by remember { mutableStateOf(false) }
    var columns by remember { mutableStateOf(ColumnPrefs.get(context, "pick", GridColumns.pick)) }
    var showColumns by remember { mutableStateOf(false) }
    var actionLine by remember { mutableStateOf<JSONObject?>(null) }
    var showTote by remember { mutableStateOf(false) }
    // ELOG müşteri isteği: bin+item aynı olan satırları tek satırda göster,
    // girilen miktarı alt satırlara dağıt (bkz. LineGrouping/LineGroupCards).
    var merge by remember { mutableStateOf(false) }
    var groupTarget by remember { mutableStateOf<LineGroup?>(null) }
    // ELOG sepet modu: ürün okutunca satırın siparişine atanmış sepeti öner;
    // sepet okutularak doğrulanır (yoksa okutulan sepet siparişe bağlanır).
    var toteMode by remember { mutableStateOf(false) }
    var toteSuggest by remember { mutableStateOf<Pair<JSONObject, String>?>(null) }
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
    // "Place" satırı gereksiz (hedef bin otomatik) — sadece Take satırlarını göster.
    val takeLines = lines.filter { !it.optString("actionType").equals("Place", ignoreCase = true) }

    // ELOG sepet modu: satırın kaynak siparişine atanmış sepeti BC'den sor;
    // sonuç ToteSuggestSheet'i açar (öneri varsa doğrulat, yoksa bağlat).
    fun requestToteSuggestion(line: JSONObject) {
        scope.launch {
            busy = true; status = "Sepet sorgulanıyor..."
            val src = firstValue(line, "sourceNo")
            val r = BcApi.boundAction(context, "picks", no, "toteForOrder",
                JSONObject().apply { put("sourceOrderNo", src) }.toString())
            busy = false
            val lp = if (r.ok) BcApi.scalarValue(r.body) else ""
            toteSuggest = line to lp
        }
    }

    // Donanım tarayıcı: ürünü okut → tek Take satırı otomatik tamamlanır; çok
    // eşleşme listeyi filtreler. Birleştirme açıkken tek eşleşme grubun miktar
    // dialogunu açar; sepet modunda önce sepet önerisi/doğrulaması gelir.
    // Eşleşmeyen okuma bir raf (bin) barkoduysa liste o rafa filtrelenir
    // (ELOG: "rafı okutuyor, alması gerekenleri görüyor").
    DocumentScanHandler(
        enabled = scanLine == null && !showShort && groupTarget == null && toteSuggest == null && !busy,
        lines = takeLines,
        onSingleMatch = { line, _ ->
            scanFilter = ""
            val g = if (merge) groupLines(takeLines, ::pickLineCapacity)
                .firstOrNull { grp -> grp.lines.any { it.optInt("lineNo") == line.optInt("lineNo") } } else null
            when {
                g != null && g.count > 1 -> groupTarget = g
                toteMode -> requestToteSuggestion(line)
                else -> updateLine(line, line.optDouble("quantity"))
            }
        },
        onMultiMatch = { itemNo, _ -> scanFilter = itemNo; status = "PASS: '$itemNo' için birden fazla satır — birini seçin" },
        onNoMatch = { r ->
            val scanned = r.value.trim()
            val bin = takeLines.firstOrNull { it.optString("binCode").equals(scanned, ignoreCase = true) }?.optString("binCode")
            if (!bin.isNullOrBlank()) {
                binFilter = bin
                status = "📍 Raf $bin — bu raftan alınacak satırlar"
            } else status = "⚠️ '${r.itemNo ?: r.value}' bu belgede yok"
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
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (merge) "Gruplar (${displayGroups.size})" else "Satırlar (${displayLines.size}/${takeLines.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.weight(1f))
                FilterChip(selected = toteMode, onClick = { toteMode = !toteMode }, label = { Text("🧺", fontSize = 12.sp) })
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
                    defs = GridColumns.pick, columns = columns, rows = displayLines,
                    modifier = Modifier.weight(1f),
                    isDone = { lineDone(it, LineModule.PICK) },
                    isPartial = { linePartial(it, LineModule.PICK) },
                    onRowClick = { if (!busy) actionLine = it },
                )
            }
        }

        BottomActionBar {
            if (shipLp == null) {
                OutlinedButton(onClick = {
                    action("startShippingLP", """{"lpTemplateCode":"PALLET"}""", "Shipping LP başladı") { r ->
                        if (r.ok) shipLp = BcApi.scalarValue(r.body)
                    }
                }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Start LP") }
                OutlinedButton(onClick = { showTote = true }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("🧺 Tote") }
            } else {
                OutlinedButton(onClick = {
                    val lp = shipLp!!
                    action("stopShippingLP", JSONObject().apply { put("lpNo", lp); put("printLabel", true) }.toString(), "Shipping LP kapandı") { r ->
                        if (r.ok) shipLp = null
                    }
                }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Stop Ship LP") }
            }
            OutlinedButton(onClick = {
                // Paylaşımlı BC lisansı: atama oturumdaki WMS kullanıcısına yazılır.
                scope.launch {
                    val me = BcApi.currentUserId(context)
                    if (me.isNotBlank())
                        action("reassign", JSONObject().apply { put("userId", me); put("reason", "terminalden üstlenildi") }.toString(), "Üzerinize alındı ($me)")
                    else action("assignToMe", "{}", "Bana atandı")
                }
            }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Bana Ata") }
        }
        BottomActionBar {
            val canRegister = com.dynops.bcwms.lib.ActionGuards.hasQuantity(lines)
            Button(
                onClick = { action("register", "{}", "Toplama kaydedildi") },
                enabled = !busy && canRegister,
                modifier = Modifier.fillMaxWidth().height(54.dp),
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
            busy = busy,
            onDismiss = { if (!busy) scanLine = null },
            onVerified = {
                // Codex review Finding 2: busy=true önce set edilir, recompose
                // sırasında diğer "Tara/Tamamla/Short" butonları disabled olur,
                // sheet sonra kapatılır. Tek updateLine coroutine'i garanti.
                if (!busy) {
                    busy = true
                    scanLine = null
                    scope.launch {
                        try {
                            val qty = scanTarget.optDouble("quantity")
                            val body = JSONObject().apply { put("qtyToHandle", qty) }.toString()
                            val actType = scanTarget.optString("activityType").ifBlank { BcEnum.WhseActivityType.PICK }
                            val r = BcApi.patch(context, "pickLines(activityType='$actType',no='$no',lineNo=${scanTarget.optInt("lineNo")})", body)
                            status = if (r.ok) "✅ Doğrulandı + tamamlandı (HTTP ${r.httpCode})"
                                else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                            if (r.ok) reload()
                        } finally {
                            busy = false
                        }
                    }
                }
            },
            onMismatch = {
                status = "❌ Tarama eşleşmedi: beklenen ${scanTarget.optString("itemNo")}, okunan $it"
            },
        )
    }

    val al = actionLine
    if (al != null) {
        PickLineActionSheet(
            line = al,
            onDismiss = { actionLine = null },
            onComplete = { actionLine = null; updateLine(al, al.optDouble("quantity")) },
            onScan = { actionLine = null; scanLine = al },
            onShort = { actionLine = null; shortLine = al; showShort = true },
        )
    }
    // ELOG sepet modu: öneriyi doğrulat ya da yeni sepeti siparişe bağla,
    // sonra satırı tamamla.
    val ts = toteSuggest
    if (ts != null) {
        ToteSuggestSheet(
            line = ts.first,
            expectedLp = ts.second,
            busy = busy,
            onDismiss = { if (!busy) toteSuggest = null },
            onConfirmed = { scannedLp ->
                val line = ts.first
                val expected = ts.second
                toteSuggest = null
                scope.launch {
                    if (expected.isBlank()) {
                        busy = true; status = "Sepet bağlanıyor..."
                        val src = firstValue(line, "sourceNo")
                        val r = BcApi.boundAction(context, "picks", no, "assignTote",
                            JSONObject().apply { put("sourceOrderNo", src); put("lpNo", scannedLp) }.toString())
                        busy = false
                        if (!r.ok) {
                            status = QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                            return@launch
                        }
                    }
                    status = "🧺 $scannedLp ← ${line.optString("itemNo")}"
                    updateLine(line, line.optDouble("quantity"))
                }
            },
        )
    }

    val gt = groupTarget
    if (gt != null) {
        QuantityDialogSheet(
            title = "Toplama Miktarı (${gt.count} satıra dağıtılır)",
            itemNo = gt.itemNo,
            initialQty = gt.totalOutstanding.takeIf { it > 0 } ?: 1.0,
            initialUom = gt.lines.first().optString("unitOfMeasureCode"),
            showLotSerial = false,
            onDismiss = { groupTarget = null },
            onConfirm = { res ->
                groupTarget = null
                scope.launch {
                    busy = true; status = "Grup dağıtılıyor..."
                    val plan = distributeQty(gt, res.quantity, ::pickLineCapacity)
                    var okCount = 0
                    var firstErr: String? = null
                    for ((ln, q) in plan) {
                        val actType = ln.optString("activityType").ifBlank { BcEnum.WhseActivityType.PICK }
                        val body = JSONObject().apply { put("qtyToHandle", q) }.toString()
                        val r = BcApi.patch(context, "pickLines(activityType='$actType',no='$no',lineNo=${ln.optInt("lineNo")})", body)
                        if (r.ok) okCount++ else if (firstErr == null) firstErr = BcApi.errorMessage(r.body)
                    }
                    busy = false
                    status = if (firstErr == null) "PASS: $okCount/${plan.size} satıra dağıtıldı"
                        else "HATA: $okCount/${plan.size} satır yazıldı — $firstErr"
                    reload()
                }
            },
        )
    }
    if (showColumns) {
        ChooseColumnsSheet(GridColumns.pick, columns, onDismiss = { showColumns = false }) { c -> columns = c; ColumnPrefs.save(context, "pick", c); showColumns = false }
    }
    if (showTote) {
        ToteScanSheet(
            title = "Tote'a Topla",
            hint = "Yeniden kullanılabilir tote'u (LP) okut → bu toplamanın kabı olur.",
            onDismiss = { showTote = false },
            onScanned = { lp -> showTote = false; shipLp = lp; status = "🧺 Tote $lp aktif toplama kabı" },
        )
    }
}

/**
 * ELOG sepet modu sheet'i: sistem sipariş için atanmış sepeti önerir
 * ("→ Sepet T-06-K2"); operatör sepeti okutarak doğrular. Sipariş için sepet
 * yoksa okutulan sepet siparişe bağlanır. Yanlış sepet okutulursa hata gösterir
 * ve satır tamamlanmaz.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ToteSuggestSheet(
    line: JSONObject,
    expectedLp: String,
    busy: Boolean,
    onDismiss: () -> Unit,
    onConfirmed: (String) -> Unit,
) {
    var raw by remember { mutableStateOf("") }
    var hint by remember {
        mutableStateOf(
            if (expectedLp.isNotBlank()) "Önerilen sepeti okutarak doğrulayın."
            else "Bu siparişin sepeti yok — bağlanacak sepeti okutun."
        )
    }
    fun submit(value: String) {
        val v = value.trim()
        if (v.isEmpty()) return
        if (expectedLp.isBlank() || v.equals(expectedLp, ignoreCase = true)) onConfirmed(v)
        else hint = "❌ Yanlış sepet: $v — beklenen $expectedLp"
    }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text("🧺 Sepete Koy", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text("${line.optString("itemNo")} — ${line.optString("description")}", fontSize = 12.sp, color = Color.Gray)
        Text("Sipariş: ${firstValue(line, "sourceNo").ifBlank { "-" }} · Miktar: ${line.optDouble("quantity")}", fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(12.dp))
        if (expectedLp.isNotBlank()) {
            Surface(color = Color(0xFFE3F2FD), shape = RoundedCornerShape(10.dp)) {
                Text(
                    "→ Sepet $expectedLp",
                    Modifier.fillMaxWidth().padding(14.dp),
                    fontWeight = FontWeight.Bold, fontSize = 20.sp, color = Color(0xFF1565C0),
                )
            }
            Spacer(Modifier.height(10.dp))
        }
        com.dynops.bcwms.scanner.ScanField(
            "Sepet / LP okut", raw, { raw = it },
            modifier = Modifier.fillMaxWidth(),
            onScanned = { s ->
                val v = com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve(s).value.trim()
                raw = v
                submit(v)
            },
        )
        Spacer(Modifier.height(8.dp))
        Text(hint, fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onDismiss, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Vazgeç") }
            Button(enabled = raw.isNotBlank() && !busy, onClick = { submit(raw) }, modifier = Modifier.weight(1f)) { Text("Onayla") }
        }
        Spacer(Modifier.height(24.dp))
    }
}

/** Bir pick satırına tıklayınca açılan aksiyon sheet'i (grid satırından). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PickLineActionSheet(
    line: JSONObject,
    onDismiss: () -> Unit,
    onComplete: () -> Unit,
    onScan: () -> Unit,
    onShort: () -> Unit,
) {
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text("${line.optString("itemNo")} — ${line.optString("description")}", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Text("Bin: ${line.optString("binCode")} · Miktar: ${line.optDouble("qtyToHandle")} / ${line.optDouble("quantity")}", fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(16.dp))
        Button(onClick = onScan, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("📷 Tara & Tamamla", fontWeight = FontWeight.Bold) }
        Spacer(Modifier.height(8.dp))
        OutlinedButton(onClick = onComplete, modifier = Modifier.fillMaxWidth().height(50.dp)) { Text("✅ Tamamla (tam miktar)") }
        Spacer(Modifier.height(8.dp))
        OutlinedButton(onClick = onShort, modifier = Modifier.fillMaxWidth().height(50.dp)) { Text("⚠ Short (eksik)") }
        Spacer(Modifier.height(24.dp))
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
    busy: Boolean,
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
            OutlinedButton(onClick = onDismiss, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Vazgeç") }
            Button(
                enabled = raw.isNotBlank() && !busy,
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
