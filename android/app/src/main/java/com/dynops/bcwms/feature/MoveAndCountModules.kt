package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
 * Ad-Hoc Move — WI §10.5.
 * Single screen: scan from-bin -> scan item/LP -> scan to-bin -> qty -> Confirm.
 * Posts to movements/Microsoft.NAV.adhoc (warehouse/v2.0, live since v1.0.8.0).
 */
@Composable
fun AdHocMoveModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // ELOG akışı (varsayılan "🧺 LP ile" modu):
    //   1) kaynak bin okut → 2) LP okut → 3) sistem LP içeriğini gösterir →
    //   4) hedef okut: hedef bir LP ise içerik o LP'ye aktarılır (transfer),
    //      bin ise satırlar reclass ile o rafa taşınır.
    var lpFlow by remember { mutableStateOf(true) }
    var fromBin by remember { mutableStateOf("") }
    var lpNo by remember { mutableStateOf("") }
    var binLps by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var lpLines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var target by remember { mutableStateOf("") }
    var targetIsLp by remember { mutableStateOf<Boolean?>(null) }
    var targetLpBin by remember { mutableStateOf("") }
    // Eski ürün-bazlı mod
    var itemOrLp by remember { mutableStateOf("") }
    var toBin by remember { mutableStateOf("") }
    var qty by remember { mutableStateOf("1") }
    var lotNoInput by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    // Son başarılı hareketin kalıcı özeti — PASS sonrası ekranda kart olarak durur.
    var lastMove by remember { mutableStateOf<List<String>?>(null) }

    fun resetLpFlow() { fromBin = ""; lpNo = ""; binLps = emptyList(); lpLines = emptyList(); target = ""; targetIsLp = null; targetLpBin = "" }

    // Kaynak bin'deki LP'leri getir — operatör yazmak yerine dokunup seçer.
    fun loadBinLps(bin: String) {
        val b = bin.trim()
        if (b.isBlank()) return
        scope.launch {
            busy = true; status = "Bindeki LP'ler aranıyor..."
            val safe = b.replace("'", "''")
            val r = BcApi.get(context, "licensePlates?\$filter=binCode eq '$safe'&\$top=50&\$select=no,templateCode,status,binCode")
            binLps = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            busy = false
            status = if (!r.ok) "HATA: LP listesi alınamadı (HTTP ${r.httpCode})"
                else if (binLps.isEmpty()) "⚠️ $b bininde kayıtlı LP yok — LP barkodunu okutabilirsiniz"
                else "TAMAM: $b bininde ${binLps.size} LP — dokunarak seçin"
        }
    }

    fun loadLp(no: String) {
        val t = no.trim()
        if (t.isBlank()) return
        scope.launch {
            busy = true; status = "LP içeriği alınıyor..."
            val h = BcApi.get(context, "licensePlates('$t')")
            if (!h.ok) { busy = false; status = "HATA: LP bulunamadı: $t"; return@launch }
            val l = BcApi.get(context, "licensePlateLines?\$filter=lpNo eq '$t'&\$top=100")
            lpLines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            lpNo = t
            busy = false
            status = if (lpLines.isEmpty()) "⚠️ LP boş görünüyor — yine de taşınabilir"
                else "TAMAM: $t içinde ${lpLines.size} satır"
        }
    }

    // Hedef LP mi bin mi? LP kaydı varsa LP'ye aktarım, yoksa rafa taşıma.
    fun resolveTarget(scanned: String) {
        val t = scanned.trim()
        if (t.isBlank()) return
        scope.launch {
            busy = true
            val r = BcApi.get(context, "licensePlates('$t')")
            targetIsLp = r.ok
            targetLpBin = if (r.ok) JSONObject(r.body).optString("binCode").takeIf { it != "null" } ?: "" else ""
            target = t
            busy = false
            status = if (r.ok) "🧺 Hedef LP: $t${if (targetLpBin.isNotBlank()) " (bin: $targetLpBin)" else ""} — içerik bu LP'ye aktarılacak"
                else "📍 Hedef bin: $t — LP içeriği bu rafa taşınacak"
        }
    }

    // Satırları hedefe reclass et (stok gerçekten taşınsın) — hem bin hedefi
    // hem de farklı bindeki LP hedefi için ortak. Lot izlemeli satırlar LP
    // satırındaki lot ile adHocLot'a gider; lot'suzlar adHoc'a.
    suspend fun postReclass(toBin: String): String {
        for (ln in lpLines) {
            val lot = ln.optString("lotNo").takeIf { it.isNotBlank() && it != "null" } ?: ""
            val body = JSONObject().apply {
                put("fromBin", fromBin.trim()); put("toBin", toBin)
                put("qty", ln.optDouble("quantity"))
                put("itemNo", ln.optString("itemNo")); put("lpNo", lpNo)
                put("userId", BcApi.getLocalUser(context).ifBlank { "MOBILE" })
                if (lot.isNotBlank()) put("lotNo", lot)
            }.toString()
            val action = if (lot.isBlank()) "adHoc" else "adHocLot"
            val r = BcApi.boundAction(context, "movementOps", "", action, body)
            if (!r.ok) {
                val hint = if (lot.isNotBlank() && (r.httpCode == 404 || r.httpCode == 400))
                    " — lot desteği için BC uzantısının güncel publish'i gerekli olabilir" else ""
                return "${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})$hint"
            }
        }
        return ""
    }

    fun confirmLpMove() {
        scope.launch {
            busy = true; status = "Hareket gönderiliyor..."
            if (targetIsLp == true) {
                // Tüm satırları AÇIKÇA gönder: eski publish'te boş linesJson
                // hiçbir satır taşımadan başarı dönüyordu (ParseLines boş çıkışı).
                val linesJson = org.json.JSONArray().apply {
                    lpLines.forEach { ln -> put(JSONObject().apply { put("lineNo", ln.optInt("lineNo")) }) }
                }.toString()
                val r = BcApi.boundAction(context, "licensePlates", lpNo, "transfer",
                    JSONObject().apply { put("targetLpNo", target); put("linesJson", linesJson) }.toString())
                if (!r.ok) {
                    busy = false
                    status = "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                    return@launch
                }
                // Hedef LP farklı bindeyse stok da fiziksel olarak taşınmalı:
                // LP transferi bizim içerik kaydımızdır, reclass'ı ayrıca atıyoruz.
                var reclassNote = ""
                if (targetLpBin.isNotBlank() && !targetLpBin.equals(fromBin.trim(), ignoreCase = true)) {
                    val err = postReclass(targetLpBin)
                    reclassNote = if (err.isBlank()) " + stok $targetLpBin rafına reclass edildi"
                        else " ⚠️ içerik aktarıldı ama stok reclass HATASI: $err"
                }
                busy = false
                status = "TAMAM: $lpNo içeriği $target LP'sine aktarıldı (${lpLines.size} satır)$reclassNote"
                if (!status.contains("⚠️")) {
                    lastMove = buildList {
                        add("🧺 $lpNo → 🧺 $target" + if (targetLpBin.isNotBlank()) " (📍 $targetLpBin)" else "")
                        lpLines.forEach { ln ->
                            add("• ${ln.optString("itemNo")} × ${fmtq(ln.optDouble("quantity"))}" +
                                (ln.optString("lotNo").takeIf { it.isNotBlank() && it != "null" }?.let { " · Lot $it" } ?: ""))
                        }
                    }
                    resetLpFlow()
                }
            } else {
                val err = postReclass(target)
                if (err.isNotBlank()) {
                    busy = false
                    status = "HATA: $err"
                    return@launch
                }
                // Stok taşındı; LP kartının bin'ini de hedefe güncelle (LP raf
                // değiştirdi). Eski publish'te alan salt-okunursa not düşülür.
                val patch = BcApi.patch(context, "licensePlates('$lpNo')",
                    JSONObject().apply { put("binCode", target) }.toString())
                busy = false
                status = if (patch.ok) "TAMAM: LP $lpNo → $target (stok reclass edildi, LP kartı güncellendi)"
                    else "TAMAM: stok $target rafına taşındı · ⚠️ LP kartındaki bin güncellenemedi (HTTP ${patch.httpCode})"
                lastMove = buildList {
                    add("🧺 $lpNo · 📍 ${fromBin.trim()} → 📍 $target")
                    lpLines.forEach { ln ->
                        add("• ${ln.optString("itemNo")} × ${fmtq(ln.optDouble("quantity"))}" +
                            (ln.optString("lotNo").takeIf { it.isNotBlank() && it != "null" }?.let { " · Lot $it" } ?: ""))
                    }
                }
                resetLpFlow()
            }
        }
    }

    Column(Modifier.fillMaxSize().padding(16.dp).verticalScroll(rememberScrollState())) {
        Text("Ad-Hoc Hareket", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            FilterChip(selected = lpFlow, onClick = { lpFlow = true }, label = { Text("🧺 LP ile") })
            FilterChip(selected = !lpFlow, onClick = { lpFlow = false }, label = { Text("📦 Ürün ile") })
        }
        Spacer(Modifier.height(12.dp))

        if (lpFlow) {
            // 1) Kaynak bin — okutulunca o bindeki LP'ler otomatik listelenir.
            ScanField("1) Kaynak Bin okut", fromBin, { fromBin = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
                val b = BarcodeIntentResolver.resolve(it).value
                fromBin = b
                loadBinLps(b)
            })
            Spacer(Modifier.height(8.dp))
            // 2) LP: bindeki LP'lerden DOKUNARAK seç ya da barkod okut.
            if (fromBin.isNotBlank()) {
                if (binLps.isEmpty() && lpLines.isEmpty()) {
                    Button(
                        enabled = !busy,
                        onClick = { loadBinLps(fromBin) },
                        modifier = Modifier.fillMaxWidth().height(44.dp),
                    ) { Text("📋 2) Bu Bindeki LP'leri Listele", fontWeight = FontWeight.SemiBold) }
                    Spacer(Modifier.height(8.dp))
                }
                if (binLps.isNotEmpty() && lpLines.isEmpty()) {
                    Text("2) LP seçin (${binLps.size})", fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    Spacer(Modifier.height(4.dp))
                    binLps.forEach { lp ->
                        val no = lp.optString("no")
                        Card(
                            onClick = { if (!busy) loadLp(no) },
                            modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
                            shape = RoundedCornerShape(12.dp),
                        ) {
                            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text("🧺", fontSize = 18.sp)
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(no, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                    Text(
                                        "${firstValue(lp, "templateCode")} · ${firstValue(lp, "status")}",
                                        fontSize = 11.sp, color = Color.Gray,
                                    )
                                }
                                Text("Seç ›", fontSize = 12.sp, color = Color(0xFF6C5CE7), fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                    Spacer(Modifier.height(6.dp))
                }
                ScanField(if (lpLines.isEmpty()) "…ya da LP barkodu okut" else "2) LP", lpNo, { lpNo = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
                    loadLp(BarcodeIntentResolver.resolve(it).value)
                })
                // Elle yazılan LP için: okuma tetiklenmediğinde içerik bu butonla gelir.
                if (lpNo.isNotBlank() && lpLines.isEmpty()) {
                    Spacer(Modifier.height(6.dp))
                    OutlinedButton(
                        enabled = !busy,
                        onClick = { loadLp(lpNo) },
                        modifier = Modifier.fillMaxWidth().height(44.dp),
                    ) { Text("📥 LP İçeriğini Getir", fontWeight = FontWeight.SemiBold) }
                }
                Spacer(Modifier.height(8.dp))
            }
            // 3) İçerik (sistem gösterir)
            if (lpLines.isNotEmpty()) {
                Text("3) LP içeriği (${lpLines.size})", fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                Spacer(Modifier.height(4.dp))
                lpLines.forEach { ln ->
                    Card(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
                        Column(Modifier.padding(10.dp)) {
                            Text("${ln.optString("itemNo")} × ${ln.optDouble("quantity")}", fontWeight = FontWeight.Medium, fontSize = 13.sp)
                            val extra = listOfNotNull(
                                ln.optString("sourceBinCode").takeIf { it.isNotBlank() && it != "null" }?.let { "📍 $it" },
                                ln.optString("lotNo").takeIf { it.isNotBlank() }?.let { "Lot $it" },
                            ).joinToString(" · ")
                            if (extra.isNotBlank()) Text(extra, fontSize = 11.sp, color = Color.Gray)
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                // 4) Hedef: LP ya da bin
                ScanField("4) Hedef okut (LP veya Bin)", target, { target = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
                    resolveTarget(BarcodeIntentResolver.resolve(it).value)
                })
                if (target.isNotBlank() && targetIsLp == null) {
                    Spacer(Modifier.height(6.dp))
                    Button(
                        enabled = !busy,
                        onClick = { resolveTarget(target) },
                        modifier = Modifier.fillMaxWidth().height(44.dp),
                    ) { Text("🔎 Hedefi Doğrula (LP mi bin mi?)", fontWeight = FontWeight.SemiBold) }
                }
                Spacer(Modifier.height(12.dp))
                Button(
                    enabled = !busy && lpNo.isNotBlank() && target.isNotBlank() && targetIsLp != null,
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    onClick = { confirmLpMove() },
                ) {
                    Text(
                        when {
                            busy -> "Gönderiliyor..."
                            targetIsLp == true -> "✅ İçeriği $target LP'sine Aktar"
                            targetIsLp == false -> "✅ LP'yi $target Rafına Taşı"
                            else -> "✅ Hareketi Onayla"
                        },
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        } else {
            ScanField("Kaynak Bin", fromBin, { fromBin = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
                fromBin = BarcodeIntentResolver.resolve(it).value
            })
            Spacer(Modifier.height(8.dp))
            ScanField("Ürün / LP", itemOrLp, { itemOrLp = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
                itemOrLp = BarcodeIntentResolver.resolve(it).value
            })
            Spacer(Modifier.height(8.dp))
            ScanField("Hedef Bin", toBin, { toBin = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
                toBin = BarcodeIntentResolver.resolve(it).value
            })
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(qty, { qty = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Miktar") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            // Lot izlemeli ürünler için ("You must assign a lot number" hatası).
            ScanField("Lot No (lot izlemeli üründe)", lotNoInput, { lotNoInput = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
                lotNoInput = BarcodeIntentResolver.resolve(it).value
            })
            Spacer(Modifier.height(16.dp))
            Button(
                enabled = !busy && fromBin.isNotBlank() && toBin.isNotBlank() && itemOrLp.isNotBlank(),
                modifier = Modifier.fillMaxWidth().height(52.dp),
                onClick = {
                    scope.launch {
                        busy = true; status = "Hareket gönderiliyor..."
                        val resolved = BarcodeIntentResolver.resolve(itemOrLp)
                        val isLp = resolved.kind == com.dynops.bcwms.scanner.BarcodeKind.Lp
                        val lot = lotNoInput.trim()
                        val body = JSONObject().apply {
                            put("fromBin", fromBin.trim()); put("toBin", toBin.trim())
                            // AL action param is "qty" (not "quantity"); send every param so OData binds them all.
                            put("qty", qty.toDoubleOrNull() ?: 0.0)
                            put("itemNo", if (isLp) "" else itemOrLp.trim())
                            put("lpNo", if (isLp) itemOrLp.trim() else "")
                            put("userId", BcApi.getLocalUser(context).ifBlank { "MOBILE" })
                            if (lot.isNotBlank()) put("lotNo", lot)
                        }.toString()
                        // adHoc is bound to the singleton Setup record (key '') via the movementOps API,
                        // because a fresh bin-to-bin move has no existing movement document to bind to.
                        // Lot girildiyse lot-tracking bağlayan adHocLot action'ı kullanılır.
                        val r = BcApi.boundAction(context, "movementOps", "", if (lot.isBlank()) "adHoc" else "adHocLot", body)
                        busy = false
                        status = if (r.ok) "TAMAM: Hareket kaydedildi (HTTP ${r.httpCode})"
                            else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})" +
                                if (lot.isNotBlank() && (r.httpCode == 404 || r.httpCode == 400))
                                    " — lot desteği için BC publish gerekli olabilir" else ""
                        if (r.ok) {
                            lastMove = buildList {
                                add("📍 ${fromBin.trim()} → 📍 ${toBin.trim()}")
                                add("• ${itemOrLp.trim()} × ${qty.toDoubleOrNull()?.let { fmtq(it) } ?: qty}" +
                                    if (lot.isNotBlank()) " · Lot $lot" else "")
                            }
                            itemOrLp = ""; qty = "1"; lotNoInput = ""
                        }
                    }
                }
            ) { Text(if (busy) "Gönderiliyor..." else "✅ Hareketi Onayla", fontWeight = FontWeight.Bold) }
        }
        Spacer(Modifier.height(12.dp))
        StatusText(status)
        val lm = lastMove
        if (lm != null) {
            Spacer(Modifier.height(8.dp))
            Card(
                Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                colors = CardDefaults.cardColors(containerColor = Color(0xFFE8F5E9)),
            ) {
                Column(Modifier.padding(14.dp)) {
                    Text("✅ Hareket kaydedildi", fontWeight = FontWeight.Bold, fontSize = 15.sp, color = Color(0xFF2E7D32))
                    Spacer(Modifier.height(6.dp))
                    lm.forEach { line -> Text(line, fontSize = 13.sp, color = Color(0xFF1B5E20)) }
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "BC'de iz: Warehouse Entries (bin çifti + lot) · Bin Contents (güncel raf stoğu)",
                        fontSize = 11.sp, color = Color(0xFF558B2F),
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedButton(
                        onClick = { lastMove = null; status = "" },
                        modifier = Modifier.fillMaxWidth().height(42.dp),
                        shape = RoundedCornerShape(50),
                    ) { Text("Tamam — Yeni Hareket") }
                }
            }
        }
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
    var search by remember { mutableStateOf("") }

    fun load() {
        scope.launch {
            loading = true; status = "Sayım sayfaları yükleniyor..."
            val filter = com.dynops.bcwms.ui.buildODataFilter(com.dynops.bcwms.ui.searchClause("no", search))
            val r = BcApi.get(context, "countSheets?\$top=100&\$orderby=createdDateTime desc&\$select=no,locationCode,mode,status,createdDateTime$filter")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Sayım listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "BOŞ: Sayım sayfası yok (HTTP ${r.httpCode})"
                else "TAMAM: ${rows.size} sayfa (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(Unit) { load() }

    var itemDocs by remember { mutableStateOf<Pair<String, Set<String>>?>(null) }
    val sel = selected
    if (sel != null) { CountDocument(no = sel, onBack = { selected = null; load() }); return }

    DocListScanHandler(enabled = true, linesEndpoint = "countSheetLines", docKey = "sheetNo") { item, docs ->
        when { docs.isEmpty() -> status = "⚠️ '$item' sayım sayfasında yok"; docs.size == 1 -> selected = docs.first(); else -> { itemDocs = item to docs; status = "TAMAM: '$item' → ${docs.size} sayfa" } }
    }
    val shownRows = itemDocs?.let { f -> rows.filter { firstValue(it, "no", "batchName") in f.second } } ?: rows

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        Spacer(Modifier.height(8.dp))
        com.dynops.bcwms.ui.DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() }, label = "Sayım no ile ara")
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        if (itemDocs != null) { ScanFilterChip("${itemDocs!!.first} → ${itemDocs!!.second.size} sayfa") { itemDocs = null } }
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(shownRows) { d ->
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
    var scanFilter by remember { mutableStateOf("") }
    var columns by remember { mutableStateOf(ColumnPrefs.get(context, "count", GridColumns.count)) }
    var showColumns by remember { mutableStateOf(false) }

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
            status = if (r.ok) "TAMAM: $okMsg (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            if (r.ok) reload()
        }
    }

    val h = header
    val blind = firstValue(h ?: JSONObject(), "mode").contains("Blind", ignoreCase = true)
    DocumentScanHandler(
        enabled = countLine == null,
        lines = lines,
        onSingleMatch = { line, _ -> scanFilter = ""; countLine = line },
        onMultiMatch = { itemNo, _ -> scanFilter = itemNo; status = "TAMAM: '$itemNo' için birden fazla satır — birini seçin" },
        onNoMatch = { r -> status = "⚠️ '${r.itemNo ?: r.value}' bu sayfada yok" },
    )
    val displayLines = if (scanFilter.isBlank()) lines else lines.filter { matchLinesByBarcode(listOf(it), BarcodeIntentResolver.resolve(scanFilter)).isNotEmpty() }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Sayfa Listesi") }
            DocHeaderCard(
                title = no,
                subtitle = "Lokasyon: ${h?.optString("locationCode") ?: ""} · Mod: ${firstValue(h ?: JSONObject(), "mode")} · ${firstValue(h ?: JSONObject(), "status")}",
                badge = if (blind) "KÖR" else null
            )
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Text("Satırlar (${displayLines.size}/${lines.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { showColumns = true }) { Text("⚙ Kolonlar", fontSize = 12.sp) }
            }
            if (scanFilter.isNotBlank()) { ScanFilterChip(scanFilter) { scanFilter = "" }; Spacer(Modifier.height(4.dp)) }
            // Blind sayımda sistem/fark kolonları gizli.
            val effectiveCols = if (blind) columns.map { if (it.key == "systemQty" || it.key == "variance") it.copy(visible = false) else it } else columns
            LineGrid(
                defs = GridColumns.count, columns = effectiveCols, rows = displayLines,
                modifier = Modifier.weight(1f),
                isDone = { lineDone(it, LineModule.COUNT) },
                onRowClick = { countLine = it },
            )
        }
        BottomActionBar {
            // Generate lines from bin content when the sheet is empty (the count flow needs lines).
            OutlinedButton(onClick = { action("generateLines", "Satırlar üretildi") }, enabled = !busy, modifier = Modifier.weight(1f).height(52.dp)) { Text("➕ Satır Üret") }
            OutlinedButton(onClick = { action("startRecount", "Recount başlatıldı") }, enabled = !busy, modifier = Modifier.weight(1f).height(52.dp)) { Text("⟳ Yeniden Say") }
            Button(onClick = { action("postSheet", "Sayım kaydedildi") }, enabled = !busy, modifier = Modifier.weight(1f).height(52.dp)) { Text("✅ Kaydet", fontWeight = FontWeight.Bold) }
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
                status = if (r.ok) "TAMAM: Sayım kaydedildi (slot $slot) (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                if (r.ok) reload()
            }
        })
    }
    if (showColumns) {
        ChooseColumnsSheet(GridColumns.count, columns, onDismiss = { showColumns = false }) { c -> columns = c; ColumnPrefs.save(context, "count", c); showColumns = false }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CountEntrySheet(line: JSONObject, blind: Boolean, onDismiss: () -> Unit, onConfirm: (slot: Int, qty: Double) -> Unit) {
    var slot by remember { mutableStateOf(1) }
    var qty by remember { mutableStateOf("") }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text("Sayım Gir — ${line.optString("itemNo")}", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text("Bin: ${firstValue(line, "binCode")}" + if (blind) " · KÖR (sistem miktarı gizli)" else " · Sistem: ${fmtq(line.optDouble("systemQty"))}", fontSize = 12.sp, color = Color.Gray)
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
    var selected by remember { mutableStateOf<String?>(null) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var search by remember { mutableStateOf("") }
    var showAll by remember { mutableStateOf(true) }

    fun load() {
        scope.launch {
            loading = true; status = "Hareket belgeleri yükleniyor..."
            val myUser = if (showAll) "" else BcApi.currentUserId(context)
            val filter = buildODataFilter(
                assignedToMeClause(myUser, enabled = !showAll),
                searchClause("no", search),
            )
            val r = BcApi.get(context, "movements?\$top=100&\$orderby=no desc&\$select=no,locationCode,assignedUserId,status$filter")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Hareket listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "BOŞ: Açık yönlendirilmiş hareket belgesi yok (HTTP ${r.httpCode})"
                else "TAMAM: ${rows.size} belge (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(showAll) { load() }

    // Paylaşımlı lisans: belge oturumdaki WMS kullanıcısına atanır.
    fun takeOver(no: String) {
        scope.launch {
            loading = true; status = "Üzerine alınıyor..."
            val me = BcApi.currentUserId(context)
            val r = if (me.isNotBlank())
                BcApi.boundAction(context, "movements", no, "assignTo", JSONObject().apply { put("userId", me) }.toString())
            else BcApi.ApiResult(false, 0, "Oturum kullanıcısı çözülemedi")
            status = if (r.ok) "TAMAM: $no üzerinize alındı ($me)"
                else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})" +
                    if (r.httpCode == 404 || r.httpCode == 400) " — assignTo için BC publish gerekli olabilir" else ""
            load()
        }
    }

    val sel = selected
    if (sel != null) { MovementDocument(no = sel, onBack = { selected = null; load() }); return }

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
        Spacer(Modifier.height(8.dp))
        DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() }, label = "Hareket no ile ara")
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(rows) { d ->
                val no = d.optString("no")
                val assigned = firstValue(d, "assignedUserId")
                Card(onClick = { selected = no }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("🧭 $no", fontWeight = FontWeight.Bold)
                            Text(firstValue(d, "status"), fontSize = 12.sp, color = Color.Gray)
                        }
                        Text(
                            "Lokasyon: ${firstValue(d, "locationCode")} · " +
                                (if (assigned.isBlank()) "⏳ Atanmayı bekliyor" else "👤 Atanan Kullanıcı: $assigned"),
                            fontSize = 12.sp, color = Color.Gray,
                        )
                        if (assigned.isBlank()) {
                            Spacer(Modifier.height(6.dp))
                            Button(
                                onClick = { takeOver(no) },
                                enabled = !loading,
                                modifier = Modifier.fillMaxWidth().height(40.dp),
                            ) { Text("✋ Üzerime Al", fontWeight = FontWeight.Bold, fontSize = 13.sp) }
                        }
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Açık yönlendirilmiş hareket belgesi yok. Ofis, Movement Worksheet'ten \"Create Movement\" ile belge oluşturur.") }
        }
    }
}

/**
 * Movement belgesi: Take/Place satırlarını göster, ürün okutunca (veya satıra
 * dokunup miktar girince) qtyToHandle set edilir; "Register Movement" belgedeki
 * işlenmiş miktarları BC'de kaydeder (Whse.-Activity-Register).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MovementDocument(no: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var qtyLine by remember { mutableStateOf<JSONObject?>(null) }

    fun reload() {
        scope.launch {
            busy = true
            val h = BcApi.get(context, "movements('$no')")
            if (h.ok) header = JSONObject(h.body)
            val l = BcApi.get(context, "movementLines?\$filter=no eq '$no'&\$top=200")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            busy = false
            if (!l.ok && l.httpCode == 400) status = "⚠️ movementLines sunucuda yok — BC publish bekliyor"
        }
    }
    LaunchedEffect(no) { reload() }

    suspend fun patchLine(ln: JSONObject, qty: Double): Boolean {
        val body = JSONObject().apply { put("qtyToHandle", qty) }.toString()
        val r = BcApi.patch(context, "movementLines(activityType='${BcEnum.WhseActivityType.MOVEMENT}',no='$no',lineNo=${ln.optInt("lineNo")})", body)
        if (!r.ok) status = "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
        return r.ok
    }

    // Ürün onayı: o ürünün TÜM satırlarına (Take + Place) tam miktar yazılır.
    fun confirmItem(itemNo: String) {
        scope.launch {
            busy = true; status = "$itemNo işleniyor..."
            var ok = true
            for (ln in lines.filter { it.optString("itemNo") == itemNo }) {
                if (!patchLine(ln, ln.optDouble("qtyOutstanding", ln.optDouble("quantity")))) { ok = false; break }
            }
            busy = false
            if (ok) { status = "TAMAM: $itemNo tam miktar onaylandı"; reload() }
        }
    }

    DocumentScanHandler(
        enabled = qtyLine == null && !busy,
        lines = lines.filter { it.optString("actionType").equals("Take", ignoreCase = true) },
        onSingleMatch = { line, _ -> confirmItem(line.optString("itemNo")) },
        onMultiMatch = { itemNo, _ -> confirmItem(itemNo) },
        onNoMatch = { r -> status = "⚠️ '${r.itemNo ?: r.value}' bu belgede yok" },
    )

    val totalQty = lines.sumOf { it.optDouble("quantity", 0.0) }
    val handledOrStaged = lines.sumOf { maxOf(it.optDouble("qtyHandled", 0.0), it.optDouble("qtyToHandle", 0.0)) }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Hareket Listesi") }
            DocHeaderCard(
                title = "🧭 $no",
                subtitle = "Lokasyon: ${header?.optString("locationCode") ?: ""} · 👤 Atanan Kullanıcı: ${firstValue(header ?: JSONObject(), "assignedUserId").ifBlank { "—" }}",
                percent = if (totalQty > 0) ((handledOrStaged / totalQty) * 100).toInt().coerceIn(0, 100) else 0,
            )
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            Spacer(Modifier.height(6.dp))
            Text("Satırlar (${lines.size}) — ürünü okutun ya da satıra dokunup miktar girin", fontSize = 12.sp, color = Color.Gray)
            Spacer(Modifier.height(6.dp))
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(lines) { ln ->
                    val take = ln.optString("actionType").equals("Take", ignoreCase = true)
                    val toHandle = ln.optDouble("qtyToHandle", 0.0)
                    val qty = ln.optDouble("quantity", 0.0)
                    val done = ln.optDouble("qtyHandled", 0.0) >= qty && qty > 0
                    Card(
                        onClick = { if (!busy) qtyLine = ln },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(10.dp),
                        colors = CardDefaults.cardColors(
                            containerColor = when {
                                done -> Color(0xFFE8F5E9)
                                toHandle >= qty && qty > 0 -> Color(0xFFF3F1FD)
                                else -> MaterialTheme.colorScheme.surface
                            },
                        ),
                    ) {
                        Column(Modifier.padding(10.dp)) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(
                                    "${if (take) "📤 Al" else "📥 Bırak"} · ${ln.optString("itemNo")}",
                                    fontWeight = FontWeight.SemiBold, fontSize = 13.sp,
                                )
                                Text("${fmtq(toHandle)}/${fmtq(qty)}", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                            }
                            Text(
                                "📍 ${ln.optString("binCode")} · ${firstValue(ln, "description")}" +
                                    (firstValue(ln, "lotNo").takeIf { it.isNotBlank() }?.let { " · Lot $it" } ?: ""),
                                fontSize = 11.sp, color = Color.Gray,
                            )
                        }
                    }
                }
                if (lines.isEmpty() && !busy) item { EmptyState("Satır yok.") }
            }
        }
        BottomActionBar {
            val canRegister = lines.any { it.optDouble("qtyToHandle", 0.0) > 0 }
            Button(
                onClick = {
                    scope.launch {
                        busy = true; status = "$no kaydediliyor..."
                        val r = BcApi.boundAction(context, "movements", no, "register", "{}")
                        busy = false
                        status = if (r.ok) "TAMAM: $no kaydedildi — stok taşındı (HTTP ${r.httpCode})"
                            else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                        if (r.ok) reload()
                    }
                },
                enabled = !busy && canRegister,
                modifier = Modifier.fillMaxWidth().height(54.dp),
            ) { Text(if (canRegister) "✅ Hareketi Kaydet" else "Önce satır onaylayın (okut / miktar gir)", fontWeight = FontWeight.Bold) }
        }
    }

    val ql = qtyLine
    if (ql != null) {
        QuantityDialogSheet(
            title = "Miktar (${if (ql.optString("actionType").equals("Take", true)) "Al" else "Bırak"} · 📍 ${ql.optString("binCode")})",
            itemNo = ql.optString("itemNo"),
            initialQty = ql.optDouble("qtyOutstanding", ql.optDouble("quantity")),
            showLotSerial = false,
            onDismiss = { qtyLine = null },
            onConfirm = { res ->
                qtyLine = null
                scope.launch {
                    busy = true
                    if (patchLine(ql, res.quantity)) { status = "TAMAM: Satır güncellendi"; reload() }
                    busy = false
                }
            },
        )
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
