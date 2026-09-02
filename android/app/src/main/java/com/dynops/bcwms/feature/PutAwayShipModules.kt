package com.dynops.bcwms.feature

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.verticalScroll
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
import com.dynops.bcwms.scanner.BarcodeKind
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun shipmentPostCommitted(actionOk: Boolean, verificationHttpCode: Int?): Boolean =
    actionOk || verificationHttpCode == 404

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
    // Diğer modüllerdeki gibi "Bana atanan / Tümü" ayrımı; operatör kendi işini
    // 20 belgelik listede aramak zorunda kalmasın (UAT pa-01).
    var mineOnly by remember { mutableStateOf(true) }
    var myUser by remember { mutableStateOf("") }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            if (myUser.isBlank()) myUser = BcApi.currentUserId(context).trim()
            val filter = com.dynops.bcwms.ui.buildODataFilter(com.dynops.bcwms.ui.searchClause("no", search))
            val page = BcApi.getAllPages(context, "putAways?\$top=100&\$orderby=no desc&\$select=no,locationCode,assignedUserId,status$filter")
            loading = false
            rows = if (page.complete) page.rows else emptyList()
            val shown = if (mineOnly && myUser.isNotBlank())
                rows.count { it.optString("assignedUserId").trim().equals(myUser, true) } else rows.size
            status = when {
                !page.complete -> "HATA: Yerleştirme listesinin tamamı alınamadı. Yenileyin."
                // Arama sonuçsuzsa "hiç belge yok" demek yanıltıcı: belgeler var,
                // aramaya uyan yok (UAT pa-01).
                rows.isEmpty() && search.isNotBlank() -> "BOŞ: '$search' ile eşleşen yerleştirme belgesi bulunamadı"
                rows.isEmpty() -> "BOŞ: Açık yerleştirme belgesi yok"
                shown == 0 && mineOnly -> "BOŞ: Üzerinize atanmış yerleştirme yok — 'Tümü' ile bakabilirsiniz (${rows.size} açık belge)"
                else -> "TAMAM: $shown belge"
            }
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
        onError = { status = it },
    ) { item, docs ->
        when { docs.isEmpty() -> status = "⚠️ '$item' açık yerleştirmede yok"; docs.size == 1 -> selected = docs.first(); else -> { itemDocs = item to docs; status = "TAMAM: '$item' → ${docs.size} belge" } }
    }
    val scoped = if (mineOnly && myUser.isNotBlank())
        rows.filter { it.optString("assignedUserId").trim().equals(myUser, true) } else rows
    val shownRows = itemDocs?.let { f -> scoped.filter { it.optString("no") in f.second } } ?: scoped

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { load() }, enabled = !loading, modifier = Modifier.weight(1f)) { WmsRefreshLabel(loading) }
            FilterChip(selected = mineOnly, onClick = { mineOnly = true; load() }, label = { Text("Bana atanan", fontSize = 12.sp) })
            FilterChip(selected = !mineOnly, onClick = { mineOnly = false; load() }, label = { Text("Tümü", fontSize = 12.sp) })
        }
        Spacer(Modifier.height(8.dp))
        com.dynops.bcwms.ui.DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() })
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        if (itemDocs != null) { ScanFilterChip("${itemDocs!!.first} → ${itemDocs!!.second.size} belge") { itemDocs = null } }
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(shownRows) { d ->
                OperationDocumentCard(
                    title = d.optString("no"),
                    status = firstValue(d, "status"),
                    metadata = "Lokasyon: ${firstValue(d, "locationCode")}\nAtanan: ${firstValue(d, "assignedUserId")}",
                    onClick = { selected = d.optString("no") },
                )
            }
            if (shownRows.isEmpty() && !loading) item {
                EmptyState(
                    when {
                        search.isNotBlank() -> "'$search' ile eşleşen yerleştirme belgesi bulunamadı."
                        mineOnly && rows.isNotEmpty() -> "Üzerinize atanmış yerleştirme yok. 'Tümü' sekmesinden açık belgeleri görebilirsiniz."
                        else -> "Açık yerleştirme belgesi yok."
                    }
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PutAwayDocument(no: String, onBack: () -> Unit) {
    // Donanım Geri tuşu belge ekranından uygulamayı kapatmasın; listeye dönsün.
    androidx.activity.compose.BackHandler { onBack() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var headerLoaded by remember { mutableStateOf(false) }
    var linesComplete by remember { mutableStateOf(false) }
    var myUserId by remember { mutableStateOf("") }
    var adminTestSession by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var guidedPair by remember { mutableStateOf<PutAwayPair?>(null) }
    var scanFilter by remember { mutableStateOf("") }
    var showBulkBin by remember { mutableStateOf(false) }
    var showBatchPlacement by remember { mutableStateOf(false) }
    var showBins by remember { mutableStateOf(false) }
    // Hedef raf/miktar BC'ye yazildiktan sonra belge ekranindan cikilabilir.
    // Hangi satirlarin operatorce hazirlandigi yalniz RAM'de kalirsa geri
    // donuste kart yesil gorunmesine ragmen Kaydet "Once dokunun" diyordu.
    var stagedLineNos by remember(no) { mutableStateOf(PutAwayStagedStore.load(context, no)) }
    LaunchedEffect(no, stagedLineNos) { PutAwayStagedStore.save(context, no, stagedLineNos) }

    fun reload() {
        scope.launch {
            busy = true
            header = null; lines = emptyList(); headerLoaded = false; linesComplete = false
            myUserId = BcApi.currentUserId(context).trim()
            adminTestSession = BcApi.isAdminTestSession(context)
            val h = BcApi.get(context, "putAways('$no')")
            header = if (h.ok) runCatching { JSONObject(h.body) }.getOrNull() else null
            headerLoaded = header != null
            val page = BcApi.getAllPages(context, "putAwayLines?\$filter=no eq '$no'&\$top=100")
            lines = page.rows
            linesComplete = page.complete
            if (page.complete) {
                stagedLineNos = retainExistingPutAwayStagedLineNos(stagedLineNos, lines)
            }
            if (!headerLoaded || !linesComplete) status = "HATA: Belgenin tüm satırları yüklenemedi. Yenileyip tekrar deneyin."
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    suspend fun patchPutAwayLine(line: JSONObject, qty: Double, targetBin: String? = null): Boolean {
        if (!adminTestSession && !canMutateAssignedDocument(header?.optString("assignedUserId").orEmpty(), myUserId)) {
            status = documentOwnershipMessage(header?.optString("assignedUserId").orEmpty(), myUserId)
            return false
        }
        val lineNo = line.optInt("lineNo")
        val actType = BcEnum.decodeOData(rawValue(line, "activityType")).ifBlank { BcEnum.WhseActivityType.PUT_AWAY }
        val compositeKey = "activityType='$actType',no='$no',lineNo=$lineNo"
        val placeWithTarget = targetBin != null && isPutAwayPlaceLine(line)
        val body = JSONObject().apply {
            if (placeWithTarget) {
                put("targetBinCode", targetBin)
                put("qtyToHandle", qty)
            } else {
                put("qtyToHandle", qty)
            }
        }.toString()
        val r = if (placeWithTarget) {
            // Hedef raf değişikliği BC tarafında Validate + Modify ile atomik
            // uygulanır; böylece register önerilen eski rafa geri dönemez.
            BcApi.boundAction(context, "putAwayLines", compositeKey, "setPlacement", body)
        } else {
            BcApi.patch(context, "putAwayLines($compositeKey)", body)
        }
        if (!r.ok) status = QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
        return r.ok
    }

    suspend fun prepareRegisterLines(): Boolean {
        if (!adminTestSession && !canMutateAssignedDocument(header?.optString("assignedUserId").orEmpty(), myUserId)) {
            status = documentOwnershipMessage(header?.optString("assignedUserId").orEmpty(), myUserId)
            return false
        }
        if (!headerLoaded || !linesComplete) {
            status = "HATA: Belge tamamen yüklenmeden kayıt yapılamaz. Yenileyin."
            return false
        }
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

        val desiredByLine = putAwayRegisterQuantityPlan(lines, stagedLineNos)
        val pendingWrites = lines.mapNotNull { ln ->
            // BC yeni yerleştirme satırlarını Qty. to Handle dolu oluşturabilir.
            // Okutulmayan çiftleri 0'a çekmezsek standart register onları da
            // kaydeder ve operatör tek satır yapmasına rağmen belge kaybolur.
            val desiredQty = desiredByLine[ln.optInt("lineNo")] ?: 0.0
            val currentQty = ln.optDouble("qtyToHandle", 0.0)
            if (kotlin.math.abs(currentQty - desiredQty) > 0.00001) ln to desiredQty else null
        }
        var saved = 0
        for ((ln, desiredQty) in pendingWrites) {
            if (!patchPutAwayLine(ln, desiredQty)) {
                status = if (saved > 0) {
                    "UYARI: $saved/${pendingWrites.size} satır hazırlandı; yerleştirme kaydedilmedi. Belge yenileniyor."
                } else {
                    "HATA: Yerleştirme satırları hazırlanamadı. Belge yenileniyor."
                }
                return false
            }
            saved++
        }
        return true
    }

    /** Satırlar BC'ye hazırlandıktan sonra gerçek warehouse register işlemini tamamlar. */
    suspend fun registerPreparedLines(): Boolean {
        status = "Yerleştirme BC'ye kaydediliyor..."
        val r = BcApi.boundAction(context, "putAways", no, "register", "{}")
        if (!r.ok) {
            busy = false
            status = QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
            return false
        }

        // Register çağrısından sonra sunucudaki gerçek kalan satırları bekleyerek al.
        val page = BcApi.getAllPages(context, "putAwayLines?\$filter=no eq '$no'&\$top=100")
        if (!page.complete) {
            lines = page.rows
            linesComplete = false
            busy = false
            stagedLineNos = emptySet()
            status = "HATA: Kayıt yapıldı ancak güncel kalan satırlar alınamadı. Yenileyin."
            return false
        }
        lines = page.rows
        linesComplete = true
        val h2 = BcApi.get(context, "putAways('$no')")
        // Tamamlanan belge BC tarafından listeden kaldırılabilir; 404 bu durumda hataya
        // çevrilmez. Satır kalmadıysa kayıt başarıyla tamamlanmıştır.
        header = if (h2.ok) runCatching { JSONObject(h2.body) }.getOrNull() else null
        headerLoaded = header != null || lines.isEmpty()
        busy = false
        stagedLineNos = emptySet()
        val remaining = lines.sumOf { it.optDouble("qtyOutstanding", 0.0) }
        status = when {
            lines.isEmpty() -> "TAMAM: Tüm satırlar yerleştirildi — belge tamamlandı ✅"
            !h2.ok -> "HATA: Kayıt yapıldı ancak belge durumu alınamadı. Yenileyin."
            remaining > 0 -> "TAMAM: Kısmi kayıt yapıldı — kalan ${fmtNum(remaining)} adet listede"
            else -> "TAMAM: Yerleştirme kaydedildi (HTTP ${r.httpCode})"
        }
        return lines.isEmpty() || h2.ok
    }

    fun register() {
        scope.launch {
            busy = true; status = "Kayıt hazırlanıyor..."
            if (!prepareRegisterLines()) {
                busy = false
                reload()
                return@launch
            }
            registerPreparedLines()
        }
    }

    fun assignToMe() {
        if (myUserId.isBlank()) {
            status = "HATA: WMS kullanıcı kimliği çözülemedi. Oturumu yenileyin."
            return
        }
        scope.launch {
            busy = true
            status = "Belge üzerinize alınıyor..."
            val r = BcApi.boundAction(
                context,
                "putAways",
                no,
                "assignToMe",
                JSONObject().apply { put("userId", myUserId) }.toString(),
            )
            busy = false
            status = if (r.ok) {
                "TAMAM: Yerleştirme belgesi üzerinize alındı"
            } else {
                QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
            }
            if (r.ok) reload()
        }
    }

    // Toplu bin: iadelerde/çok satırda tüm satırları tek seferde aynı bine yerleştir.
    fun bulkAssignBin(bin: String) {
        if (!adminTestSession && !canMutateAssignedDocument(header?.optString("assignedUserId").orEmpty(), myUserId)) {
            status = documentOwnershipMessage(header?.optString("assignedUserId").orEmpty(), myUserId)
            return
        }
        if (!headerLoaded || !linesComplete) {
            status = "HATA: Belge tamamen yüklenmeden toplu atama yapılamaz. Yenileyin."
            return
        }
        scope.launch {
            busy = true; status = "Tüm satırlar → $bin..."
            var okCount = 0
            var allOk = true
            for (ln in lines) {
                val qty = ln.optDouble("qtyToHandle", 0.0).takeIf { it > 0 }
                    ?: ln.optDouble("qtyOutstanding", 0.0).takeIf { it > 0 }
                    ?: ln.optDouble("quantity", 0.0)
                if (patchPutAwayLine(ln, qty, bin)) okCount++ else {
                    allOk = false
                    break
                }
            }
            if (allOk) stagedLineNos = lines.map { it.optInt("lineNo") }.toSet()
            busy = false
            // Ekranda yerleştirmeler alma-koyma çifti olarak sayıldığı için ham
            // satır sayısı (2) kartlardaki sayıyla (1) çelişiyordu; ayrıca BC'nin
            // gerçek gerekçesi genel cümleyle eziliyordu (UAT YR-11).
            val toplam = logicalPutAwayMovementCount(lines)
            val yazilan = if (allOk) toplam else logicalPutAwayMovementCount(lines.take(okCount))
            val sebep = status.removePrefix("HATA:").trim()
            status = when {
                allOk -> "TAMAM: $toplam yerleştirme → $bin"
                okCount > 0 -> "UYARI: $toplam yerleştirmenin $yazilan tanesi yazıldı. " +
                    (if (sebep.isNotBlank()) "Sebep: $sebep " else "") + "Kayıt yapılmadı, belge yenilendi."
                else -> "HATA: Toplu raf ataması yapılamadı. " +
                    (if (sebep.isNotBlank()) "Sebep: $sebep " else "") + "Belge yenilendi."
            }
            reload()
        }
    }

    fun registerBatchAssignments(assignments: Map<String, String>) {
        if (assignments.isEmpty()) {
            status = "HATA: Önce hedef raf ve en az bir LP okutun."
            return
        }
        scope.launch {
            busy = true
            status = "${assignments.size} LP yerleştirmeye hazırlanıyor..."
            val allPairs = groupPutAwayPairs(lines)
            val preparedLineNos = linkedSetOf<Int>()
            var preparedLpCount = 0

            for ((lpNo, targetBin) in assignments) {
                val lpPairs = allPairs.filter { putAwayLpNo(it).equals(lpNo, ignoreCase = true) }
                if (lpPairs.isEmpty()) {
                    busy = false
                    status = "HATA: $lpNo artık bu yerleştirmede bulunamadı. Belge yenileniyor."
                    reload()
                    return@launch
                }

                for (pair in lpPairs) {
                    val qty = pair.place.optDouble("qtyOutstanding", 0.0)
                        .takeIf { it > 0 }
                        ?: pair.place.optDouble("quantity", 0.0)
                    if (qty <= 0) continue
                    val affected = putAwayPairLines(pair.place, lines)
                    var pairPrepared = true
                    for (line in affected) {
                        if (!patchPutAwayLine(line, qty, targetBin)) {
                            pairPrepared = false
                            break
                        }
                        line.put("qtyToHandle", qty)
                        if (isPutAwayPlaceLine(line)) line.put("binCode", targetBin)
                        preparedLineNos.add(line.optInt("lineNo"))
                    }
                    if (!pairPrepared) {
                        busy = false
                        status = "HATA: $lpNo hazırlanamadı; hiçbir yerleştirme kaydedilmedi. Belge yenileniyor."
                        reload()
                        return@launch
                    }
                }
                preparedLpCount++
                status = "$preparedLpCount/${assignments.size} LP hazırlandı..."
            }

            stagedLineNos = stagedLineNos + preparedLineNos
            if (!prepareRegisterLines()) {
                busy = false
                reload()
                return@launch
            }
            registerPreparedLines()
        }
    }

    val h = header
    val assignedUserId = h?.optString("assignedUserId")?.trim().orEmpty()
    val canMutate = headerLoaded && linesComplete &&
        (adminTestSession || canMutateAssignedDocument(assignedUserId, myUserId))
    DocumentScanHandler(
        enabled = canMutate && guidedPair == null && !showBulkBin && !showBatchPlacement && !busy,
        lines = lines,
        matchKeys = listOf("lpNo", "itemNo", "itemReference"),
        onSingleMatch = { line, _ -> scanFilter = ""; guidedPair = groupPutAwayPairs(putAwayPairLines(line, lines)).firstOrNull() },
        onMultiMatch = { value, resolved ->
            if (resolved.kind == BarcodeKind.Lp) {
                val lpLine = lines.firstOrNull { it.optString("lpNo").equals(resolved.value, ignoreCase = true) }
                if (lpLine != null) {
                    scanFilter = ""
                    guidedPair = groupPutAwayPairs(putAwayPairLines(lpLine, lines)).firstOrNull()
                } else status = "⚠️ '${resolved.value}' bu yerleştirmede yok"
            } else {
                scanFilter = value
                status = "TAMAM: '$value' için birden fazla satır — birini seçin"
            }
        },
        onNoMatch = { r -> status = "⚠️ '${r.itemNo ?: r.value}' bu belgede yok" },
    )
    val displayLines = if (scanFilter.isBlank()) lines else lines.filter {
        matchLinesByBarcode(
            listOf(it),
            com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve(scanFilter),
            listOf("lpNo", "itemNo", "itemReference"),
        ).isNotEmpty()
    }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Belge Listesi") }
            // Başlıkta atanan kullanıcı ve ilerleme yoktu; operatör belgenin
            // kimde olduğunu ve ne kadarının bittiğini göremiyordu (UAT pa-02).
            val doneQty = lines.filter { it.optString("actionType").equals("Place", true) }
                .sumOf { it.optDouble("qtyHandled", 0.0) }
            val totalQty = lines.filter { it.optString("actionType").equals("Place", true) }
                .sumOf { it.optDouble("quantity", 0.0) }
            val pct = if (totalQty > 0) (doneQty / totalQty * 100).toInt() else 0
            DocHeaderCard(
                title = no,
                subtitle = "Lokasyon: ${h?.optString("locationCode") ?: ""} · ${firstValue(h ?: JSONObject(), "status")}" +
                    (assignedUserId.takeIf { it.isNotBlank() }?.let { " · Atanan: $it" } ?: " · Atanmamış") +
                    if (headerLoaded) " · %$pct tamamlandı" else "",
            )
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            if (!canMutate && headerLoaded) {
                Text(
                    documentOwnershipMessage(assignedUserId, myUserId),
                    color = bcwmsStatus().danger,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(vertical = 4.dp),
                )
            } else if (adminTestSession && headerLoaded) {
                Text(
                    "Yönetici test oturumu: belge sahipliği kontrolü yalnız bu test için aşıldı.",
                    color = bcwmsStatus().warning,
                    fontSize = 12.sp,
                    modifier = Modifier.padding(vertical = 4.dp),
                )
            }
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
            Text(
                if (lines.any { it.optString("lpNo").isNotBlank() })
                    "Hedef rafı okutun, ardından o rafa bırakacağınız LP'leri peş peşe okutun."
                else
                    "Bir yerleştirmeye dokunun; kaynak raf, ürün ve hedef raf doğrulanır.",
                fontSize = 12.sp,
                color = Color.Gray,
            )
            if (scanFilter.isNotBlank()) { ScanFilterChip(scanFilter) { scanFilter = "" }; Spacer(Modifier.height(4.dp)) }
            Spacer(Modifier.height(8.dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                pairs.forEach { pair -> PutAwayPairCard(pair, staged = pair.place.optInt("lineNo") in stagedLineNos) {
                    if (canMutate && !busy) guidedPair = pair
                } }
                if (pairs.isEmpty() && !busy) EmptyState("Yerleştirilecek satır yok.")
            }
        }
        BottomActionBar {
            // Atamasız belge admin oturumunda da sahipsiz kalmamalı: "Bana Ata"
            // her durumda görünür (UAT pa-06).
            if (headerLoaded && assignedUserId.isBlank()) {
                Button(
                    onClick = { assignToMe() },
                    enabled = !busy && linesComplete && myUserId.isNotBlank(),
                    modifier = Modifier.fillMaxWidth().height(com.dynops.bcwms.ui.wmsPrimaryButtonHeight()),
                ) {
                    Text("👤 Bana Ata", fontWeight = FontWeight.Bold)
                }
            } else {
                val hasLpMovements = lines.any { it.optString("lpNo").isNotBlank() }
                OutlinedButton(
                    onClick = {
                        if (hasLpMovements) showBatchPlacement = true else showBulkBin = true
                    },
                    enabled = !busy && canMutate && lines.isNotEmpty(),
                    modifier = Modifier.weight(1f).height(com.dynops.bcwms.ui.wmsPrimaryButtonHeight()),
                ) {
                    Text(if (hasLpMovements) "📍 Raf + LP Okut" else "📦 Tümünü Bir Bine")
                }
                // Hazırlanan miktar BC'ye yazılıyor; ekrandan çıkıp dönünce
                // oturum hafızası sıfırlanıyor ve düğme pasifleşiyordu — BC'de
                // bekleyen iş kaydedilemez hâle geliyordu (UAT pa-05).
                val serverStaged = lines.any {
                    it.optString("actionType").equals("Place", true) && it.optDouble("qtyToHandle", 0.0) > 0.0
                }
                val canRegister = canMutate && (stagedLineNos.isNotEmpty() || serverStaged)
                Button(
                    onClick = { register() },
                    enabled = !busy && canRegister,
                    modifier = Modifier.weight(1f).height(com.dynops.bcwms.ui.wmsPrimaryButtonHeight()),
                ) {
                    Text(
                        if (canRegister) "✅ Yerleştirmeyi Kaydet" else "Önce dokunun",
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }

    if (showBulkBin) {
        BulkBinSheet(
            locationCode = h?.optString("locationCode") ?: "",
            movementCount = logicalPutAwayMovementCount(lines),
            onDismiss = { showBulkBin = false },
            onConfirm = { bin -> showBulkBin = false; bulkAssignBin(bin) },
        )
    }
    if (showBatchPlacement) {
        BatchLpPutAwaySheet(
            locationCode = h?.optString("locationCode") ?: "",
            pairs = groupPutAwayPairs(lines),
            onDismiss = { showBatchPlacement = false },
            onComplete = { assignments ->
                showBatchPlacement = false
                registerBatchAssignments(assignments)
            },
        )
    }
    if (showBins) {
        BinBrowserSheet(
            locationCode = h?.optString("locationCode") ?: "",
            onDismiss = { showBins = false },
            onSelect = null,
        )
    }
    val gp = guidedPair
    if (gp != null) {
        PutAwayGuidedSheet(
            pair = gp,
            locationCode = h?.optString("locationCode") ?: "",
            onDismiss = { guidedPair = null },
            onConfirm = { bin, qty ->
                guidedPair = null
                if (!canMutate) { status = documentOwnershipMessage(assignedUserId, myUserId); return@PutAwayGuidedSheet }
                scope.launch {
                    busy = true; status = "Satır güncelleniyor..."
                    var okCount = 0
                    val affected = putAwayPairLines(gp.place, lines)
                    for (ln in affected) {
                        if (patchPutAwayLine(ln, qty, bin)) okCount++ else break
                    }
                    if (okCount == affected.size) {
                        stagedLineNos = stagedLineNos + affected.map { it.optInt("lineNo") }
                        // Kart eski hazırlanan miktarı göstermeye devam ediyordu;
                        // satırlar BC'den tazelenip yeni değer hemen yansıtılır.
                        val fresh = BcApi.getAllPages(context, "putAwayLines?\$filter=no eq '$no'&\$top=200")
                        if (fresh.complete) lines = fresh.rows
                        busy = false
                        status = "TAMAM: Satır hazırlandı. Diğer satırları tamamlayın veya Yerleştirmeyi Kaydet'e basın."
                    } else {
                        busy = false
                        // patchPutAwayLine BC'nin gerçek gerekçesini status'e yazmıştı;
                        // burada genel bir cümleyle ezilmemeli (UAT pa-03).
                        val sebep = status.removePrefix("HATA:").trim()
                        status = if (okCount > 0)
                            "UYARI: $okCount/${affected.size} satır yazıldı; kalanı başarısız. " +
                                (if (sebep.isNotBlank()) "Sebep: $sebep " else "") + "Belge yenilendi."
                        else "HATA: Satır güncellenemedi. " +
                            (if (sebep.isNotBlank()) "Sebep: $sebep " else "") + "Belge yenilendi."
                        reload()
                    }
                }
            }
        )
    }
}

private fun putAwayAction(line: JSONObject): String =
    BcEnum.decodeOData(rawValue(line, "actionType")).lowercase()

private fun isPutAwayPlaceLine(line: JSONObject): Boolean {
    val action = putAwayAction(line)
    return action.isBlank() || action.contains("place")
}

private fun putAwayPairKey(line: JSONObject): String {
    val sourceNo = rawValue(line, "sourceNo", "whseDocumentNo")
    val sourceLineNo = rawValue(line, "sourceLineNo", "whseDocumentLineNo")
    val whseDocNo = rawValue(line, "whseDocumentNo")
    val whseDocLineNo = rawValue(line, "whseDocumentLineNo")
    return listOf(
        sourceNo,
        sourceLineNo,
        whseDocNo,
        whseDocLineNo,
        rawValue(line, "itemNo"),
        rawValue(line, "variantCode"),
        rawValue(line, "unitOfMeasureCode"),
        rawValue(line, "lotNo"),
        rawValue(line, "serialNo"),
        rawValue(line, "lpNo"),
    ).joinToString("|")
}

/**
 * Standart BC bütün açık satırlarda Qty. to Handle bırakabilir. Register öncesi
 * yalnız operatörün doğruladığı Take/Place çiftleri pozitif kalmalı, diğerleri
 * sıfırlanmalıdır; aksi halde tek okutma tüm belgeyi kapatır.
 */
internal fun putAwayRegisterQuantityPlan(
    lines: List<JSONObject>,
    stagedLineNos: Set<Int>,
): Map<Int, Double> {
    val stagedQtyByPair = mutableMapOf<String, Double>()
    lines.filter { it.optInt("lineNo") in stagedLineNos }.forEach { line ->
        val qty = line.optDouble("qtyToHandle", 0.0)
        if (qty > 0) stagedQtyByPair[putAwayPairKey(line)] = qty
    }
    return lines.associate { line ->
        line.optInt("lineNo") to (stagedQtyByPair[putAwayPairKey(line)] ?: 0.0)
    }
}

/** Belge kismi kaydedildiyse artik bulunmayan eski satir kimliklerini unut. */
internal fun retainExistingPutAwayStagedLineNos(
    stagedLineNos: Set<Int>,
    lines: List<JSONObject>,
): Set<Int> {
    val existing = lines.mapTo(mutableSetOf()) { it.optInt("lineNo") }
    return stagedLineNos.intersect(existing)
}

/** Belgeye ozel hazirlanmis yerleştirme satirlari; uygulama/ekran gecisinde korunur. */
internal object PutAwayStagedStore {
    private const val PREFS = "bcwms_putaway_staged"

    fun load(context: android.content.Context, no: String): Set<Int> =
        runCatching {
            context.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE)
                .getString("putaway:$no", "").orEmpty()
                .split(',')
                .mapNotNull { it.trim().toIntOrNull() }
                .toSet()
        }.getOrDefault(emptySet())

    fun save(context: android.content.Context, no: String, stagedLineNos: Set<Int>) {
        runCatching {
            val editor = context.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE).edit()
            if (stagedLineNos.isEmpty()) editor.remove("putaway:$no")
            else editor.putString("putaway:$no", stagedLineNos.joinToString(","))
            editor.apply()
        }
    }
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

private fun putAwayLpNo(pair: PutAwayPair): String = pair.place.optString("lpNo").trim()

private fun putAwayLpMatches(pair: PutAwayPair, scannedValue: String): Boolean {
    val needle = scannedValue.trim()
    if (needle.isBlank()) return false
    return putAwayLpNo(pair).equals(needle, ignoreCase = true) ||
        pair.place.optString("lpSscc").trim().equals(needle, ignoreCase = true)
}

private fun groupPutAwayPairs(lines: List<JSONObject>): List<PutAwayPair> {
    val byKey = LinkedHashMap<String, MutableList<JSONObject>>()
    for (ln in lines) byKey.getOrPut(putAwayPairKey(ln)) { mutableListOf() }.add(ln)
    return byKey.values.map { group ->
        val place = group.firstOrNull { isPutAwayPlaceLine(it) } ?: group.first()
        val take = group.firstOrNull { !isPutAwayPlaceLine(it) }
        PutAwayPair(take, place, place.optString("itemNo"), place.optString("description"))
    }
}

/**
 * BC bir fiziksel yerleştirmeyi kaynak Take ve hedef Place olmak üzere iki
 * satırla temsil eder. Operatöre gösterilen adet ham satır sayısı değil,
 * gruplandırılmış depo hareketi sayısıdır.
 */
internal fun logicalPutAwayMovementCount(lines: List<JSONObject>): Int =
    groupPutAwayPairs(lines).size

/** Take/Place çiftini "nereden → nereye" tek kart olarak gösteren, tıklanabilir satır. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PutAwayPairCard(pair: PutAwayPair, staged: Boolean, onClick: () -> Unit) {
    val place = pair.place
    // Kart, BC'de bekleyen hazırlığı da "hazır" saymalı: aksi hâlde ekrandan
    // çıkıp dönen operatör satırı hazırlanmamış sanıyor (UAT pa-05).
    val done = staged || lineDone(place, LineModule.PUTAWAY) || place.optDouble("qtyToHandle", 0.0) > 0.0
    val sourceBin = pair.take?.optString("binCode")?.ifBlank { null } ?: "-"
    val targetBin = place.optString("binCode").ifBlank { "" }
    val lpNo = place.optString("lpNo").trim()
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
                // Hazırlanan miktar ayrı yazılır; eskiden "Miktar" alanına
                // yazılıp kalanla karışıyordu (UAT pa-05).
                (if (toHandle > 0) "Hazırlanan: ${fmtNum(toHandle)} · Kalan: ${fmtNum(outstanding)} $uom"
                 else "Miktar: ${fmtNum(outstanding)} · Kalan: ${fmtNum(outstanding)} $uom").trim(),
                fontSize = 12.sp, color = Color.Gray,
            )
            if (lpNo.isNotBlank())
                Text("LP: $lpNo", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFF4F46E5))
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

/**
 * Saha yerleştirme akışı: hedef raf bir kez okutulur, sonra o rafa giden LP'ler
 * art arda okutulur. Yeni bir raf barkodu mevcut hedefi değiştirir; LP taraması
 * yalnız yerel listeye eklenir ve tüm sunucu kayıtları Tamamla'da tek akışta yapılır.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BatchLpPutAwaySheet(
    locationCode: String,
    pairs: List<PutAwayPair>,
    onDismiss: () -> Unit,
    onComplete: (Map<String, String>) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var currentBin by remember { mutableStateOf("") }
    var scan by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("Önce hedef rafı okutun.") }
    var checkingBin by remember { mutableStateOf(false) }
    var assignments by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    val lpPairs = pairs.filter { putAwayLpNo(it).isNotBlank() }
    val totalLpCount = lpPairs.map(::putAwayLpNo).distinctBy { it.uppercase() }.size

    fun selectBin(raw: String) {
        val candidate = BarcodeIntentResolver.resolve(raw).value.trim()
        if (candidate.isBlank()) return
        scope.launch {
            checkingBin = true
            status = "$candidate rafı kontrol ediliyor..."
            val page = BcApi.getAllPages(context, putAwayExactBinPath(locationCode, candidate))
            val found = page.rows.firstOrNull()
            if (page.complete && found != null) {
                currentBin = found.optString("code").ifBlank { candidate }
                status = "TAMAM: Hedef raf $currentBin — LP'leri peş peşe okutun."
            } else {
                status = if (page.complete)
                    "HATA: $candidate rafı $locationCode lokasyonunda bulunamadı."
                else
                    "HATA: Raf doğrulanamadı; bağlantıyı kontrol edip tekrar okutun."
            }
            scan = ""
            checkingBin = false
        }
    }

    fun scanLp(raw: String) {
        val resolved = BarcodeIntentResolver.resolve(raw)
        if (resolved.kind != BarcodeKind.Lp) {
            selectBin(raw)
            return
        }
        if (currentBin.isBlank()) {
            status = "HATA: LP'den önce hedef rafı okutun."
            scan = ""
            return
        }

        val matchedPairs = lpPairs.filter { putAwayLpMatches(it, resolved.value) }
        val lpNo = matchedPairs.firstOrNull()?.let(::putAwayLpNo).orEmpty()
        if (lpNo.isBlank()) {
            status = "HATA: ${resolved.value} bu yerleştirme belgesinde yok."
            scan = ""
            return
        }

        val qualityStatuses = matchedPairs.map {
            it.place.optString("lpQualityStatus").trim().lowercase()
        }
        if (qualityStatuses.any { it == "inprogress" || it == "open" }) {
            status = "HATA: $lpNo kalite onayı bekliyor; karantina gözünde kalmalı."
            scan = ""
            return
        }
        if (qualityStatuses.any { it == "failed" }) {
            val quarantineBin = matchedPairs.firstNotNullOfOrNull {
                it.place.optString("lpQualityBin").trim().takeIf(String::isNotBlank)
            }.orEmpty()
            if (quarantineBin.isBlank() || !currentBin.equals(quarantineBin, ignoreCase = true)) {
                status = "HATA: $lpNo reddedildi; ${quarantineBin.ifBlank { "tanımlı ret gözüne" }} taşınmalı."
                scan = ""
                return
            }
        }

        val oldBin = assignments[lpNo]
        assignments = assignments + (lpNo to currentBin)
        status = if (oldBin == null)
            "TAMAM: $lpNo → $currentBin (${assignments.size}/$totalLpCount LP)"
        else if (oldBin.equals(currentBin, ignoreCase = true))
            "UYARI: $lpNo zaten $currentBin için okutuldu."
        else
            "TAMAM: $lpNo hedefi $oldBin yerine $currentBin olarak değiştirildi."
        scan = ""
    }

    com.dynops.bcwms.ui.SheetScaffold(
        onDismiss = onDismiss,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp),
    ) {
        Text("Raf Bazlı Toplu LP Yerleştirme", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text(
            "Hedef rafı okutun, ardından bu rafa bırakacağınız LP'leri peş peşe okutun. Raf değişince yeni rafı okutmanız yeterli.",
            fontSize = 12.sp,
            color = Color.Gray,
        )
        Spacer(Modifier.height(12.dp))

        Surface(
            shape = RoundedCornerShape(12.dp),
            color = if (currentBin.isBlank()) Color(0xFFEA580C).copy(alpha = 0.12f)
            else Color(0xFF16A34A).copy(alpha = 0.12f),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(Modifier.padding(14.dp)) {
                Text("AKTİF HEDEF RAF", fontSize = 11.sp, color = Color.Gray)
                Text(currentBin.ifBlank { "Önce raf okutun" }, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text("${assignments.size}/$totalLpCount LP hazır", fontSize = 12.sp, color = Color.Gray)
            }
        }

        Spacer(Modifier.height(12.dp))
        ScanField(
            label = if (currentBin.isBlank()) "Hedef raf okut" else "LP veya yeni hedef raf okut",
            value = scan,
            onValueChange = { scan = it },
            modifier = Modifier.fillMaxWidth(),
            enabled = !checkingBin,
            onScanned = { raw ->
                val resolved = BarcodeIntentResolver.resolve(raw)
                if (resolved.kind == BarcodeKind.Lp) scanLp(raw) else selectBin(raw)
            },
        )
        Spacer(Modifier.height(8.dp))
        StatusText(status)

        if (assignments.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            assignments.entries.toList().asReversed().take(6).forEach { (lpNo, bin) ->
                Text("✓ $lpNo → $bin", fontSize = 13.sp, modifier = Modifier.padding(vertical = 2.dp))
            }
            if (assignments.size > 6)
                Text("+ ${assignments.size - 6} LP daha", fontSize = 12.sp, color = Color.Gray)
        }

        Spacer(Modifier.height(16.dp))
        Button(
            enabled = assignments.isNotEmpty() && !checkingBin,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            onClick = { onComplete(assignments) },
        ) {
            Text("✅ Okutulan ${assignments.size} LP'yi Yerleştir", fontWeight = FontWeight.Bold)
        }
        TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text("Vazgeç") }
        Spacer(Modifier.height(20.dp))
    }
}

private fun odataLiteral(value: String): String = value.replace("'", "''")

internal enum class PutAwayTargetDecision { EMPTY, NOT_FOUND, SUGGESTED, ALTERNATIVE }

/** BC'nin önerdiği raf bilgi amaçlıdır; aynı lokasyondaki başka geçerli raf kabul edilir. */
internal fun decidePutAwayTarget(
    selectedBin: String,
    suggestedBin: String,
    existsAtLocation: Boolean,
): PutAwayTargetDecision {
    if (selectedBin.isBlank()) return PutAwayTargetDecision.EMPTY
    if (!existsAtLocation) return PutAwayTargetDecision.NOT_FOUND
    return if (selectedBin.equals(suggestedBin, ignoreCase = true))
        PutAwayTargetDecision.SUGGESTED
    else
        PutAwayTargetDecision.ALTERNATIVE
}

/** Bottom sheet: scan/enter target bin (with "Öner" = suggestBin) + qty. */
private enum class PutAwayStep { LP, SOURCE_BIN, ITEM, TARGET_BIN, QTY }

/**
 * Yönlendirilmiş yerleştirme: kaynak raf → ürün → hedef raf → miktar.
 *
 * Kaynak raf ve ürün belgedeki beklenen değerle karşılaştırılır; uyuşmazsa adım
 * İLERLEMEZ (sert blok). Hedef raf ise BC'nin önerisine mahkum değildir: operatör
 * aynı lokasyondaki geçerli herhangi bir rafa yerleştirebilir.
 *
 * Kaynak raf yalnızca BC'nin Take satırı bir bin veriyorsa sorulur. Hedef raf
 * önerisi operatöre gösterilir ama yalnız seçilen rafın lokasyonda varlığı aranır.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PutAwayGuidedSheet(
    pair: PutAwayPair,
    locationCode: String,
    onDismiss: () -> Unit,
    onConfirm: (bin: String, qty: Double) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val place = pair.place
    val pairLines = listOfNotNull(pair.take, place)
    val expectedSource = pair.take?.optString("binCode").orEmpty().trim()
    val expectedTarget = place.optString("binCode").trim()
    val expectedItem = place.optString("itemNo").trim()
    val expectedLp = place.optString("lpNo").trim()

    val steps = buildList {
        if (expectedLp.isNotBlank()) add(PutAwayStep.LP)
        if (expectedSource.isNotBlank()) add(PutAwayStep.SOURCE_BIN)
        add(PutAwayStep.ITEM)
        add(PutAwayStep.TARGET_BIN)
        add(PutAwayStep.QTY)
    }
    var step by remember(place.optInt("lineNo")) { mutableStateOf(steps.first()) }
    var scan by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    var targetBin by remember { mutableStateOf("") }
    var hint by remember { mutableStateOf("") }
    var showBinList by remember { mutableStateOf(false) }
    var validatingTargetBin by remember { mutableStateOf(false) }

    val outstanding = place.optDouble("qtyOutstanding", Double.NaN)
    val handled = place.optDouble("qtyHandled", 0.0)
    val prefill = when {
        !outstanding.isNaN() && outstanding > 0 -> outstanding
        place.optDouble("qtyToHandle", 0.0) > 0 -> place.optDouble("qtyToHandle", 0.0)
        else -> place.optDouble("quantity", 0.0)
    }
    var qty by remember { mutableStateOf(fmtNum(prefill)) }

    // Bin barkodu bazen ham metin, bazen resolver'dan geçmiş değerdir; ikisini de dene.
    fun binEquals(raw: String, expected: String): Boolean {
        val candidates = listOf(raw.trim(), BarcodeIntentResolver.resolve(raw).value.trim())
        return candidates.any { it.isNotBlank() && it.equals(expected, ignoreCase = true) }
    }

    fun itemMatches(raw: String): Boolean {
        val resolved = BarcodeIntentResolver.resolve(raw)
        if (matchLinesByBarcode(pairLines, resolved, listOf("itemNo", "itemReference", "gtin")).isNotEmpty()) return true
        val needle = (resolved.itemNo ?: resolved.value).trim()
        return needle.isNotBlank() && needle.equals(expectedItem, ignoreCase = true)
    }

    fun lpMatches(raw: String): Boolean {
        val resolved = BarcodeIntentResolver.resolve(raw)
        val needle = resolved.value.trim().ifBlank { raw.trim() }
        return needle.equals(expectedLp, ignoreCase = true)
    }

    suspend fun targetBinExists(binCode: String): Boolean? {
        val safeLocation = odataLiteral(locationCode)
        val safeBin = odataLiteral(binCode)
        val filter = if (safeLocation.isNotBlank())
            "locationCode eq '$safeLocation' and code eq '$safeBin'"
        else
            "code eq '$safeBin'"
        val page = BcApi.getAllPages(
            context,
            "bins?\$filter=$filter&\$select=code&\$top=1",
        )
        if (!page.complete) return null
        return page.rows.any { it.optString("code").equals(binCode, ignoreCase = true) }
    }

    fun advance() {
        error = ""
        scan = ""
        step = steps[(steps.indexOf(step) + 1).coerceAtMost(steps.lastIndex)]
    }

    fun submit(raw: String) {
        val v = raw.trim()
        if (v.isBlank()) return
        when (step) {
            PutAwayStep.LP ->
                if (lpMatches(v)) advance()
                else error = "❌ Yanlış LP. Beklenen: $expectedLp · Okuttuğunuz: $v"
            PutAwayStep.SOURCE_BIN ->
                if (binEquals(v, expectedSource)) advance()
                else error = "❌ Yanlış raf. Beklenen: $expectedSource · Okuttuğunuz: $v"
            PutAwayStep.ITEM ->
                if (itemMatches(v)) advance()
                else error = "❌ Yanlış ürün. Beklenen: $expectedItem · Okuttuğunuz: $v"
            PutAwayStep.TARGET_BIN -> {
                if (validatingTargetBin) return
                val selectedBin = BarcodeIntentResolver.resolve(v).value.trim().ifBlank { v }
                validatingTargetBin = true
                error = ""
                hint = "Raf doğrulanıyor..."
                scope.launch {
                    val exists = targetBinExists(selectedBin)
                    when {
                        exists == null -> {
                            hint = ""
                            error = "❌ Raf doğrulanamadı. Bağlantıyı kontrol edip tekrar deneyin."
                        }
                        decidePutAwayTarget(selectedBin, expectedTarget, exists) in setOf(
                            PutAwayTargetDecision.SUGGESTED,
                            PutAwayTargetDecision.ALTERNATIVE,
                        ) -> {
                            targetBin = selectedBin
                            hint = ""
                            advance()
                        }
                        else -> {
                            hint = ""
                            error = "❌ $selectedBin rafı $locationCode lokasyonunda bulunamadı."
                        }
                    }
                    validatingTargetBin = false
                }
            }
            PutAwayStep.QTY -> Unit
        }
    }

    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = PaddingValues(20.dp)) {
        if (showBinList) {
            TextButton(onClick = { showBinList = false }) { Text("‹ Geri") }
            BinListContent(
                locationCode = locationCode,
                onSelect = { picked -> showBinList = false; submit(picked) },
            )
        } else {
            val stepNo = steps.indexOf(step) + 1
            Text("Yerleştirme · Adım $stepNo/${steps.size}", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Text(
                "${pair.itemNo}${if (pair.description.isNotBlank()) " — ${pair.description}" else ""}",
                fontSize = 12.sp, color = Color.Gray,
            )
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                BinPill("📤 Al", expectedSource.ifBlank { "-" }, Color(0xFF64748B))
                Text("  →  ", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color(0xFF6366F1))
                BinPill(
                    if (targetBin.isBlank() && expectedTarget.isNotBlank()) "📥 Öneri" else "📥 Koy",
                    targetBin.ifBlank { expectedTarget.ifBlank { "Okutun" } },
                    Color(0xFF16A34A),
                )
            }
            Spacer(Modifier.height(14.dp))

            when (step) {
                PutAwayStep.LP -> {
                    Text("Palet/LP etiketini okutun", fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                    Text("Doğru fiziksel paleti yerleştirdiğinizi teyit eder. Beklenen: $expectedLp", fontSize = 12.sp, color = Color.Gray)
                }
                PutAwayStep.SOURCE_BIN -> {
                    Text("Bulunduğunuz rafı okutun", fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                    Text("Doğru raftan aldığınızı teyit eder. Beklenen: $expectedSource", fontSize = 12.sp, color = Color.Gray)
                }
                PutAwayStep.ITEM -> {
                    Text("Ürünü okutun", fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                    Text("Doğru ürünü aldığınızı teyit eder. Beklenen: $expectedItem", fontSize = 12.sp, color = Color.Gray)
                }
                PutAwayStep.TARGET_BIN -> {
                    Text("Koyacağınız rafı okutun", fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                    Text(
                        if (expectedTarget.isNotBlank())
                            "Önerilen: $expectedTarget · Aynı lokasyondaki başka bir rafı da seçebilirsiniz."
                        else
                            "Aynı lokasyondaki geçerli bir rafı okutun veya listeden seçin.",
                        fontSize = 12.sp, color = Color.Gray,
                    )
                }
                PutAwayStep.QTY -> {
                    Text("Miktarı onaylayın", fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                    Text(
                        buildString {
                            append("Hedef raf: $targetBin")
                            if (!outstanding.isNaN()) append(" · Kalan: ${fmtNum(outstanding)}")
                            if (handled > 0) append(" · Konan: ${fmtNum(handled)}")
                        },
                        fontSize = 12.sp, color = Color.Gray,
                    )
                }
            }
            Spacer(Modifier.height(10.dp))

            if (step == PutAwayStep.QTY) {
                OutlinedTextField(
                    qty,
                    { qty = normalizeQtyInput(it) },
                    label = { Text("Miktar") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            } else {
                ScanField(
                    label = when (step) {
                        PutAwayStep.LP -> "LP okut"
                        PutAwayStep.ITEM -> "Ürün okut"
                        else -> "Raf okut"
                    },
                    value = scan,
                    onValueChange = { scan = it },
                    modifier = Modifier.fillMaxWidth(),
                    onScanned = { submit(it) },
                )
                Spacer(Modifier.height(6.dp))
                Button(
                    onClick = { submit(scan) },
                    enabled = scan.isNotBlank() && !validatingTargetBin,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (validatingTargetBin) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                    }
                    Text(if (validatingTargetBin) "Raf kontrol ediliyor" else "Doğrula")
                }
            }

            if (step == PutAwayStep.TARGET_BIN) {
                Spacer(Modifier.height(6.dp))
                OutlinedButton(onClick = { showBinList = true }, modifier = Modifier.fillMaxWidth()) {
                    Text("📍 Bin Listesinden Seç")
                }
                if (expectedTarget.isBlank()) {
                    Spacer(Modifier.height(6.dp))
                    OutlinedButton(onClick = {
                        scope.launch {
                            hint = "Bin öneriliyor..."
                            val body = JSONObject().apply {
                                put("itemNo", expectedItem)
                                put("qty", qty.toDoubleOrNull() ?: 0.0)
                                put("locationCode", locationCode)
                            }.toString()
                            val r = BcApi.post(context, "putAways('${place.optString("no")}')/Microsoft.NAV.suggestBin", body)
                            hint = if (r.ok) {
                                val suggested = BcApi.scalarValue(r.body)
                                if (suggested.isNotBlank()) { scan = suggested; "Önerilen bin: $suggested — okutup doğrulayın" }
                                else "Öneri boş döndü"
                            } else "Bin önerisi alınamadı. Bin listesinden seçin veya yenileyin."
                        }
                    }, modifier = Modifier.fillMaxWidth()) { Text("🎯 Bin Öner") }
                }
                if (hint.isNotBlank()) { Spacer(Modifier.height(4.dp)); Text(operatorFacingStatus(hint), fontSize = 12.sp, color = Color.Gray) }
            }

            if (error.isNotBlank()) {
                Spacer(Modifier.height(10.dp))
                Surface(shape = RoundedCornerShape(10.dp), color = Color(0xFFDC2626).copy(alpha = 0.12f)) {
                    Text(
                        error,
                        Modifier.fillMaxWidth().padding(12.dp),
                        color = Color(0xFFB91C1C),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }

            Spacer(Modifier.height(16.dp))
            if (step == PutAwayStep.QTY) {
                // Düğme eskiden boş/0 miktarda PASİF idi: operatör basıyor,
                // hiçbir şey olmuyor ve neden olmadığını göremiyordu. Artık
                // basılabiliyor ve eksik olan şeyi Türkçe söylüyor (UAT pa-03).
                Button(
                    enabled = true,
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        val entered = qty.toDoubleOrNull()
                        val kalan = if (outstanding.isNaN()) null else outstanding
                        error = when {
                            targetBin.isBlank() -> "Önce koyacağınız rafı okutun."
                            qty.isBlank() -> "Miktar girin."
                            entered == null -> "Miktar sayı olmalı. Örnek: 12 veya 12.5"
                            entered <= 0 -> "Miktar sıfırdan büyük olmalı."
                            kalan != null && entered > kalan ->
                                "Kalan miktardan fazla giremezsiniz (kalan: ${fmtNum(kalan)})."
                            else -> ""
                        }
                        if (error.isBlank()) onConfirm(targetBin, entered ?: 0.0)
                    },
                ) { Text("✅ Yerleştirmeyi Onayla", fontWeight = FontWeight.Bold) }
            }
            TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text("Vazgeç") }
            Spacer(Modifier.height(24.dp))
        }
    }
}

/** Toplu bin sheet: bir bin okut/gir → belgedeki tüm yerleştirmelere uygula. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BulkBinSheet(locationCode: String, movementCount: Int, onDismiss: () -> Unit, onConfirm: (bin: String) -> Unit) {
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
        Text("$movementCount yerleştirmenin hepsi seçilen bine atanır.", fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(12.dp))
        ScanField("Hedef Bin", bin, { bin = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            bin = BarcodeIntentResolver.resolve(it).value
        })
        Spacer(Modifier.height(8.dp))
        OutlinedButton(onClick = { showBinList = true }, modifier = Modifier.fillMaxWidth()) { Text("📍 Bin Listesinden Seç") }
        Spacer(Modifier.height(16.dp))
        Button(enabled = bin.isNotBlank(), modifier = Modifier.fillMaxWidth(), onClick = { onConfirm(bin.trim()) }) {
            Text("Tümüne Uygula ($movementCount)")
        }
        Spacer(Modifier.height(24.dp))
        }
    }
}

internal fun putAwayBinListPath(locationCode: String): String =
    if (locationCode.isNotBlank()) {
        "bins?\$filter=locationCode eq '${odataLiteral(locationCode)}'&\$orderby=code&\$top=1000"
    } else {
        "bins?\$orderby=code&\$top=1000"
    }

/**
 * Bin kodu ilk listede bulunmasa bile BC'de lokasyon + tam kod ile aranır.
 * Tam eşitlik, benzer adlı yanlış bir rafın seçilmesini engeller.
 */
internal fun putAwayExactBinPath(locationCode: String, binCode: String): String {
    val safeBin = odataLiteral(binCode.trim())
    // Tam eşitlik yanında KISMİ kod da aranır: operatör "Y.G03" yazdığında
    // Y.G03.13 bulunabilmeli. Depoda yüzlerce raf olabildiği için yalnız yerel
    // listeye bakmak yetmiyordu.
    val match = "(code eq '$safeBin' or startswith(code,'$safeBin'))"
    val filter = if (locationCode.isNotBlank()) {
        "locationCode eq '${odataLiteral(locationCode)}' and $match"
    } else {
        match
    }
    return "bins?\$filter=$filter&\$orderby=code&\$top=50"
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
    var exactMatch by remember(locationCode) { mutableStateOf<JSONObject?>(null) }
    var exactLoading by remember(locationCode) { mutableStateOf(false) }
    var exactLookupComplete by remember(locationCode) { mutableStateOf(false) }
    var exactLookupError by remember(locationCode) { mutableStateOf("") }
    // Sunucudan gelen kısmi eşleşmeler (yerel sayfada olmayan raflar).
    var serverMatches by remember(locationCode) { mutableStateOf<List<JSONObject>>(emptyList()) }

    fun loadBins() {
        scope.launch {
            loading = true
            // $top yalnızca sayfa boyutudur; getAllPages @odata.nextLink'leri
            // takip ederek ilk 200 sonrasını da eksiksiz alır.
            val page = BcApi.getAllPages(context, putAwayBinListPath(locationCode))
            bins = if (page.complete) page.rows else emptyList()
            status = if (page.complete) "TAMAM: ${bins.size} bin" else "HATA: Bin listesinin tamamı alınamadı. Yenileyin."
            loading = false
        }
    }

    LaunchedEffect(locationCode) { loadBins() }
    val exactQuery = search.trim()
    LaunchedEffect(locationCode, exactQuery) {
        exactMatch = null
        serverMatches = emptyList()
        exactLookupComplete = false
        exactLookupError = ""
        exactLoading = false
        if (exactQuery.isBlank()) return@LaunchedEffect

        // Klavye/barkod okuyucu girişi tamamlanmadan her karakterde BC'ye gitme.
        delay(250)
        exactLoading = true
        val page = BcApi.getAllPages(
            context,
            putAwayExactBinPath(locationCode, exactQuery),
        )
        exactLoading = false
        exactLookupComplete = page.complete
        if (!page.complete) {
            exactLookupError = "HATA: Raf sunucuda doğrulanamadı. Bağlantıyı kontrol edip tekrar deneyin."
        } else {
            serverMatches = page.rows
            exactMatch = page.rows.firstOrNull {
                it.optString("code").equals(exactQuery, ignoreCase = true) &&
                    // Lokasyon zaten server-side OData filtresinde zorunlu. Bazı
                    // eski bins API sürümleri locationCode alanını yanıta koymaz.
                    (it.optString("locationCode").isBlank() || locationCode.isBlank() ||
                        it.optString("locationCode").equals(locationCode, ignoreCase = true))
            }
        }
    }
    OutlinedTextField(
        value = search,
        onValueChange = { search = it },
        label = { Text("Bin ara") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(6.dp))
    val localMatches = bins.filter {
        val q = exactQuery
        q.isBlank() ||
            it.optString("code").contains(q, ignoreCase = true) ||
            it.optString("description").contains(q, ignoreCase = true) ||
            it.optString("zoneCode").contains(q, ignoreCase = true) ||
            it.optString("warehouseClassCode").contains(q, ignoreCase = true)
    }
    // Server'dan bulunan tam eşleşmeyi, ilk liste sayfasında olmasa bile
    // en üste ekle; aynı raf yerel listede varsa ikinci kez gösterme.
    val shown = buildList {
        exactMatch?.let { add(it) }
        // Sunucudan gelen kısmi eşleşmeleri de göster (yerel sayfada olmayabilir).
        addAll(serverMatches.filterNot { sm ->
            sm.optString("code").equals(exactMatch?.optString("code").orEmpty(), ignoreCase = true) ||
                localMatches.any { it.optString("code").equals(sm.optString("code"), ignoreCase = true) }
        })
        addAll(localMatches.filterNot { local ->
            exactMatch?.let { exact ->
                val localLocation = local.optString("locationCode")
                val exactLocation = exact.optString("locationCode")
                local.optString("code").equals(exact.optString("code"), ignoreCase = true) &&
                    (localLocation.isBlank() || exactLocation.isBlank() ||
                        localLocation.equals(exactLocation, ignoreCase = true))
            } == true
        })
    }
    val visibleStatus = when {
        loading -> "Binler yükleniyor..."
        exactLoading -> "Raf sunucuda aranıyor..."
        exactLookupError.isNotBlank() -> exactLookupError
        exactQuery.isNotBlank() && exactLookupComplete && shown.isEmpty() ->
            "BOŞ: '$exactQuery' rafı ${if (locationCode.isBlank()) "bu ortamda" else "$locationCode lokasyonunda"} bulunamadı."
        exactMatch != null -> "TAMAM: ${exactMatch!!.optString("code")} rafı sunucuda bulundu"
        else -> status
    }
    StatusText(visibleStatus)
    Spacer(Modifier.height(8.dp))
    LazyColumn(Modifier.heightIn(max = 360.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        items(shown) { b ->
            val code = b.optString("code")
            val block = b.optString("blockMovement")
            val blocked = block.equals("All", true) || block.equals("Inbound", true)
            Card(
                modifier = Modifier.fillMaxWidth().then(
                    if (!blocked && onSelect != null) Modifier.clickable { onSelect(code) }
                    else Modifier
                ),
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
                            "Bölge ${b.optString("zoneCode").ifBlank { "-" }}",
                            "Tip ${b.optString("binTypeCode").ifBlank { "-" }}",
                            "Sıra ${b.optInt("binRanking", 0)}",
                            if (block.isBlank() || block == " ") "Blok yok" else "Blok $block",
                        ).filter { it.isNotBlank() }.joinToString(" · "),
                        fontSize = 12.sp,
                        color = Color.Gray,
                    )
                }
            }
        }
        if (
            shown.isEmpty() &&
            !loading &&
            !exactLoading &&
            exactLookupError.isBlank() &&
            (exactQuery.isBlank() || exactLookupComplete)
        ) {
            item { EmptyState("Uygun bin bulunamadı.") }
        }
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
    val tabs = if (showSo) {
        listOf(
            // Dar el terminalinde ortak "Ambar" öneki üç sekmenin metnini
            // kesiyor ve ilk iki sekmeyi aynı gösteriyordu. Ekran başlığı zaten
            // Sevkiyat olduğu için kısa, birbirinden ayırt edilebilir adlar kullan.
            WmsGlyph.PICKING to "Toplama",
            WmsGlyph.SHIPPING to "Sevkiyat",
            WmsGlyph.ENTRIES to "Sipariş",
        )
    } else {
        listOf(WmsGlyph.PICKING to "Toplama", WmsGlyph.SHIPPING to "Sevkiyat")
    }
    if (tab >= tabs.size) tab = 0

    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab) {
            tabs.forEachIndexed { i, item ->
                Tab(selected = tab == i, onClick = { tab = i }, text = { WmsTabLabel(item.first, item.second) })
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
            if (!canLoadAssignedOnlyList(showAll, myUser)) {
                rows = emptyList(); loading = false
                status = "HATA: Depo kullanıcısı doğrulanamadı. Yeniden giriş yapın."
                return@launch
            }
            val filter = buildODataFilter(
                assignedToMeClause(myUser, enabled = !showAll),
                searchClause("no", search),
            )
            val page = BcApi.getAllPagesWithStandardFallback(context, "picks?\$top=100&\$orderby=no desc&\$select=no,locationCode,assignedUserId,sourceNo,status,percentComplete$filter")
            loading = false
            rows = if (page.complete) page.rows else emptyList()
            status = if (!page.complete) "HATA: Ambar çekme listesinin tamamı alınamadı. Yenileyin."
                else if (rows.isEmpty()) "BOŞ: Açık ambar çekme yok"
                else "TAMAM: ${rows.size} ambar çekme"
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
        onError = { status = it },
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
            Button(onClick = { load() }, enabled = !loading) { WmsRefreshLabel(loading) }
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
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(shownRows) { d ->
                OperationDocumentCard(
                    title = d.optString("no"),
                    status = bcStatusLabelTr(d.optString("status")),
                    metadata = "Lokasyon: ${firstValue(d, "locationCode")}  ·  Kaynak: ${firstValue(d, "sourceNo")}\nAtanan: ${firstValue(d, "assignedUserId")}",
                    progressPercent = d.optInt("percentComplete"),
                    onClick = { selected = d.optString("no") },
                )
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Açık ambar çekme yok.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WhsePickDocument(no: String, onBack: () -> Unit) {
    // Donanım Geri tuşu belge ekranından uygulamayı kapatmasın; listeye dönsün.
    androidx.activity.compose.BackHandler { onBack() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var headerLoaded by remember { mutableStateOf(false) }
    var linesComplete by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var qtyLine by remember { mutableStateOf<JSONObject?>(null) }
    var scanFilter by remember { mutableStateOf("") }
    var sortByBin by remember { mutableStateOf(true) }
    // v2: Lot No. varsayılan olarak Item No.'nun yanında görünür.
    var columns by remember { mutableStateOf(ColumnPrefs.get(context, "shippingPickLpQtyV3", GridColumns.pick)) }
    var showColumns by remember { mutableStateOf(false) }
    // ELOG müşteri isteği: bin+item aynı olan satırları tek satırda göster,
    // girilen miktarı alt satırlara dağıt (bkz. LineGrouping/LineGroupCards).
    var merge by remember { mutableStateOf(false) }
    var groupTarget by remember { mutableStateOf<LineGroup?>(null) }
    // ELOG raf modu: raf (bin) barkodu okutulunca liste o rafın satırlarına iner.
    var binFilter by remember { mutableStateOf("") }
    // Eş zamanlılık: aynı pick belgesine Toplama ekranından da girilebiliyor.
    // Belge başkasının üzerindeyse burada da işlem yapılamamalı — iki operatör
    // aynı satırı toplarsa miktarlar çakışır. Kimlik bir kez çözülür.
    var myUserId by remember { mutableStateOf("") }
    var inFlightLineNos by remember(no) { mutableStateOf<Set<Int>>(emptySet()) }
    var showCancelConfirm by remember { mutableStateOf(false) }
    // Sevk LP (toplama sepeti) ve eksik bildirimi — API'de vardı, ekranda yoktu (UAT shipping-x04).
    var shortLine by remember(no) { mutableStateOf<JSONObject?>(null) }

    fun reload() {
        scope.launch {
            busy = true
            header = null; lines = emptyList(); headerLoaded = false; linesComplete = false
            myUserId = BcApi.currentUserId(context).trim()
            val h = BcApi.get(context, "picks('$no')")
            header = if (h.ok) runCatching { JSONObject(h.body) }.getOrNull() else null
            headerLoaded = header != null
            // Toplama kaydedilince BC belgeyi siler; 404 bir yükleme hatası değil,
            // "iş bitti" demektir. Eskiden bunun yerine "satırlar yüklenemedi"
            // hatası gösteriliyordu (kullanıcı başarılı kaydı hata sanıyordu).
            if (!h.ok && h.httpCode == 404) {
                busy = false
                status = "TAMAM: Toplama kaydedildi, belge kapandı."
                onBack()
                return@launch
            }
            val page = BcApi.getAllPages(context, "pickLines?\$filter=no eq '$no'&\$top=100")
            lines = page.rows
            linesComplete = page.complete
            if (!headerLoaded || !linesComplete) status = "Belgenin tüm satırları yüklenemedi. Yenileyip tekrar deneyin."
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    fun action(name: String, body: String, okMsg: String) {
        if (myUserId.isBlank()) {
            status = "Depo kullanıcısı doğrulanamadı. Yeniden giriş yapın."
            return
        }
        scope.launch {
            busy = true; status = "$name..."
            val r = BcApi.boundAction(context, "picks", no, name, body)
            busy = false
            status = if (r.ok) "TAMAM: $okMsg (HTTP ${r.httpCode})" else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
            if (r.ok) reload()
        }
    }

    fun updateLine(line: JSONObject, qty: Double, lotNo: String, sourceLpNo: String = "") {
        if (!canMutateAssignedDocument(header?.optString("assignedUserId").orEmpty(), myUserId)) {
            status = documentOwnershipMessage(header?.optString("assignedUserId").orEmpty(), myUserId)
            return
        }
        val lineNo = line.optInt("lineNo")
        if (lineNo in inFlightLineNos) return
        inFlightLineNos = inFlightLineNos + lineNo
        scope.launch {
            busy = true; status = "Satır güncelleniyor..."
            val r = BcApi.confirmPickLine(
                context = context,
                pickNo = no,
                lineNo = lineNo,
                qtyToHandle = qty,
                lotNo = lotNo,
                sourceLpNo = sourceLpNo,
            )
            busy = false
            inFlightLineNos = inFlightLineNos - lineNo
            status = if (r.ok) "TAMAM: Satır güncellendi (HTTP ${r.httpCode})" else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
            if (r.ok) reload()
        }
    }

    fun cancelForCurrentUser() {
        scope.launch {
            busy = true
            status = "Toplama güvenli biçimde iptal ediliyor..."
            val r = BcApi.cancelPick(context, no)
            busy = false
            showCancelConfirm = false
            status = if (r.ok) "TAMAM: $no iptal edildi"
                else "HATA (HTTP ${r.httpCode}): ${BcApi.errorMessage(r.body)}"
            if (r.ok) onBack()
        }
    }

    val h = header
    val assignedTo = h?.optString("assignedUserId")?.trim().orEmpty()
    val canMutate = headerLoaded && linesComplete &&
        canMutateAssignedDocument(assignedTo, myUserId)
    val takeLines = lines.filter { !BcEnum.decodeOData(it.optString("actionType")).equals("Place", ignoreCase = true) }
    val allCollected = takeLines.isNotEmpty() && takeLines.all { lineDone(it, LineModule.PICK) }
    val readyToRegister = pickReadyToRegister(
        pickMode = BcEnum.decodeOData(h?.optString("pickMode").orEmpty()),
        qtyToHandle = takeLines.map { it.optDouble("qtyToHandle", 0.0) },
        allCollected = allCollected,
    )
    DocumentScanHandler(
        enabled = qtyLine == null && groupTarget == null && !busy && canMutate,
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
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(12.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onBack) { Text("‹ Belge Listesi") }
                Spacer(Modifier.weight(1f))
                TextButton(
                    onClick = { showCancelConfirm = true },
                    enabled = !busy && canMutate,
                ) {
                    Text("Pick'i İptal Et", color = MaterialTheme.colorScheme.error)
                }
            }
            DocHeaderCard(
                title = no,
                subtitle = "Lokasyon: ${h?.optString("locationCode") ?: ""} · ${bcStatusLabelTr(h?.optString("status") ?: "")}",
                badge = assignedTo.ifBlank { "Atanmadı" },
                percent = h?.optDouble("percentComplete")?.toInt() ?: 0,
            )
            if (!canMutate && headerLoaded) {
                Spacer(Modifier.height(6.dp))
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = bcwmsStatus().danger.copy(alpha = 0.14f)),
                ) {
                    Column(Modifier.padding(12.dp)) {
                        Text(documentOwnershipMessage(assignedTo, myUserId), fontWeight = FontWeight.Bold, fontSize = 14.sp, color = bcwmsStatus().danger)
                        Text(
                            "Salt görüntüleme. Aynı belgeyi iki kişi toplarsa miktarlar çakışır. " +
                                "Devam etmek için önce \"Bana Ata\" ile sunucu üzerinden atama yapın.",
                            fontSize = 12.sp,
                        )
                    }
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
                Text(if (merge) "Gruplar (${displayGroups.size})" else "Satırlar (${displayLines.size}/${takeLines.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.weight(1f))
                FilterChip(selected = merge, onClick = { merge = !merge }, label = { Text("🔗 Birleştir", fontSize = 12.sp) })
                FilterChip(selected = sortByBin, onClick = { sortByBin = !sortByBin }, label = { Text("🧭 Bin", fontSize = 12.sp) })
                if (!merge) { TextButton(onClick = { showColumns = true }) { WmsActionLabel(WmsGlyph.FIELD_SETTINGS, "Kolonlar") } }
            }
            if (binFilter.isNotBlank()) { ScanFilterChip("📍 Raf $binFilter") { binFilter = "" }; Spacer(Modifier.height(4.dp)) }
            if (scanFilter.isNotBlank()) { ScanFilterChip(scanFilter) { scanFilter = "" }; Spacer(Modifier.height(4.dp)) }
            if (merge) {
                LineGroupCards(
                    groups = displayGroups,
                    staged = { it.optDouble("qtyToHandle", 0.0) },
                    modifier = Modifier.fillMaxWidth(),
                    expandRows = true,
                    onGroupClick = { if (!busy && canMutate) groupTarget = it },
                )
            } else {
                LineGrid(
                    defs = GridColumns.pick,
                    columns = columns,
                    rows = displayLines,
                    modifier = Modifier.fillMaxWidth(),
                    isDone = { lineDone(it, LineModule.PICK) },
                    isPartial = { linePartial(it, LineModule.PICK) },
                    expandRows = true,
                    onRowClick = { if (canMutate && !busy) qtyLine = it },
                )
            }
        }
        BottomActionBar {
            val mainLp = h?.optString("mainLpNo").orEmpty()
            OutlinedButton(
                onClick = {
                    scope.launch {
                        busy = true
                        if (mainLp.isBlank()) {
                            status = "Sevk LP başlatılıyor..."
                            val tpl = resolveLpTemplate(context, LpPurpose.PALLET)
                            if (tpl == null) { busy = false; status = "HATA: Uygun sepet/palet şablonu bulunamadı."; return@launch }
                            val r = BcApi.boundAction(context, "picks", no, "startShippingLP", JSONObject().apply { put("lpTemplateCode", tpl) }.toString())
                            busy = false
                            status = if (r.ok) "TAMAM: Sevk LP ${BcApi.scalarValue(r.body).trim()} başlatıldı"
                                else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                        } else {
                            status = "Sevk LP kapatılıyor..."
                            val r = BcApi.boundAction(context, "picks", no, "stopShippingLP", JSONObject().apply { put("lpNo", mainLp); put("printLabel", false) }.toString())
                            busy = false
                            status = if (r.ok) "TAMAM: Sevk LP $mainLp kapatıldı" else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                        }
                        reload()
                    }
                },
                enabled = !busy && canMutate,
                modifier = Modifier.weight(1f).height(48.dp),
            ) { Text(if (mainLp.isBlank()) "📦 Sevk LP Başlat" else "📦 LP Kapat ($mainLp)", fontSize = 13.sp) }
            OutlinedButton(
                onClick = {
                    val open = lines.filter { it.optDouble("qtyOutstanding", 0.0) > 0.0 }
                    when {
                        open.isEmpty() -> status = "ℹ️ Eksik bildirilecek açık satır yok."
                        else -> shortLine = open.first()
                    }
                },
                enabled = !busy && canMutate,
                modifier = Modifier.weight(1f).height(48.dp),
            ) { Text("📉 Eksik Bildir", fontSize = 13.sp) }
        }
        BottomActionBar {
            // "Bana Ata" kilitliyken de açık: devralma tek çıkış yolu. BC tarafı
            // (ClaimPick) belge başkasındaysa zaten reddeder, o hata gösterilir.
            OutlinedButton(onClick = { action("assignToMe", "{}", "Bana atandı") }, enabled = !busy && headerLoaded && linesComplete && myUserId.isNotBlank() && !canMutate, modifier = Modifier.weight(1f).height(com.dynops.bcwms.ui.wmsPrimaryButtonHeight())) {
                Text("Bana Ata")
            }
            val canRegister = canRegisterAssignedPick(assignedTo, myUserId, readyToRegister, inFlightLineNos.size) && headerLoaded && linesComplete
            Button(onClick = {
                scope.launch {
                    busy = true; status = "Toplama kaydediliyor..."
                    val r = BcApi.registerPick(context, no)
                    busy = false
                    status = if (r.ok) "Toplama kaydedildi." else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                    if (r.ok) reload()
                }
            }, enabled = !busy && canRegister, modifier = Modifier.weight(1f).height(com.dynops.bcwms.ui.wmsPrimaryButtonHeight())) {
                Text(
                    when {
                        !canMutate -> "Belge salt okunur"
                        inFlightLineNos.isNotEmpty() -> "Satır yazımı bekleniyor"
                        canRegister -> "✅ Toplamayı Kaydet"
                        else -> "Miktar girin"
                    },
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }

    shortLine?.let { sl ->
        QuantityDialogSheet(
            title = "Eksik Bildir — ${sl.optString("binCode")}",
            itemNo = sl.optString("itemNo"),
            initialQty = sl.optDouble("qtyOutstanding").takeIf { it > 0 } ?: 1.0,
            initialUom = sl.optString("unitOfMeasureCode"),
            showLotSerial = false,
            onDismiss = { shortLine = null },
            onConfirm = { res ->
                shortLine = null
                scope.launch {
                    busy = true; status = "Eksik miktar bildiriliyor..."
                    val r = BcApi.boundAction(
                        context, "picks", no, "markShort",
                        JSONObject().apply {
                            put("lineNo", sl.optInt("lineNo"))
                            put("qty", res.quantity)
                            put("reasonCode", "")
                        }.toString(),
                    )
                    busy = false
                    status = if (r.ok) "TAMAM: ${sl.optString("itemNo")} için ${res.quantity} eksik bildirildi"
                        else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                    if (r.ok) reload()
                }
            },
        )
    }

    val ql = qtyLine
    if (ql != null) {
        QuantityDialogSheet(
            title = "Çekme Miktarı",
            itemNo = ql.optString("itemNo"),
            initialQty = ql.optDouble("qtyOutstanding").takeIf { it > 0 } ?: ql.optDouble("quantity").takeIf { it > 0 } ?: 1.0,
            initialUom = ql.optString("unitOfMeasureCode"),
            initialLot = ql.optString("lotNo"),
            allowZeroQuantity = true,
            showLotSerial = true,
            showSerial = false,
            showSourceLp = true,
            initialSourceLp = ql.optString("licensePlateNo"),
            lotRequired = ql.optBoolean("lotRequired", false),
            showAvailableLotLookup = true,
            autoDetectLotFromStock = true,
            locationCode = rawValue(ql, "locationCode").ifBlank { h?.optString("locationCode").orEmpty() },
            binCode = rawValue(ql, "binCode"),
            variantCode = ql.optString("variantCode"),
            onDismiss = { qtyLine = null },
            onConfirm = { res ->
                qtyLine = null
                updateLine(ql, res.quantity, res.lotNo, res.sourceLpNo)
            },
        )
    }
    if (showCancelConfirm) {
        AlertDialog(
            onDismissRequest = { if (!busy) showCancelConfirm = false },
            title = { Text("$no iptal edilsin mi?") },
            text = { Text("Yalnız kaydedilmemiş toplama iptal edilir. Sevkiyat silinmez; yeniden Pick Oluşturabilirsiniz.") },
            dismissButton = {
                TextButton(onClick = { showCancelConfirm = false }, enabled = !busy) { Text("Vazgeç") }
            },
            confirmButton = {
                Button(
                    onClick = { cancelForCurrentUser() },
                    enabled = !busy,
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                ) { Text("Pick'i İptal Et") }
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
            allowZeroQuantity = true,
            showLotSerial = true,
            showSerial = false,
            showSourceLp = true,
            lotRequired = gt.lines.any { it.optBoolean("lotRequired", false) },
            showAvailableLotLookup = true,
            autoDetectLotFromStock = true,
            locationCode = rawValue(gt.lines.first(), "locationCode").ifBlank { h?.optString("locationCode").orEmpty() },
            binCode = rawValue(gt.lines.first(), "binCode"),
            variantCode = gt.lines.first().optString("variantCode"),
            onDismiss = { groupTarget = null },
            onConfirm = { res ->
                groupTarget = null
                if (!canMutate) { status = documentOwnershipMessage(assignedTo, myUserId); return@QuantityDialogSheet }
                val planLineNos = distributeQty(gt, res.quantity, ::pickLineCapacity).map { it.first.optInt("lineNo") }.toSet()
                if (planLineNos.any { it in inFlightLineNos }) return@QuantityDialogSheet
                inFlightLineNos = inFlightLineNos + planLineNos
                scope.launch {
                    busy = true; status = "Grup dağıtılıyor..."
                    val plan = distributeQty(gt, res.quantity, ::pickLineCapacity)
                    var okCount = 0
                    var firstErr: String? = null
                    for ((ln, q) in plan) {
                        val r = BcApi.confirmPickLine(
                            context = context,
                            pickNo = no,
                            lineNo = ln.optInt("lineNo"),
                            qtyToHandle = q,
                            lotNo = res.lotNo,
                            sourceLpNo = res.sourceLpNo,
                        )
                        if (r.ok) {
                            okCount++
                        } else {
                            firstErr = BcApi.errorMessage(r.body)
                            break
                        }
                    }
                    busy = false
                    inFlightLineNos = inFlightLineNos - planLineNos
                    status = if (firstErr == null) "TAMAM: $okCount/${plan.size} satıra dağıtıldı"
                        else "HATA: $okCount/${plan.size} satır yazıldı — $firstErr"
                    reload()
                }
            },
        )
    }
    if (showColumns) {
        ChooseColumnsSheet(GridColumns.pick, columns, onDismiss = { showColumns = false }) { c -> columns = c; ColumnPrefs.save(context, "shippingPickLpQtyV3", c); showColumns = false }
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
            if (!canLoadAssignedOnlyList(showAll, myUser)) {
                rows = emptyList(); loading = false
                status = "HATA: Depo kullanıcısı doğrulanamadı. Yeniden giriş yapın."
                return@launch
            }
            val filter = com.dynops.bcwms.ui.buildODataFilter(
                assignedToMeClause(myUser, enabled = !showAll),
                com.dynops.bcwms.ui.searchClause("no", search),
            )
            val page = BcApi.getAllPages(context, "shipments?\$top=100&\$orderby=shipmentDate desc&\$select=no,locationCode,assignedUserId,status,shipmentDate,sourceNo,shipTo,lineCount$filter")
            loading = false
            rows = if (page.complete) page.rows else emptyList()
            status = if (!page.complete) "HATA: Sevkiyat listesinin tamamı alınamadı. Yenileyin."
                else if (rows.isEmpty()) (if (showAll) "BOŞ: Serbest bırakılmış ambar sevkiyatı yok" else "BOŞ: Size atanmış sevkiyat yok")
                else "TAMAM: ${rows.size} belge"
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
        onError = { status = it },
    ) { item, docs ->
        when { docs.isEmpty() -> status = "⚠️ '$item' açık sevkiyatta yok"; docs.size == 1 -> selected = docs.first(); else -> { itemDocs = item to docs; status = "TAMAM: '$item' → ${docs.size} belge" } }
    }
    val shownRows = itemDocs?.let { f -> rows.filter { it.optString("no") in f.second } } ?: rows

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { load() }, enabled = !loading) { WmsRefreshLabel(loading) }
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
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(shownRows) { d ->
                OperationDocumentCard(
                    title = d.optString("no"),
                    status = firstValue(d, "status"),
                    metadata = "Sevk: ${firstValue(d, "shipTo")}  ·  Kaynak: ${firstValue(d, "sourceNo")}\nAtanan: ${firstValue(d, "assignedUserId")}",
                    onClick = { selected = d.optString("no") },
                )
            }
            if (rows.isEmpty() && !loading) item { EmptyState(if (showAll) "Serbest bırakılmış Ambar Sevkiyatı yok. Siparişten direkt sevkiyat için sağdaki sekmeyi kullanın." else "Size atanmış sevkiyat yok. Tümünü görmek için \"Tümü\" seçin.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ShipDocument(no: String, onBack: () -> Unit, onPickCreated: (String) -> Unit) {
    // Donanım Geri tuşu belge ekranından uygulamayı kapatmasın; listeye dönsün.
    androidx.activity.compose.BackHandler { onBack() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var printSlip by remember { mutableStateOf(true) }
    var invoice by remember { mutableStateOf(false) }
    // Sevk BC'de kaydedildi ama BC bir uyarı döndürdü (ör. e-İrsaliye numara
    // serisi bitti). Eskiden mesaj yazılıp hemen onBack() çalıştığı için
    // operatör uyarıyı hiç görmüyordu (UAT shipping-11).
    var postWarning by remember { mutableStateOf<String?>(null) }
    var qtyLine by remember { mutableStateOf<JSONObject?>(null) }
    // Toplama üretilemezse elle miktar/lot girilecek satır.
    var pendingLotLine by remember(no) { mutableStateOf<JSONObject?>(null) }
    var scanFilter by remember { mutableStateOf("") }
    var columns by remember { mutableStateOf(ColumnPrefs.get(context, "shipment", GridColumns.shipment)) }
    var showColumns by remember { mutableStateOf(false) }
    var headerLoaded by remember(no) { mutableStateOf(false) }
    var linesComplete by remember(no) { mutableStateOf(false) }
    var myUserId by remember(no) { mutableStateOf("") }
    // BADE: satış siparişinde sevkiyat acentesi zorunlu (Sales-Post öncesi
    // kontrol). Terminal acenteyi seçip başlığa + kaynak siparişe yazar.
    var showAgent by remember(no) { mutableStateOf(false) }
    var agentSkipped by remember(no) { mutableStateOf(false) }

    fun reload() {
        scope.launch {
            busy = true
            headerLoaded = false
            linesComplete = false
            header = null
            lines = emptyList()
            myUserId = BcApi.currentUserId(context).trim()
            val h = BcApi.get(context, "shipments('$no')")
            if (h.ok) {
                header = JSONObject(h.body)
                headerLoaded = true
            }
            val page = BcApi.getAllPages(context, "shipmentLines?\$filter=no eq '$no'&\$orderby=lineNo")
            lines = page.rows
            linesComplete = page.complete
            if (!headerLoaded || !linesComplete) {
                status = "Belge eksiksiz yüklenemedi. Bağlantıyı kontrol edip yenileyin."
            }
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    val h = header
    val assignedUserId = h?.optString("assignedUserId").orEmpty()
    val canMutate = headerLoaded && linesComplete &&
        canMutateAssignedDocument(assignedUserId, myUserId)
    val shippingAgent = h?.optString("shippingAgentCode")?.trim().orEmpty()
    val sourceShippingAgent = h?.optString("sourceShippingAgentCode")?.trim().orEmpty()
    val agentMissing = headerLoaded && shippingAgent.isBlank() && sourceShippingAgent.isBlank() && !agentSkipped

    fun openPickForMultipleLots(fallbackLine: JSONObject? = null) {
        pendingLotLine = fallbackLine
        if (!canMutate) {
            status = documentOwnershipMessage(assignedUserId, myUserId)
            return
        }
        scope.launch {
            busy = true
            status = "Çoklu lot/raf için ambar toplama açılıyor..."
            val r = BcApi.boundAction(
                context,
                "shipments",
                no,
                "createPickFor",
                JSONObject().apply { put("userId", myUserId) }.toString(),
            )
            val pickNo = if (r.ok) BcApi.scalarValue(r.body) else ""
            busy = false
            if (r.ok && pickNo.isNotBlank()) {
                status = "TAMAM: Ambar Toplama $pickNo açıldı"
                onPickCreated(pickNo)
            } else {
                // Toplama üretilemediğinde operatörün başka yolu kalmıyordu.
                // Miktar + lot penceresi doğrudan açılır ki satır elle sevk
                // edilebilsin (UAT D-01/D-03).
                pendingLotLine?.let { satir ->
                    qtyLine = satir
                    pendingLotLine = null
                }
                status = if (r.ok) "HATA: Toplama numarası alınamadı"
                    else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode) +
                        " Miktar ve lotu elle girmek için pencereyi kullanabilirsiniz."
            }
        }
    }

    DocumentScanHandler(
        enabled = qtyLine == null && canMutate && !busy,
        lines = lines,
        onSingleMatch = { line, _ -> scanFilter = ""; qtyLine = line },
        onMultiMatch = { itemNo, _ -> scanFilter = itemNo; status = "TAMAM: '$itemNo' için birden fazla satır — birini seçin" },
        onNoMatch = { r -> status = "⚠️ '${r.itemNo ?: r.value}' bu belgede yok" },
    )
    val displayLines = if (scanFilter.isBlank()) lines else lines.filter { matchLinesByBarcode(listOf(it), com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve(scanFilter)).isNotEmpty() }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Belge Listesi") }
            DocHeaderCard(
                title = no,
                subtitle = "Sevk: ${firstValue(h ?: JSONObject(), "shipTo")} · ${bcStatusLabelTr(firstValue(h ?: JSONObject(), "status"))} · 👤 Atanan Kullanıcı: ${assignedUserId.ifBlank { "Atanmamış" }}",
            )
            if (headerLoaded && h?.has("shippingAgentCode") == true) {
                Spacer(Modifier.height(6.dp))
                ShippingAgentCard(
                    agentCode = shippingAgent.ifBlank { sourceShippingAgent },
                    missing = agentMissing,
                    enabled = canMutate && !busy,
                    onEdit = { showAgent = true },
                )
            }
            if (!canMutate && !busy) {
                Spacer(Modifier.height(6.dp))
                StatusText(documentOwnershipMessage(assignedUserId, myUserId))
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
                TextButton(onClick = { showColumns = true }) { WmsActionLabel(WmsGlyph.FIELD_SETTINGS, "Kolonlar") }
            }
            if (scanFilter.isNotBlank()) { ScanFilterChip(scanFilter) { scanFilter = "" }; Spacer(Modifier.height(4.dp)) }
            LineGrid(
                defs = GridColumns.shipment, columns = columns, rows = displayLines,
                modifier = Modifier.fillMaxWidth(),
                isDone = { lineDone(it, LineModule.SHIPMENT) },
                expandRows = true,
                onRowClick = {
                    if (canMutate) {
                        // A warehouse shipment line can consume several lots
                        // and bins. Direct line PATCH only represents one lot;
                        // route tracked items to BC's pick flow where Take lines
                        // can be split safely per lot/bin.
                        if (it.optBoolean("lotRequired", false))
                            openPickForMultipleLots(fallbackLine = it)
                        else
                            qtyLine = it
                    }
                },
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = printSlip, enabled = canMutate && !busy, onCheckedChange = { printSlip = it })
                Text("İrsaliye yazdır", fontSize = 13.sp)
                Spacer(Modifier.width(12.dp))
                Checkbox(checked = invoice, enabled = canMutate && !busy, onCheckedChange = { invoice = it })
                Text("Faturalandır", fontSize = 13.sp)
            }
        }
        BottomActionBar {
            if (!canMutate) {
                OutlinedButton(
                    onClick = {
                        scope.launch {
                            if (myUserId.isBlank()) {
                                status = "Depo kullanıcısı doğrulanamadı. Yeniden giriş yapın."
                                return@launch
                            }
                            busy = true; status = "Sevkiyat üzerinize alınıyor..."
                            val body = JSONObject().apply { put("userId", myUserId) }.toString()
                            val r = BcApi.boundAction(context, "shipments", no, "assignToUser", body)
                            busy = false
                            status = if (r.ok) "TAMAM: Sevkiyat bana atandı"
                                else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                            if (r.ok) reload()
                        }
                    },
                    enabled = !busy && headerLoaded && linesComplete && myUserId.isNotBlank(),
                    modifier = Modifier.fillMaxWidth().height(com.dynops.bcwms.ui.wmsPrimaryButtonHeight()),
                ) { Text("👤 Bana Ata", fontWeight = FontWeight.Bold) }
            } else {
                OutlinedButton(
                    onClick = { openPickForMultipleLots() },
                    enabled = !busy && lines.isNotEmpty(),
                    modifier = Modifier.weight(1f).height(com.dynops.bcwms.ui.wmsPrimaryButtonHeight()),
                ) { Text("📦 Pick Oluştur", fontWeight = FontWeight.Bold) }
                Button(
                    onClick = onClick@{
                        // Acente boşsa BC (BADE) postu reddeder; önce seçtir.
                        if (agentMissing) { showAgent = true; return@onClick }
                        scope.launch {
                            busy = true; status = "Sevk kaydı..."
                            val body = JSONObject().apply {
                                put("print", printSlip)
                                put("invoice", invoice)
                                put("printerId", getDefaultPrinter(context, PRINTER_USAGE_DOCUMENT))
                            }.toString()
                            val r = BcApi.boundAction(context, "shipments", no, "postToPrinter", body)
                            // BC bazı başarılı postlarda belgeyi silip cevabı geç
                            // üretirken REF-* hatası döndürebiliyor. Hata sonrası
                            // açık belge gerçekten yoksa işlem kaydedilmiştir.
                            val verifyCode = if (!r.ok) {
                                val safeNo = no.replace("'", "''")
                                BcApi.get(context, "shipments('$safeNo')").httpCode
                            } else null
                            var committed = shipmentPostCommitted(r.ok, verifyCode)
                            var postedDespiteError = false
                            if (!committed && !r.ok && verifyCode == 200) {
                                // BC sevki commit edip sonra (ör. BADE e-İrsaliye numara serisi)
                                // hata döndürebiliyor: belge duruyorsa satırların sevk miktarı
                                // düştü mü diye bak; düştüyse sevk gerçekleşmiştir.
                                val after = BcApi.getAllPages(context, "shipmentLines?\$filter=no eq '${no.replace("'", "''")}'&\$orderby=lineNo")
                                if (after.complete) {
                                    val before = lines.associateBy { it.optInt("lineNo") }
                                    postedDespiteError = after.rows.any { l ->
                                        val b = before[l.optInt("lineNo")] ?: return@any false
                                        l.optDouble("qtyOutstanding", -1.0) >= 0 && l.optDouble("qtyOutstanding", 0.0) < b.optDouble("qtyOutstanding", 0.0)
                                    }
                                    if (postedDespiteError) committed = true
                                }
                            }
                            busy = false
                            status = when {
                                committed && postedDespiteError -> "TAMAM: Sevkiyat BC'de kaydedildi. UYARI: " + QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode).removePrefix("HATA: ")
                                committed -> "TAMAM: Sevkiyat kaydedildi"
                                else -> QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                            }
                            if (committed) {
                                if (postedDespiteError) postWarning = status else onBack()
                            }
                        }
                    },
                    enabled = !busy && com.dynops.bcwms.lib.ActionGuards.hasQuantity(lines, field = "qtyToShip"),
                    modifier = Modifier.weight(1f).height(com.dynops.bcwms.ui.wmsPrimaryButtonHeight()),
                ) {
                    Text(
                        if (com.dynops.bcwms.lib.ActionGuards.hasQuantity(lines, field = "qtyToShip")) "✅ Sevkiyatı Kaydet" else "Önce satırlara miktar girin",
                        fontWeight = FontWeight.Bold,
                    )
                }
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
            showSourceLp = true,
            initialSourceLp = ql.optString("licensePlateNo"),
            lotRequired = ql.optBoolean("lotRequired", false),
            showAvailableLotLookup = true,
            autoDetectLotFromStock = true,
            locationCode = rawValue(ql, "locationCode").ifBlank { h?.optString("locationCode").orEmpty() },
            // Warehouse Shipment satırındaki bin sevk/hedef binidir.
            // Kaynak stok lotları lokasyonun tüm fiziksel raflarından listelenir.
            binCode = "",
            variantCode = ql.optString("variantCode"),
            onSelectMultipleLots = {
                qtyLine = null
                openPickForMultipleLots()
            },
            onDismiss = { qtyLine = null },
            onConfirm = { res ->
                qtyLine = null
                scope.launch {
                    if (!canMutate) {
                        status = documentOwnershipMessage(assignedUserId, myUserId)
                        return@launch
                    }
                    busy = true; status = "Satır güncelleniyor..."
                    val body = JSONObject().apply {
                        put("qtyToShip", res.quantity)
                        put("lotNo", res.lotNo)
                        if (res.sourceLpNo.isNotBlank()) put("licensePlateNo", res.sourceLpNo)
                    }.toString()
                    val lineNo = ql.optInt("lineNo")
                    val r = BcApi.patch(context, "shipmentLines(no='$no',lineNo=$lineNo)", body)
                    busy = false
                    status = if (r.ok) "TAMAM: Satır güncellendi" else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                    if (r.ok) reload()
                }
            }
        )
    }
    if (showAgent) {
        ShippingAgentDialog(
            current = shippingAgent.ifBlank { sourceShippingAgent },
            loadAgents = {
                val r = BcApi.boundAction(context, "shipments", no, "listShippingAgents")
                if (r.ok) parseVehicleDrivers(BcApi.scalarValue(r.body)) else null
            },
            onDismiss = { showAgent = false },
            onSkip = { showAgent = false; agentSkipped = true },
            onSave = { code ->
                showAgent = false
                scope.launch {
                    busy = true; status = "Sevkiyat acentesi kaydediliyor..."
                    val r = BcApi.boundAction(
                        context, "shipments", no, "setShippingAgent",
                        JSONObject().apply { put("agentCode", code); put("serviceCode", "") }.toString(),
                    )
                    busy = false
                    status = if (r.ok) "TAMAM: Sevkiyat acentesi $code kaydedildi" else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                    if (r.ok) reload()
                }
            },
        )
    }
    postWarning?.let { warn ->
        AlertDialog(
            onDismissRequest = { postWarning = null; onBack() },
            title = { Text("Sevkiyat kaydedildi") },
            text = { Text(warn.removePrefix("TAMAM: ")) },
            confirmButton = {
                Button(onClick = { postWarning = null; onBack() }) { Text("Tamam") }
            },
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
            val page = BcApi.getAllPages(
                context,
                "salesSources?\$top=100&\$orderby=shipmentDate desc$filter&\$select=no,customerNo,customerName,shipToName,locationCode,shipmentDate,status,lineCount,outstandingQty,percentComplete,requiresWhseShipment,directShipAllowed"
            )
            loading = false
            // Kalan miktarı olmayan siparişler sevk edilemez; listede yer kaplayıp
            // operatörü yanıltıyordu (canlı UAT shipping-x01).
            rows = if (page.complete) page.rows.filter { it.optDouble("outstandingQty", 0.0) > 0.0 } else emptyList()
            status = if (!page.complete) "HATA: Satış siparişi listesinin tamamı alınamadı. Yenileyin."
                else if (rows.isEmpty()) "BOŞ: sevk edilecek ${if (releasedOnly) "serbest bırakılmış" else "açık"} satış siparişi yok"
                else "TAMAM: ${rows.size} satış siparişi"
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
        onError = { status = it },
    ) { item, docs ->
        when { docs.isEmpty() -> status = "⚠️ '$item' açık SO'da yok"; docs.size == 1 -> selected = docs.first(); else -> { itemDocs = item to docs; status = "TAMAM: '$item' → ${docs.size} SO" } }
    }
    val shownRows = itemDocs?.let { f -> rows.filter { it.optString("no") in f.second } } ?: rows

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { load() }, enabled = !loading) { WmsRefreshLabel(loading) }
            Spacer(Modifier.width(12.dp))
            FilterChip(
                selected = releasedOnly,
                onClick = { releasedOnly = !releasedOnly },
                label = { Text(if (releasedOnly) "Sadece Serbest" else "Tüm Durumlar", fontSize = 12.sp) }
            )
        }
        Spacer(Modifier.height(8.dp))
        com.dynops.bcwms.ui.DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() }, label = "SO no ile ara")
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        if (itemDocs != null) { ScanFilterChip("${itemDocs!!.first} → ${itemDocs!!.second.size} SO") { itemDocs = null } }
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
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
                        val st = rawValue(d, "shipToName")
                        if (st.isNotBlank() && st != rawValue(d, "customerName")) {
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
    // Donanım Geri tuşu belge ekranından uygulamayı kapatmasın; listeye dönsün.
    androidx.activity.compose.BackHandler { onBack() }
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
    var touched by remember(no) { mutableStateOf(setOf<Int>()) }
    var showShipConfirm by remember(no) { mutableStateOf(false) }
    var columns by remember { mutableStateOf(ColumnPrefs.get(context, "salesSource", GridColumns.salesSource)) }
    var showColumns by remember { mutableStateOf(false) }
    var headerLoaded by remember(no) { mutableStateOf(false) }
    var linesComplete by remember(no) { mutableStateOf(false) }

    fun reload() {
        scope.launch {
            busy = true
            headerLoaded = false
            linesComplete = false
            header = null
            lines = emptyList()
            val h = BcApi.get(context, "salesSources('$no')")
            if (h.ok) {
                header = JSONObject(h.body)
                headerLoaded = true
            }
            val page = BcApi.getAllPages(
                context,
                "salesSourceLines?\$filter=no eq '$no' and type eq 'Item'&\$orderby=lineNo",
            )
            lines = page.rows
            linesComplete = page.complete
            if (!headerLoaded || !linesComplete) {
                status = "Belge eksiksiz yüklenemedi. Direkt sevkiyat kapatıldı; yenileyip tekrar deneyin."
            }
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    val h = header
    val trackingRequiresWarehouse = lines.any {
        it.optBoolean("lotRequired", false) || it.optBoolean("serialRequired", false)
    }
    val directAllowed = headerLoaded && linesComplete &&
        (h?.optBoolean("directShipAllowed", false) == true) &&
        !trackingRequiresWarehouse
    val stagedLines = lines.filter {
        it.optInt("lineNo") in touched && it.optDouble("qtyToShip", 0.0) > 0.0
    }
    DocumentScanHandler(
        enabled = qtyLine == null && !showScan && !busy && directAllowed,
        lines = lines,
        onSingleMatch = { line, _ -> if (directAllowed) { scanFilter = ""; qtyLine = line } },
        onMultiMatch = { itemNo, _ -> scanFilter = itemNo; status = "TAMAM: '$itemNo' için birden fazla satır — birini seçin" },
        onNoMatch = { r -> status = "⚠️ '${r.itemNo ?: r.value}' bu SO'da yok" },
    )
    val displayLines = if (scanFilter.isBlank()) lines else lines.filter { matchLinesByBarcode(listOf(it), com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve(scanFilter)).isNotEmpty() }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(12.dp)) {
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
                        if (trackingRequiresWarehouse)
                            "Bu siparişte lot/seri izlemeli ürün var. Lot ve seri kaydını korumak için Ambar Sevkiyatı ekranındaki belgeyi kullanın."
                        else "Bu lokasyon (${firstValue(h, "locationCode")}) için Ambar Sevkiyatı zorunlu. İlgili belgeyi Ambar Sevkiyatı ekranından tamamlayın.",
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
                TextButton(onClick = { showColumns = true }) { WmsActionLabel(WmsGlyph.FIELD_SETTINGS, "Kolonlar") }
            }
            if (scanFilter.isNotBlank()) { ScanFilterChip(scanFilter) { scanFilter = "" }; Spacer(Modifier.height(4.dp)) }
            LineGrid(
                defs = GridColumns.salesSource, columns = columns, rows = displayLines,
                modifier = Modifier.fillMaxWidth(),
                isDone = { it.optInt("lineNo") in touched && lineDone(it, LineModule.SALES) },
                expandRows = true,
                onRowClick = { if (directAllowed) qtyLine = it },
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = invoiceToo, enabled = directAllowed && !busy, onCheckedChange = { invoiceToo = it })
                Text("Aynı zamanda faturalandır", fontSize = 13.sp)
            }
        }

        BottomActionBar {
            OutlinedButton(onClick = { showScan = true }, enabled = !busy && directAllowed, modifier = Modifier.weight(1f)) {
                WmsActionLabel(WmsGlyph.SCAN, "Ürün Tara")
            }
        }
        BottomActionBar {
            Button(
                onClick = { showShipConfirm = true },
                enabled = !busy && directAllowed && stagedLines.isNotEmpty(),
                modifier = Modifier.fillMaxWidth().height(com.dynops.bcwms.ui.wmsPrimaryButtonHeight()),
            ) {
                Text(
                    when {
                        !directAllowed -> "Direkt sevkiyat yapılamaz"
                        stagedLines.isEmpty() -> "Önce satırlara miktar girin"
                        else -> if (invoiceToo) "✅ Sevk Et ve Faturalandır" else "✅ Sevk Et"
                    },
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }

    if (showShipConfirm) {
        AlertDialog(
            onDismissRequest = { if (!busy) showShipConfirm = false },
            title = { Text("Sevkiyatı kaydet") },
            text = { Text("${stagedLines.size} satır sevk edilecek${if (invoiceToo) " ve faturalandırılacak" else ""}. Devam edilsin mi?") },
            confirmButton = {
                Button(onClick = {
                    showShipConfirm = false
                    scope.launch {
                        if (!directAllowed) {
                            status = "Belge doğrulanmadan direkt sevkiyat yapılamaz. Yenileyip tekrar deneyin."
                            return@launch
                        }
                        busy = true; status = "Sevkiyat hazırlanıyor..."
                        var preflightOk = true
                        var resetCount = 0
                        for (line in lines.filter {
                            it.optInt("lineNo") !in touched && it.optDouble("qtyToShip", 0.0) > 0.0
                        }) {
                            val reset = BcApi.patch(
                                context,
                                "salesSourceLines(documentType='Order',no='${no.replace("'", "''")}',lineNo=${line.optInt("lineNo")})",
                                JSONObject().apply { put("qtyToShip", 0) }.toString(),
                            )
                            if (!reset.ok) { preflightOk = false; break }
                            resetCount++
                        }
                        if (!preflightOk) {
                            busy = false
                            status = if (resetCount > 0)
                                "UYARI: $resetCount satır sıfırlandı, kalan satırlar işlenemedi. Belge yenilendi; sevkiyat yapılmadı."
                            else "HATA: İşlenmeyen satırlar güvenle ayrıştırılamadı. Yenileyip tekrar deneyin."
                            reload()
                            return@launch
                        }
                        val body = JSONObject().apply { put("invoice", invoiceToo) }.toString()
                        val r = BcApi.boundAction(context, "salesSources", no, "ship", body)
                        busy = false
                        status = if (r.ok) "TAMAM: Sevkiyat kaydedildi."
                            else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                        if (r.ok) { touched = emptySet(); reload() }
                    }
                }) { Text(if (invoiceToo) "Sevk Et ve Faturala" else "Sevk Et") }
            },
            dismissButton = { TextButton(onClick = { showShipConfirm = false }) { Text("Vazgeç") } },
        )
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
                    if (!directAllowed) {
                        status = "Belge doğrulanmadan satır değiştirilemez. Yenileyip tekrar deneyin."
                        return@launch
                    }
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
                    status = if (r.ok) "TAMAM: Satır miktarı ${fmtNum(res.quantity)} olarak güncellendi."
                        else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                    if (r.ok) { touched = touched + lineNo; reload() }
                }
            }
        )
    }

    if (showScan) {
        ScanItemSheet(title = "Ürün Tara (SO)", onDismiss = { showScan = false }, onItem = { _, line ->
            showScan = false
            if (directAllowed) qtyLine = line
        }, lines = lines, matchKey = "itemNo")
    }
    if (showColumns) {
        ChooseColumnsSheet(GridColumns.salesSource, columns, onDismiss = { showColumns = false }) { c -> columns = c; ColumnPrefs.save(context, "salesSource", c); showColumns = false }
    }
}

private fun fmtNum(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()

@Composable
private fun ShippingAgentCard(agentCode: String, missing: Boolean, enabled: Boolean, onEdit: () -> Unit) {
    val palette = bcwmsStatus()
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = if (missing) palette.warning.copy(alpha = 0.18f) else MaterialTheme.colorScheme.surface),
        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Sevkiyat Acentesi", fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                Text(
                    if (missing) "Seçilmedi — sevk kaydından önce seçin (siparişte zorunlu olabilir)" else "Acente: ${agentCode.ifBlank { "-" }}",
                    fontSize = 12.sp,
                    color = if (missing) palette.danger else Color.Gray,
                )
            }
            TextButton(onClick = onEdit, enabled = enabled) { Text(if (missing) "Seç" else "Değiştir") }
        }
    }
}

@Composable
private fun ShippingAgentDialog(
    current: String,
    loadAgents: suspend () -> List<Pair<String, String>>?,
    onDismiss: () -> Unit,
    onSkip: () -> Unit,
    onSave: (String) -> Unit,
) {
    var selected by remember { mutableStateOf(current) }
    var query by remember { mutableStateOf("") }
    var agents by remember { mutableStateOf<List<Pair<String, String>>?>(null) }
    var loadError by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        val a = loadAgents()
        loadError = a == null
        agents = a ?: emptyList()
    }
    val shown = (agents ?: emptyList()).filter {
        query.isBlank() || it.first.contains(query, ignoreCase = true) || it.second.contains(query, ignoreCase = true)
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Sevkiyat Acentesi") },
        text = {
            Column(Modifier.fillMaxWidth()) {
                Text("Satış siparişinde sevkiyat acentesi zorunlu olabilir. Seçilen acente sevkiyata ve siparişe yazılır.", fontSize = 12.sp, color = Color.Gray)
                Spacer(Modifier.height(6.dp))
                OutlinedTextField(value = query, onValueChange = { query = it }, label = { Text("Acente ara") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(4.dp))
                when {
                    agents == null -> Text("Acenteler yükleniyor...", fontSize = 12.sp, color = Color.Gray)
                    loadError -> Text("HATA: Acente listesi alınamadı. Yenileyip tekrar deneyin.", fontSize = 12.sp, color = bcwmsStatus().danger)
                    shown.isEmpty() -> Text("Eşleşen acente yok. BC'de Sevkiyat Acenteleri listesini kontrol edin.", fontSize = 12.sp, color = Color.Gray)
                    else -> LazyColumn(Modifier.fillMaxWidth().heightIn(max = 240.dp)) {
                        items(shown) { (code, name) ->
                            Row(
                                Modifier.fillMaxWidth().clickable { selected = code }.padding(vertical = 2.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                RadioButton(selected = selected == code, onClick = { selected = code })
                                Column {
                                    Text(name.ifBlank { code }, fontSize = 14.sp)
                                    if (name.isNotBlank()) Text(code, fontSize = 11.sp, color = Color.Gray)
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = { Button(onClick = { onSave(selected) }, enabled = selected.isNotBlank()) { Text("Kaydet") } },
        dismissButton = {
            Row {
                TextButton(onClick = onSkip) { Text("Acentesiz devam") }
                TextButton(onClick = onDismiss) { Text("Vazgeç") }
            }
        },
    )
}
