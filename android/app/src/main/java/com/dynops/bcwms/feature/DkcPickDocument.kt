package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.math.BigDecimal
import java.math.RoundingMode

private fun pickNum(value: Double): String =
    BigDecimal.valueOf(value).setScale(5, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()

private fun pickCell(line: JSONObject, key: String): String = line.optString(key).let { if (it == "null") "" else it }

/**
 * DKÇ toplama belgesi — mal kabuldeki parçalı kabul akışının aynısı.
 *
 * Operatör satıra dokunur ya da ürünü okutur, topladığı miktarı girer (kalandan
 * az olabilir). "Kaydet" yalnız miktar girilen satırları, girilen miktar kadar
 * kaydeder; kalan miktar belgede durur ve sonra toplanır. Satır girişi belgeyi
 * kaydetmez; kayıt tek yerden, özet onayından sonra çalışır.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DkcPickDocument(no: String, onBack: () -> Unit) {
    // Donanım Geri tuşu belge ekranından uygulamayı kapatmasın; listeye dönsün.
    androidx.activity.compose.BackHandler { onBack() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember(no) { mutableStateOf<JSONObject?>(null) }
    var lines by remember(no) { mutableStateOf<List<JSONObject>>(emptyList()) }
    var headerLoaded by remember(no) { mutableStateOf(false) }
    var linesComplete by remember(no) { mutableStateOf(false) }
    var documentGone by remember(no) { mutableStateOf(false) }
    var status by remember(no) { mutableStateOf("") }
    var busy by remember(no) { mutableStateOf(false) }
    var myUserId by remember { mutableStateOf("") }
    var lpScanRequired by remember { mutableStateOf(false) }
    var entries by remember(no) { mutableStateOf(PickEntryStore.load(context, no)) }
    LaunchedEffect(entries) { PickEntryStore.save(context, no, entries) }

    var qtyLine by remember(no) { mutableStateOf<JSONObject?>(null) }
    var scanLot by remember(no) { mutableStateOf("") }
    var scanFilter by remember(no) { mutableStateOf("") }
    var binFilter by remember(no) { mutableStateOf("") }
    var showScan by remember(no) { mutableStateOf(false) }
    var showPostConfirm by remember(no) { mutableStateOf(false) }

    suspend fun reloadNow() {
        // Eski/eksik veriyle işlem yapılmasın: başlık ya da satırların bir
        // sayfası alınamazsa ekran salt okunur kalır.
        headerLoaded = false
        linesComplete = false
        coroutineScope {
            val headerJob = async { BcApi.get(context, "picks('${no.replace("'", "''")}')") }
            val linesJob = async { BcApi.getAllPages(context, "pickLines?\$filter=no eq '${no.replace("'", "''")}'&\$top=500") }
            val h = headerJob.await()
            val l = linesJob.await()
            // Toplama tamamen kaydedilince BC belgeyi siler: 404 yükleme hatası
            // değil, "belge kapandı" demektir.
            if (!h.ok && h.httpCode == 404) {
                documentGone = true
                header = null
                lines = emptyList()
                entries = emptyMap()
                return@coroutineScope
            }
            val parsed = if (h.ok) runCatching { JSONObject(h.body) }.getOrNull() else null
            header = parsed
            headerLoaded = parsed != null
            lines = l.rows
            linesComplete = l.complete
            if (headerLoaded && linesComplete) entries = prunePickEntries(pickTakeLines(lines), entries)
            else status = "HATA: Toplama belgesinin tamamı alınamadı. Yenileyip tekrar deneyin."
        }
    }

    fun reload() {
        scope.launch { busy = true; reloadNow(); busy = false }
    }

    LaunchedEffect(no) {
        busy = true
        myUserId = BcApi.currentUserId(context).trim()
        lpScanRequired = BcApi.lpScanRequired(context)
        reloadNow()
        busy = false
    }
    LaunchedEffect(documentGone) {
        if (documentGone) {
            // Liste ekranına dönülür; operatör belgenin neden kaybolduğunu görsün.
            android.widget.Toast.makeText(context, "$no toplaması tamamlandı, belge kapandı.", android.widget.Toast.LENGTH_LONG).show()
            onBack()
        }
    }

    val h = header
    val assignedTo = h?.optString("assignedUserId")?.trim().orEmpty()
    val canMutate = headerLoaded && linesComplete && canMutateAssignedPick(assignedTo, myUserId)
    val takeLines = pickTakeLines(lines)
    val rowDone: (JSONObject) -> Boolean = { pickRowDone(it, entries) }
    val rowPartial: (JSONObject) -> Boolean = { pickRowPartial(it, entries) }
    val postLines = pickPostLines(takeLines, entries)
    val postQty = postLines.sumOf { pickEnteredQty(it, entries) }

    fun takeOver() {
        scope.launch {
            if (myUserId.isBlank()) {
                status = "HATA: Depo kullanıcısı doğrulanamadı. Yeniden giriş yapın."
                return@launch
            }
            busy = true; status = "Üzerinize alınıyor..."
            val r = BcApi.boundAction(
                context, "picks", no, "reassign",
                JSONObject().apply { put("userId", myUserId); put("reason", "terminalden üstlenildi") }.toString(),
            )
            status = if (r.ok) "TAMAM: $no üzerinize alındı." else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
            reloadNow()
            busy = false
        }
    }

    fun openLine(line: JSONObject, lotFromScan: String = "") {
        if (!canMutate || busy) return
        scanLot = lotFromScan
        qtyLine = line
    }

    /** Satıra miktar yazar; belgeyi KAYDETMEZ. 0 girilirse satır "girilmedi" olur. */
    fun confirmLine(line: JSONObject, qty: Double, lotNo: String, sourceLpNo: String) {
        val lineNo = line.optInt("lineNo")
        scope.launch {
            busy = true; status = "Satır kaydediliyor..."
            val r = BcApi.confirmPickLine(
                context = context,
                pickNo = no,
                lineNo = lineNo,
                qtyToHandle = qty,
                // Miktar 0 iken satırın mevcut lotu korunur; boş göndermek lotu silerdi.
                lotNo = if (qty > 0.0) lotNo else line.optString("lotNo"),
                sourceLpNo = if (qty > 0.0) sourceLpNo else "",
            )
            if (!r.ok) {
                status = QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                reloadNow()
                busy = false
                return@launch
            }
            // Giriş, sunucunun kabul ettiği (yuvarlanmış olabilir) miktarla tutulur.
            entries = entries - lineNo
            reloadNow()
            val saved = pickTakeLines(lines).firstOrNull { it.optInt("lineNo") == lineNo }
            val savedQty = saved?.optDouble("qtyToHandle", 0.0) ?: 0.0
            if (saved != null && savedQty > PICK_QTY_EPSILON) {
                entries = entries + (lineNo to PickEntry(savedQty, saved.optDouble("qtyHandled", 0.0)))
                val left = pickLineCapacity(saved) - savedQty
                status = "TAMAM: ${line.optString("itemNo")} · ${pickNum(savedQty)} girildi" +
                    if (left > PICK_QTY_EPSILON) " (kalan ${pickNum(left)} belgede kalır)" else ""
            } else if (headerLoaded && linesComplete) {
                status = "TAMAM: ${line.optString("itemNo")} satırının girişi kaldırıldı."
            }
            scanFilter = ""
            busy = false
        }
    }

    fun register() {
        scope.launch {
            busy = true; status = "Toplama hazırlanıyor..."
            // 1) Güncel belge üzerinden karar ver.
            reloadNow()
            if (documentGone) { busy = false; return@launch }
            if (!headerLoaded || !linesComplete) { busy = false; return@launch }
            if (!canMutateAssignedPick(header?.optString("assignedUserId").orEmpty(), myUserId)) {
                status = documentOwnershipMessage(header?.optString("assignedUserId").orEmpty(), myUserId)
                busy = false
                return@launch
            }
            var take = pickTakeLines(lines)
            if (pickPostLines(take, entries).isEmpty()) {
                status = "HATA: Kaydedilecek satır kalmadı. Miktarları yeniden girin."
                busy = false
                return@launch
            }
            // 2) BC'nin önceden doldurduğu, operatörün dokunmadığı satırları
            //    sıfırla; yoksa kayıt bütün belgeyi toplanmış sayar. Seri ve
            //    fail-closed: biri sıfırlanamazsa kayıt hiç yapılmaz.
            val toClear = pickLinesToClear(take, entries)
            for ((i, line) in toClear.withIndex()) {
                status = "Girilmeyen satırlar ayrılıyor: ${i + 1}/${toClear.size}"
                val r = BcApi.confirmPickLine(
                    context, no, line.optInt("lineNo"), 0.0, lotNo = line.optString("lotNo"), sourceLpNo = "",
                )
                if (!r.ok) {
                    status = "HATA: ${line.optString("itemNo")} satırı kayıt dışı bırakılamadı, toplama KAYDEDİLMEDİ: " +
                        BcApi.errorMessage(r.body)
                    reloadNow()
                    busy = false
                    return@launch
                }
            }
            // 3) Son kontrol: sunucudaki miktarlar operatörün girdikleriyle birebir aynı mı?
            if (toClear.isNotEmpty()) {
                reloadNow()
                if (documentGone) { busy = false; return@launch }
                if (!headerLoaded || !linesComplete) { busy = false; return@launch }
                take = pickTakeLines(lines)
            }
            val mismatches = pickPostMismatches(take, entries)
            val ready = pickPostLines(take, entries)
            if (mismatches.isNotEmpty() || ready.isEmpty()) {
                status = "HATA: Satır miktarları doğrulanamadı" +
                    (if (mismatches.isNotEmpty()) " (satır ${mismatches.joinToString(", ")})" else "") +
                    ". Toplama KAYDEDİLMEDİ; miktarları kontrol edip tekrar deneyin."
                busy = false
                return@launch
            }
            // 4) Kayıt.
            status = "Toplama kaydediliyor..."
            val readyCount = ready.size
            val r = BcApi.registerPick(context, no)
            if (!r.ok) {
                status = QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                // Yanıt kaybolmuş olabilir: gerçek durumu sunucudan al.
                reloadNow()
                busy = false
                return@launch
            }
            entries = emptyMap()
            reloadNow()
            if (!documentGone) status = "TAMAM: $readyCount satır kaydedildi. Kalan miktar belgede duruyor."
            busy = false
        }
    }

    // Donanım tarayıcı: ürün okut → tek satırsa miktar ekranı açılır, çok satırsa
    // liste o ürüne iner; raf barkodu okutulursa liste o rafa iner.
    DocumentScanHandler(
        enabled = canMutate && !busy && qtyLine == null && !showScan && !showPostConfirm,
        lines = takeLines,
        onSingleMatch = { line, r -> scanFilter = ""; openLine(line, r.lotNo.orEmpty()) },
        onMultiMatch = { itemNo, r ->
            val lot = r.lotNo.orEmpty()
            val byLot = if (lot.isBlank()) emptyList() else takeLines.filter {
                it.optString("itemNo").equals(itemNo, ignoreCase = true) && it.optString("lotNo").equals(lot, ignoreCase = true)
            }
            if (byLot.size == 1) { scanFilter = ""; openLine(byLot.single(), lot) }
            else { scanFilter = itemNo; status = "TAMAM: '$itemNo' birden fazla satırda — birini seçin" }
        },
        onNoMatch = { r ->
            val scanned = r.value.trim()
            val bin = takeLines.firstOrNull { it.optString("binCode").equals(scanned, ignoreCase = true) }?.optString("binCode")
            if (!bin.isNullOrBlank()) {
                binFilter = bin
                status = "Raf $bin — bu raftan alınacak satırlar"
            } else status = "UYARI: '${r.itemNo ?: r.value}' bu toplama belgesinde yok"
        },
    )

    val binLines = if (binFilter.isBlank()) takeLines else takeLines.filter { it.optString("binCode").equals(binFilter, ignoreCase = true) }
    val filteredLines = if (scanFilter.isBlank()) binLines else binLines.filter {
        matchLinesByBarcode(listOf(it), com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve(scanFilter)).isNotEmpty()
    }
    val displayLines = filteredLines.sortedWith(compareBy(warehouseBinCodeComparator) { it.optString("binCode") })

    val gridDefs = remember(entries) {
        listOf(
            GridColumn("bin", "Raf", true, 128) { pickCell(it, "binCode") },
            GridColumn("itemNo", "Ürün No.", true, 96) { pickCell(it, "itemNo") },
            GridColumn("outstanding", "Kalan", true, 70) { pickNum(pickLineCapacity(it)) },
            GridColumn("entered", "Girilen", true, 70) { l -> pickEnteredQty(l, entries).takeIf { it > 0.0 }?.let(::pickNum).orEmpty() },
            GridColumn("uom", "Birim", true, 58) { pickCell(it, "unitOfMeasureCode") },
            GridColumn("lotNo", "Lot No.", true, 110) { pickCell(it, "lotNo") },
            GridColumn("description", "Açıklama", true, 190) { pickCell(it, "description") },
            GridColumn("sourceNo", "Kaynak", true, 96) { pickCell(it, "sourceNo") },
        )
    }
    val gridColumns = remember(gridDefs) { gridDefs.map { ColumnState(it.key, it.defaultVisible, it.defaultWidth) } }

    Column(Modifier.fillMaxSize()) {
        // Başlık, özet ve satırlar tek kaydırma alanında: küçük el terminalinde
        // ekranın tamamı kayar.
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Belge Listesi") }
            val sources = takeLines.map { pickCell(it, "sourceNo") }.filter { it.isNotBlank() }.distinct()
            val totalQty = takeLines.sumOf { it.optDouble("quantity", 0.0) }
            val handledQty = takeLines.sumOf { it.optDouble("qtyHandled", 0.0) }
            DocHeaderCard(
                title = no,
                subtitle = "Lokasyon: ${h?.optString("locationCode").orEmpty()}" +
                    if (sources.isNotEmpty()) " · Kaynak: ${sources.take(3).joinToString(", ")}${if (sources.size > 3) " +${sources.size - 3}" else ""}" else "",
                percent = if (totalQty > 0.0) (handledQty * 100.0 / totalQty).toInt() else 0,
            )
            if (headerLoaded && linesComplete && !canMutate) {
                Spacer(Modifier.height(6.dp))
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = bcwmsStatus().warning.copy(alpha = 0.16f)),
                ) {
                    Column(Modifier.padding(12.dp)) {
                        Text(documentOwnershipMessage(assignedTo, myUserId), fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        if (myUserId.isNotBlank())
                            Text("Toplamaya başlamak için alttaki düğmeyle belgeyi üzerinize alın.", fontSize = 12.sp)
                    }
                }
            }
            Spacer(Modifier.height(6.dp))
            Surface(
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                shape = RoundedCornerShape(10.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "${postLines.size}/${takeLines.size} satır hazır",
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp,
                        color = if (postLines.isNotEmpty()) bcwmsStatus().success else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.weight(1f))
                    Text("Kaydedilecek miktar: ${pickNum(postQty)}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            Spacer(Modifier.height(4.dp))
            Text(
                "Satırlar (${displayLines.size}/${takeLines.size}) — satıra dokunun ya da ürünü okutun, topladığınız miktarı girin",
                fontWeight = FontWeight.Bold,
                fontSize = 13.sp,
            )
            if (binFilter.isNotBlank()) { ScanFilterChip("Raf $binFilter") { binFilter = "" }; Spacer(Modifier.height(4.dp)) }
            if (scanFilter.isNotBlank()) { ScanFilterChip(scanFilter) { scanFilter = "" }; Spacer(Modifier.height(4.dp)) }
            Spacer(Modifier.height(4.dp))
            LineGrid(
                defs = gridDefs,
                columns = gridColumns,
                rows = displayLines,
                modifier = Modifier.fillMaxWidth(),
                isDone = rowDone,
                isPartial = rowPartial,
                showProgress = true,
                expandRows = true,
                onRowClick = { openLine(it) },
            )
        }

        BottomActionBar {
            if (headerLoaded && linesComplete && !canMutate) {
                OutlinedButton(onClick = { reload() }, enabled = !busy, modifier = Modifier.weight(1f).height(46.dp)) {
                    WmsActionLabel(WmsGlyph.ENTRIES, "Yenile")
                }
                Button(
                    onClick = { takeOver() },
                    enabled = !busy && myUserId.isNotBlank(),
                    modifier = Modifier.weight(2f).height(46.dp),
                ) { Text(if (assignedTo.isBlank()) "Üzerime Al" else "Devral", fontWeight = FontWeight.Bold) }
            } else {
                OutlinedButton(
                    onClick = { reload() },
                    enabled = !busy,
                    modifier = Modifier.weight(0.9f).height(46.dp),
                    contentPadding = PaddingValues(horizontal = 8.dp),
                ) { WmsActionLabel(WmsGlyph.ENTRIES, "Yenile") }
                Button(
                    onClick = { showScan = true },
                    enabled = !busy && canMutate,
                    modifier = Modifier.weight(0.9f).height(46.dp),
                    contentPadding = PaddingValues(horizontal = 8.dp),
                ) { WmsActionLabel(WmsGlyph.SCAN, "Tara") }
                val canPost = canMutate && postLines.isNotEmpty()
                Button(
                    onClick = { showPostConfirm = true },
                    enabled = !busy && canPost,
                    modifier = Modifier.weight(1.4f).height(46.dp),
                    contentPadding = PaddingValues(horizontal = 8.dp),
                ) {
                    Text(if (canPost) "Kaydet · ${postLines.size}" else "Önce miktar gir", fontWeight = FontWeight.Bold, maxLines = 1)
                }
            }
        }
    }

    if (showScan) {
        ScanItemSheet(title = "Ürün Tara", onDismiss = { showScan = false }, onItem = { item, line ->
            showScan = false
            val matches = takeLines.filter { it.optString("itemNo").equals(item.trim(), ignoreCase = true) }
            when {
                line != null && matches.size <= 1 -> openLine(line)
                matches.size > 1 -> { scanFilter = item.trim(); status = "TAMAM: '${item.trim()}' birden fazla satırda — birini seçin" }
                else -> status = "UYARI: '${item.trim()}' bu toplama belgesinde yok"
            }
        }, lines = takeLines, matchKey = "itemNo")
    }

    val ql = qtyLine
    if (ql != null) {
        val lotPolicy = pickLotInputPolicy(listOf(ql))
        val outstanding = pickLineCapacity(ql)
        QuantityDialogSheet(
            title = "Toplanan Miktar · Kalan ${pickNum(outstanding)}",
            itemNo = ql.optString("itemNo"),
            initialQty = pickEnteredQty(ql, entries).takeIf { it > 0.0 } ?: outstanding.takeIf { it > 0.0 } ?: 1.0,
            maximumQuantity = outstanding,
            initialUom = ql.optString("unitOfMeasureCode"),
            initialLot = rawValue(ql, "lotNo").ifBlank { scanLot },
            allowZeroQuantity = true,
            showLotSerial = lotPolicy.visible,
            showSerial = false,
            showSourceLp = lpScanRequired,
            sourceLpRequired = lpScanRequired,
            lotRequired = lotPolicy.required,
            showAvailableLotLookup = lotPolicy.visible,
            autoDetectLotFromStock = lotPolicy.detectFromStock,
            locationCode = rawValue(ql, "locationCode").ifBlank { h?.optString("locationCode").orEmpty() },
            binCode = rawValue(ql, "binCode"),
            variantCode = ql.optString("variantCode"),
            onDismiss = { qtyLine = null },
            onConfirm = { res ->
                qtyLine = null
                confirmLine(ql, res.quantity, res.lotNo, res.sourceLpNo)
            },
        )
    }

    if (showPostConfirm) {
        val partialCount = postLines.count(rowPartial)
        val untouched = takeLines.size - postLines.size
        AlertDialog(
            onDismissRequest = { showPostConfirm = false },
            title = { Text("Toplamayı kaydet", fontWeight = FontWeight.Bold) },
            text = {
                Column {
                    Text("Kaydedilecek satır: ${postLines.size}/${takeLines.size}", fontSize = 14.sp)
                    Text("Toplam miktar: ${pickNum(postQty)}", fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    if (partialCount > 0 || untouched > 0) {
                        Spacer(Modifier.height(6.dp))
                        Text(
                            listOfNotNull(
                                "$partialCount satır kısmi".takeIf { partialCount > 0 },
                                "$untouched satıra miktar girilmedi".takeIf { untouched > 0 },
                            ).joinToString(" · ") + ". Kalan miktar belgede kalır, sonra toplanabilir.",
                            fontSize = 12.sp,
                            color = bcwmsStatus().warning,
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Kayıt, girilen miktarları Business Central'da toplanmış olarak işler ve geri alınamaz.",
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            },
            confirmButton = { Button(onClick = { showPostConfirm = false; register() }) { Text("Kaydet", fontWeight = FontWeight.Bold) } },
            dismissButton = { OutlinedButton(onClick = { showPostConfirm = false }) { Text("Vazgeç") } },
        )
    }
}
