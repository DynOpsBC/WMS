package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.EmptyState
import com.dynops.bcwms.ui.InfoPill
import com.dynops.bcwms.ui.StatusText
import com.dynops.bcwms.ui.WmsRefreshLabel
import com.dynops.bcwms.ui.normalizeQtyInput
import com.dynops.bcwms.ui.toFiniteDoubleOrNull
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.UUID

/**
 * Transfer Sevk: lokasyonlar arası, fasoncuya veya konsinye müşteriye giden malın sevki ve e-İrsaliyesi.
 *  - Transfer Emirleri: BC'de açılmış, serbest bırakılmış transfer emrini okut, miktarı onayla, sevk et.
 *  - Yeni Transfer: kaynak/hedef ve alıcıyı seç, ürün okut, terminalden transferi oluşturup sevk et.
 *  - e-İrsaliyeler: oluşan e-İrsaliyeleri kontrol et, değiştir, gönder, A4 ya da 80 mm yazdır.
 * Stok BC'de post edilir; e-İrsaliye hatası sevki geri almaz.
 */
@Composable
fun TransferShipModule() {
    var tab by remember { mutableStateOf(0) }
    var openEntryNo by remember { mutableStateOf<Int?>(null) }

    openEntryNo?.let { entryNo ->
        EDespatchReviewSheet(entryNo = entryNo, onClose = { openEntryNo = null })
        return
    }

    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab) {
            Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Transfer Emirleri") })
            Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Yeni Transfer") })
            Tab(selected = tab == 2, onClick = { tab = 2 }, text = { Text("e-İrsaliyeler") })
        }
        when (tab) {
            0 -> TransferOrdersTab(onOpenDespatch = { openEntryNo = it })
            1 -> NewTransferTab(onOpenDespatch = { openEntryNo = it })
            else -> EDespatchListTab(onOpen = { openEntryNo = it })
        }
    }
}

// ---- Transfer Emirleri -------------------------------------------------------------------------------------

@Composable
private fun TransferOrdersTab(onOpenDespatch: (Int) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var orders by remember { mutableStateOf<List<TransferOrderSummary>>(emptyList()) }
    var selected by remember { mutableStateOf<TransferOrderSummary?>(null) }
    var search by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun load(openBarcode: String? = null) {
        scope.launch {
            loading = true
            status = "Transfer emirleri yükleniyor..."
            val result = BcApi.getAllPages(
                context,
                "transferOrders?\$top=500&\$select=no,transferFromCode,transferToCode,transferToName,requiresWhseShipment," +
                    "outstandingQuantity,lineCount,fasonReferenceNo",
            )
            loading = false
            if (!result.complete) {
                status = "HATA: Transfer listesinin tamamı alınamadı. Yenileyin."
                orders = emptyList()
                return@launch
            }
            orders = parseTransferOrders(result.rows).filter { it.outstandingQuantity > 0.0 }
            status = if (orders.isEmpty()) "BOŞ: Sevk bekleyen serbest transfer emri yok." else "TAMAM: ${orders.size} transfer emri"
            openBarcode?.trim()?.takeIf { it.isNotBlank() }?.let { raw ->
                val value = BarcodeIntentResolver.resolve(raw).value.trim()
                orders.firstOrNull { it.no.equals(value, true) || it.no.equals(raw.trim(), true) }
                    ?.let { selected = it }
                    ?: run { status = "HATA: '$value' sevk bekleyen transfer emri değil." }
            }
        }
    }

    LaunchedEffect(Unit) { load() }

    selected?.let { order ->
        TransferOrderShipDetail(
            order = order,
            onBack = { selected = null; load() },
            onOpenDespatch = onOpenDespatch,
        )
        return
    }

    val query = search.trim()
    val shown = orders.filter {
        query.isBlank() || listOf(it.no, it.fromCode, it.toCode, it.toName, it.fasonReferenceNo).any { v -> v.contains(query, true) }
    }
    Column(Modifier.fillMaxSize().padding(12.dp)) {
        ScanField(
            label = "Transfer emri / barkod",
            value = search,
            onValueChange = { search = it },
            modifier = Modifier.fillMaxWidth(),
            enabled = !loading,
            onScanned = { load(it) },
        )
        Spacer(Modifier.height(8.dp))
        Button(onClick = { load() }, enabled = !loading) { WmsRefreshLabel(loading) }
        StatusText(status)
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(shown, key = { it.no }) { order ->
                Card(onClick = { selected = order }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                    Column(Modifier.padding(14.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(order.no, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                            if (order.fasonReferenceNo.isNotBlank()) InfoPill("Fason")
                        }
                        Text("${order.fromCode} → ${order.toCode} · ${order.toName}")
                        Text("${order.lineCount} satır · kalan ${fmtQty(order.outstandingQuantity)}", fontSize = 12.sp, color = Color.Gray)
                        if (order.requiresWhseShipment)
                            Text("Ambar sevkiyatı ile gönderilir (Sevkiyat ekranı)", fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
                    }
                }
            }
            if (shown.isEmpty() && !loading) item { EmptyState("Aramaya uyan transfer emri yok.") }
        }
    }
}

@Composable
private fun TransferOrderShipDetail(order: TransferOrderSummary, onBack: () -> Unit, onOpenDespatch: (Int) -> Unit) {
    androidx.activity.compose.BackHandler { onBack() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var lines by remember { mutableStateOf<List<TransferLineSummary>>(emptyList()) }
    val quantities = remember { mutableStateMapOf<Int, String>() }
    val lots = remember { mutableStateMapOf<Int, String>() }
    val serials = remember { mutableStateMapOf<Int, String>() }
    var scan by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var showConfirm by remember { mutableStateOf(false) }
    var idempotencyKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
    val despatch = rememberDespatchForm()

    fun loadLines() {
        scope.launch {
            busy = true
            val safeNo = order.no.replace("'", "''")
            val result = BcApi.getAllPages(context, "transferOrderLines?\$top=500&\$filter=documentNo eq '$safeNo'")
            busy = false
            if (!result.complete) {
                status = "HATA: Transfer satırlarının tamamı alınamadı."
                return@launch
            }
            lines = parseTransferLines(result.rows)
            lines.forEach { line -> if (quantities[line.lineNo] == null) quantities[line.lineNo] = fmtQty(line.outstandingQuantity) }
            status = "TAMAM: ${lines.size} satır. Miktarları kontrol edin, gerekirse ürünü okutun."
            despatch.resolve(scope, context, order.fromCode, "", order.toCode, lines.firstOrNull { it.toBinCode.isNotBlank() }?.toBinCode.orEmpty())
        }
    }

    LaunchedEffect(order.no) { loadLines() }

    fun entries(): List<TransferShipEntry> = lines.mapNotNull { line ->
        val qty = quantities[line.lineNo]?.replace(',', '.')?.toFiniteDoubleOrNull() ?: 0.0
        if (qty <= 0.0) null else TransferShipEntry(line.lineNo, qty, lots[line.lineNo].orEmpty(), serials[line.lineNo].orEmpty())
    }

    fun ship() {
        showConfirm = false
        scope.launch {
            busy = true
            status = "Transfer sevk ediliyor..."
            val userId = BcApi.currentUserId(context).trim()
            val body = JSONObject()
                .put("linesJson", buildShipLinesJson(entries()))
                .put("overridesJson", buildChangesJson(despatch.changes()).toString())
                .put("userId", userId)
                .put("idempotencyKey", idempotencyKey)
            val api = BcApi.postLongRunning(context, "transferOrders('${order.no.replace("'", "''")}')/Microsoft.NAV.ship", body.toString())
            busy = false
            if (!api.ok) {
                status = if (BcApi.isAmbiguousMutationFailure(api))
                    "HATA: Bağlantı kesildi; sevkin geçip geçmediği bilinmiyor. Aynı ekranda tekrar Sevk Et deyin, çift kayıt oluşmaz."
                else "HATA: ${BcApi.errorMessage(api.body)} (HTTP ${api.httpCode})"
                return@launch
            }
            val result = parseTransferShipResult(api.body)
            idempotencyKey = UUID.randomUUID().toString()
            status = "TAMAM: ${result?.postedShipmentNo.orEmpty().ifBlank { order.no }} sevk edildi." +
                (result?.eDespatch?.let { " " + eDespatchSummaryLine(it) } ?: "")
            if (result != null && result.eDespatchRequired && result.requestEntryNo > 0) onOpenDespatch(result.requestEntryNo)
            else loadLines()
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp)) {
        TextButton(onClick = onBack, enabled = !busy) { Text("‹ Transfer Emirleri") }
        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
            Column(Modifier.padding(14.dp)) {
                Text(order.no, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Text("${order.fromCode} → ${order.toCode} · ${order.toName}")
                if (order.fasonReferenceNo.isNotBlank()) Text("Fason ref: ${order.fasonReferenceNo}", fontSize = 12.sp)
            }
        }
        if (order.requiresWhseShipment) {
            Text(
                "Bu lokasyon ambar sevkiyatı gerektiriyor. Transferi Sevkiyat > Ambar Sevkiyatı ekranından gönderin; e-İrsaliye orada oluşur.",
                color = MaterialTheme.colorScheme.error,
            )
            return@Column
        }
        Spacer(Modifier.height(8.dp))
        ScanField(
            label = "Ürün / GTIN okut",
            value = scan,
            onValueChange = { scan = it },
            modifier = Modifier.fillMaxWidth(),
            enabled = !busy,
            onScanned = { raw ->
                val value = BarcodeIntentResolver.resolve(raw).value.trim()
                val line = matchTransferLine(lines, value)
                if (line == null) status = "HATA: '$value' bu transferde yok."
                else {
                    val current = quantities[line.lineNo]?.replace(',', '.')?.toFiniteDoubleOrNull() ?: 0.0
                    val next = minOf(line.outstandingQuantity, if (current >= line.outstandingQuantity) 1.0 else current + 1.0)
                    quantities[line.lineNo] = fmtQty(next)
                    status = "TAMAM: ${line.itemNo} · ${fmtQty(next)} / ${fmtQty(line.outstandingQuantity)}"
                }
                scan = ""
            },
        )
        StatusText(status)
        lines.forEach { line ->
            Card(Modifier.fillMaxWidth().padding(vertical = 4.dp), shape = RoundedCornerShape(12.dp)) {
                Column(Modifier.padding(12.dp)) {
                    Text("${line.itemNo} · ${line.description}", fontWeight = FontWeight.SemiBold)
                    Text("Kalan ${fmtQty(line.outstandingQuantity)} ${line.unitOfMeasureCode}" + if (line.toBinCode.isNotBlank()) " · hedef raf ${line.toBinCode}" else "", fontSize = 12.sp, color = Color.Gray)
                    OutlinedTextField(
                        quantities[line.lineNo].orEmpty(),
                        { quantities[line.lineNo] = normalizeQtyInput(it) },
                        label = { Text("Sevk miktarı") },
                        singleLine = true,
                        enabled = !busy,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (line.lotRequired)
                        OutlinedTextField(lots[line.lineNo].orEmpty(), { lots[line.lineNo] = it.trim() }, label = { Text("Lot no") }, singleLine = true, enabled = !busy, modifier = Modifier.fillMaxWidth())
                    if (line.serialRequired)
                        OutlinedTextField(serials[line.lineNo].orEmpty(), { serials[line.lineNo] = it.trim() }, label = { Text("Seri no") }, singleLine = true, enabled = !busy, modifier = Modifier.fillMaxWidth())
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        DespatchFormCard(despatch, enabled = !busy)
        Spacer(Modifier.height(10.dp))
        Button(
            onClick = {
                val issue = validateShipEntries(lines, entries())
                    ?: despatch.validate()
                if (issue != null) status = "HATA: $issue" else showConfirm = true
            },
            enabled = !busy && lines.isNotEmpty(),
            modifier = Modifier.fillMaxWidth(),
        ) { Text("Sevk Et ve e-İrsaliye Hazırla") }
    }

    if (showConfirm) AlertDialog(
        onDismissRequest = { showConfirm = false },
        title = { Text("${order.no} sevk edilsin mi?") },
        text = {
            Text(
                "${entries().size} satır · ${fmtQty(entries().sumOf { it.quantity })} birim\n" +
                    "Alıcı: ${despatch.receiverName.value.ifBlank { "eşlemeye göre" }}\n" +
                    "Stok kaynak lokasyondan düşülür. e-İrsaliye taslak olarak hazırlanır; göndermeden önce kontrol edebilirsiniz.",
            )
        },
        confirmButton = { Button(onClick = { ship() }) { Text("Sevk Et") } },
        dismissButton = { TextButton(onClick = { showConfirm = false }) { Text("Vazgeç") } },
    )
}

// ---- Yeni Transfer -------------------------------------------------------------------------------------------

@Composable
private fun NewTransferTab(onOpenDespatch: (Int) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var fromLocation by remember { mutableStateOf("") }
    var toLocation by remember { mutableStateOf("") }
    var toBin by remember { mutableStateOf("") }
    var fromBin by remember { mutableStateOf("") }
    var scan by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var showConfirm by remember { mutableStateOf(false) }
    var idempotencyKey by remember { mutableStateOf(UUID.randomUUID().toString()) }
    var locations by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    val lines = remember { mutableStateListOf<NewTransferLine>() }
    val despatch = rememberDespatchForm()

    LaunchedEffect(Unit) {
        val result = BcApi.getAllPages(context, "locations?\$top=200&\$select=code,name,useAsInTransit")
        if (result.complete) locations = result.rows.filter { !it.optBoolean("useAsInTransit") }
    }

    fun addScanned(raw: String) {
        val value = BarcodeIntentResolver.resolve(raw).value.trim()
        if (value.isEmpty()) return
        scope.launch {
            val safe = value.replace("'", "''")
            val item = BcApi.get(context, "items?\$top=1&\$filter=no eq '$safe'&\$select=no,description,baseUnitOfMeasure")
            val row = runCatching { JSONObject(item.body).getJSONArray("value").optJSONObject(0) }.getOrNull()
            if (!item.ok || row == null) {
                status = "HATA: '$value' ürünü bulunamadı."
                return@launch
            }
            val itemNo = row.optString("no")
            addOrIncrement(lines, itemNo, fromBin)
            status = "TAMAM: $itemNo eklendi (${row.optString("description")})."
        }
        scan = ""
    }

    fun createAndShip() {
        showConfirm = false
        scope.launch {
            busy = true
            status = "Transfer oluşturuluyor ve sevk ediliyor..."
            val userId = BcApi.currentUserId(context).trim()
            val requestJson = buildCreateAndShipJson(fromLocation, toLocation, toBin, lines.toList(), despatch.changes())
            val body = JSONObject().put("requestJson", requestJson).put("userId", userId).put("idempotencyKey", idempotencyKey)
            val api = BcApi.postLongRunning(context, "transferOps('')/Microsoft.NAV.createAndShip", body.toString())
            busy = false
            if (!api.ok) {
                status = if (BcApi.isAmbiguousMutationFailure(api))
                    "HATA: Bağlantı kesildi; sevkin geçip geçmediği bilinmiyor. Aynı ekranda tekrar deneyin, çift kayıt oluşmaz."
                else "HATA: ${BcApi.errorMessage(api.body)} (HTTP ${api.httpCode})"
                return@launch
            }
            val result = parseTransferShipResult(api.body)
            idempotencyKey = UUID.randomUUID().toString()
            lines.clear()
            status = "TAMAM: ${result?.transferOrderNo.orEmpty()} oluşturuldu, ${result?.postedShipmentNo.orEmpty()} sevk edildi."
            if (result != null && result.eDespatchRequired && result.requestEntryNo > 0) onOpenDespatch(result.requestEntryNo)
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp)) {
        Text("Nereden nereye?", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        LocationPicker("Kaynak lokasyon", fromLocation, locations, enabled = !busy) { fromLocation = it }
        LocationPicker("Hedef lokasyon", toLocation, locations, enabled = !busy) {
            toLocation = it
            despatch.resolve(scope, context, fromLocation, fromBin, it, toBin)
        }
        OutlinedTextField(fromBin, { fromBin = it.uppercase() }, label = { Text("Kaynak raf (isteğe bağlı)") }, singleLine = true, enabled = !busy, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(
            toBin,
            { toBin = it.uppercase() },
            label = { Text("Hedef raf (fasoncu/konsinye rafı)") },
            singleLine = true,
            enabled = !busy,
            modifier = Modifier.fillMaxWidth(),
        )
        TextButton(onClick = { despatch.resolve(scope, context, fromLocation, fromBin, toLocation, toBin) }, enabled = !busy && toLocation.isNotBlank()) {
            Text("Alıcıyı eşlemeden getir")
        }
        Spacer(Modifier.height(8.dp))
        DespatchFormCard(despatch, enabled = !busy)
        Spacer(Modifier.height(8.dp))
        Text("Ürünler", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        ScanField(
            label = "Ürün / GTIN okut",
            value = scan,
            onValueChange = { scan = it },
            modifier = Modifier.fillMaxWidth(),
            enabled = !busy,
            onScanned = { addScanned(it) },
        )
        StatusText(status)
        lines.forEachIndexed { index, line ->
            Card(Modifier.fillMaxWidth().padding(vertical = 4.dp), shape = RoundedCornerShape(12.dp)) {
                Column(Modifier.padding(12.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(line.itemNo, fontWeight = FontWeight.SemiBold)
                        TextButton(onClick = { lines.removeAt(index) }, enabled = !busy) { Text("Sil") }
                    }
                    OutlinedTextField(
                        fmtQty(line.quantity),
                        { raw -> lines[index] = line.copy(quantity = normalizeQtyInput(raw).replace(',', '.').toFiniteDoubleOrNull() ?: 0.0) },
                        label = { Text("Miktar") }, singleLine = true, enabled = !busy, modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(line.lotNo, { lines[index] = line.copy(lotNo = it.trim()) }, label = { Text("Lot no (takipliyse)") }, singleLine = true, enabled = !busy, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(line.serialNo, { lines[index] = line.copy(serialNo = it.trim()) }, label = { Text("Seri no (takipliyse)") }, singleLine = true, enabled = !busy, modifier = Modifier.fillMaxWidth())
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        Button(
            onClick = {
                val issue = validateNewTransfer(fromLocation, toLocation, lines) ?: despatch.validate()
                if (issue != null) status = "HATA: $issue" else showConfirm = true
            },
            enabled = !busy && lines.isNotEmpty(),
            modifier = Modifier.fillMaxWidth(),
        ) { Text("Transferi Oluştur ve Sevk Et") }
    }

    if (showConfirm) AlertDialog(
        onDismissRequest = { showConfirm = false },
        title = { Text("Yeni transfer sevk edilsin mi?") },
        text = {
            Text(
                "$fromLocation → $toLocation${if (toBin.isNotBlank()) " / $toBin" else ""}\n" +
                    "${lines.size} satır · ${fmtQty(lines.sumOf { it.quantity })} birim\n" +
                    "Alıcı: ${despatch.receiverName.value.ifBlank { "eşlemeye göre" }}",
            )
        },
        confirmButton = { Button(onClick = { createAndShip() }) { Text("Sevk Et") } },
        dismissButton = { TextButton(onClick = { showConfirm = false }) { Text("Vazgeç") } },
    )
}

internal fun addOrIncrement(lines: SnapshotStateList<NewTransferLine>, itemNo: String, fromBin: String) {
    val index = lines.indexOfFirst { it.itemNo == itemNo && it.lotNo.isBlank() && it.serialNo.isBlank() }
    if (index >= 0) lines[index] = lines[index].copy(quantity = lines[index].quantity + 1.0)
    else lines.add(NewTransferLine(itemNo = itemNo, quantity = 1.0, fromBinCode = fromBin))
}

@Composable
private fun LocationPicker(label: String, value: String, locations: List<JSONObject>, enabled: Boolean, onChange: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        OutlinedTextField(
            value, { onChange(it.uppercase()) },
            label = { Text(label) },
            singleLine = true,
            enabled = enabled,
            modifier = Modifier.fillMaxWidth(),
            trailingIcon = { TextButton(onClick = { expanded = true }, enabled = enabled && locations.isNotEmpty()) { Text("Seç") } },
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            locations.forEach { location ->
                DropdownMenuItem(
                    text = { Text("${location.optString("code")} · ${location.optString("name")}") },
                    onClick = { onChange(location.optString("code")); expanded = false },
                )
            }
        }
    }
}

// ---- e-İrsaliyeler -------------------------------------------------------------------------------------------

@Composable
private fun EDespatchListTab(onOpen: (Int) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var onlyOpen by remember { mutableStateOf(true) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true
            val filter = if (onlyOpen) "&\$filter=status ne 'Sent' and status ne 'Accepted' and status ne 'NotRequired' and status ne 'Cancelled'" else ""
            val result = BcApi.getAllPages(context, "eDespatchRequests?\$top=200$filter", maxPages = 2)
            loading = false
            rows = result.rows
            status = if (!result.complete) "UYARI: Liste eksik olabilir. Yenileyin." else if (rows.isEmpty()) "BOŞ: e-İrsaliye yok." else "TAMAM: ${rows.size} e-İrsaliye"
        }
    }

    LaunchedEffect(onlyOpen) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Button(onClick = { load() }, enabled = !loading) { WmsRefreshLabel(loading) }
            Spacer(Modifier.width(8.dp))
            Checkbox(checked = onlyOpen, onCheckedChange = { onlyOpen = it })
            Text("Yalnız bekleyenler")
        }
        StatusText(status)
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(rows, key = { it.optInt("entryNo") }) { row ->
                val rowStatus = EDespatchStatus.fromValue(row.opt("status"))
                Card(onClick = { onOpen(row.optInt("entryNo")) }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                    Column(Modifier.padding(14.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(row.optString("eDespatchNo").ifBlank { "#${row.optInt("entryNo")}" }, fontWeight = FontWeight.Bold)
                            InfoPill(rowStatus.label)
                        }
                        Text("${row.optString("sourceType")} ${row.optString("sourceNo")}", fontSize = 12.sp)
                        Text("${row.optString("locationCode")} → ${row.optString("toLocationCode")} ${row.optString("toBinCode")}", fontSize = 12.sp)
                        Text(row.optString("receiverName").ifBlank { "Alıcı belirlenmedi" }, fontSize = 12.sp, color = Color.Gray)
                        row.optString("lastError").takeIf { it.isNotBlank() && rowStatus == EDespatchStatus.Error }?.let {
                            Text(it.take(140), fontSize = 11.sp, color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Gösterilecek e-İrsaliye yok.") }
        }
    }
}

// ---- Ortak: alıcı ve taşıma formu ----------------------------------------------------------------------------

/** Sevkten önce seçilen alıcı ve taşıma bilgisi; BC'ye overridesJson olarak gider. */
internal class DespatchFormState {
    val receiverType = mutableStateOf(EDespatchReceiverType.Auto)
    val receiverNo = mutableStateOf("")
    val receiverName = mutableStateOf("")
    val receiverAddressCode = mutableStateOf("")
    val purpose = mutableStateOf(EDespatchPurpose.Unset)
    val plate = mutableStateOf("")
    val driverFirst = mutableStateOf("")
    val driverFamily = mutableStateOf("")
    val driverId = mutableStateOf("")
    val agent = mutableStateOf("")
    val note = mutableStateOf("")
    val previewText = mutableStateOf("")
    val requireVehicle = mutableStateOf(false)
    val receiverEditedByUser = mutableStateOf(false)

    fun changes(): EDespatchChanges = EDespatchChanges(
        receiverType = if (receiverEditedByUser.value) receiverType.value else null,
        receiverNo = if (receiverEditedByUser.value) receiverNo.value else null,
        receiverAddressCode = if (receiverEditedByUser.value) receiverAddressCode.value else null,
        purpose = purpose.value.takeIf { it != EDespatchPurpose.Unset },
        vehiclePlateNo = plate.value.takeIf { it.isNotBlank() },
        driverFirstName = driverFirst.value.takeIf { it.isNotBlank() },
        driverFamilyName = driverFamily.value.takeIf { it.isNotBlank() },
        driverIdentificationNo = driverId.value.takeIf { it.isNotBlank() },
        shippingAgentCode = agent.value.takeIf { it.isNotBlank() },
        note = note.value.takeIf { it.isNotBlank() },
    )

    fun validate(): String? =
        if (requireVehicle.value) validateVehicleInfo(plate.value, driverFirst.value, driverFamily.value, driverId.value, agent.value, true)
        else validateVehicleInfo(plate.value, driverFirst.value, driverFamily.value, driverId.value, agent.value, false)

    /** BC'deki alıcı eşlemesini (lokasyon/raf) okuyup forma yazar; kullanıcı alıcıyı değiştirdiyse dokunmaz. */
    fun resolve(scope: kotlinx.coroutines.CoroutineScope, context: android.content.Context, fromLocation: String, fromBin: String, toLocation: String, toBin: String) {
        if (toLocation.isBlank()) return
        scope.launch {
            val setup = BcApi.get(context, "transferOps?\$top=1")
            if (setup.ok) runCatching {
                JSONObject(setup.body).getJSONArray("value").optJSONObject(0)?.let { requireVehicle.value = it.optBoolean("eDespatchRequireVehicle") }
            }
            val body = JSONObject()
                .put("fromLocationCode", fromLocation.trim().uppercase())
                .put("fromBinCode", fromBin.trim().uppercase())
                .put("toLocationCode", toLocation.trim().uppercase())
                .put("toBinCode", toBin.trim().uppercase())
            val api = BcApi.post(context, "transferOps('')/Microsoft.NAV.resolveReceiver", body.toString())
            val json = if (api.ok) parseActionJson(api.body) else null
            if (json == null) {
                previewText.value = "Alıcı eşlemesi okunamadı."
                return@launch
            }
            if (!json.optBoolean("providerConnected")) {
                previewText.value = "e-İrsaliye sağlayıcısı bağlı değil; sevk sonrası sevk fişi basılabilir."
                return@launch
            }
            if (!receiverEditedByUser.value) {
                receiverType.value = EDespatchReceiverType.fromValue(json.opt("receiverType"))
                receiverNo.value = json.optString("receiverNo")
                receiverName.value = json.optString("receiverName")
                receiverAddressCode.value = json.optString("receiverAddressCode")
                if (purpose.value == EDespatchPurpose.Unset) purpose.value = EDespatchPurpose.fromValue(json.opt("purpose"))
            }
            if (plate.value.isBlank()) plate.value = json.optString("vehiclePlateNo")
            if (driverFirst.value.isBlank()) driverFirst.value = json.optString("driverFirstName")
            if (driverFamily.value.isBlank()) driverFamily.value = json.optString("driverFamilyName")
            if (agent.value.isBlank()) agent.value = json.optString("shippingAgentCode")
            previewText.value = if (json.optBoolean("eDespatchRequired"))
                "e-İrsaliye kesilecek · ${json.optString("resolvedFrom")} · ${json.optString("deliveryAddress")}"
            else "e-İrsaliye gerekmiyor: ${json.optString("skipReason")}"
        }
    }
}

@Composable
internal fun rememberDespatchForm(): DespatchFormState = remember { DespatchFormState() }

@Composable
internal fun DespatchFormCard(form: DespatchFormState, enabled: Boolean) {
    var showPicker by remember { mutableStateOf(false) }
    Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
        Column(Modifier.padding(12.dp)) {
            Text("Alıcı ve Taşıma (e-İrsaliye)", fontWeight = FontWeight.Bold)
            if (form.previewText.value.isNotBlank()) Text(form.previewText.value, fontSize = 12.sp, color = Color.Gray)
            Text(
                "${form.receiverType.value.label}: ${form.receiverName.value.ifBlank { form.receiverNo.value.ifBlank { "eşlemeye göre" } }}" +
                    if (form.receiverAddressCode.value.isNotBlank()) " · adres ${form.receiverAddressCode.value}" else "",
            )
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                EDespatchReceiverType.entries.filter { it != EDespatchReceiverType.Auto }.forEach { type ->
                    OutlinedButton(
                        onClick = {
                            form.receiverEditedByUser.value = true
                            form.receiverType.value = type
                            form.receiverNo.value = ""
                            form.receiverAddressCode.value = ""
                            form.receiverName.value = if (type == EDespatchReceiverType.OwnCompany) "Kendi şirketim" else ""
                            if (type != EDespatchReceiverType.OwnCompany) showPicker = true
                        },
                        enabled = enabled,
                    ) { Text(type.label, fontSize = 11.sp) }
                }
            }
            OutlinedTextField(form.plate.value, { form.plate.value = normalizePlate(it) }, label = { Text("Araç plakası") }, singleLine = true, enabled = enabled, modifier = Modifier.fillMaxWidth())
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                OutlinedTextField(form.driverFirst.value, { form.driverFirst.value = it }, label = { Text("Şoför adı") }, singleLine = true, enabled = enabled, modifier = Modifier.weight(1f))
                OutlinedTextField(form.driverFamily.value, { form.driverFamily.value = it }, label = { Text("Soyadı") }, singleLine = true, enabled = enabled, modifier = Modifier.weight(1f))
            }
            OutlinedTextField(form.driverId.value, { form.driverId.value = it.filter(Char::isDigit).take(11) }, label = { Text("Şoför TCKN") }, singleLine = true, enabled = enabled, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(form.agent.value, { form.agent.value = it.uppercase() }, label = { Text("Nakliyeci kodu (varsa)") }, singleLine = true, enabled = enabled, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(form.note.value, { form.note.value = it.take(250) }, label = { Text("e-İrsaliye notu") }, enabled = enabled, modifier = Modifier.fillMaxWidth())
        }
    }
    if (showPicker) ReceiverPickerDialog(
        receiverType = form.receiverType.value,
        onDismiss = { showPicker = false },
        onPicked = { no, name, addressCode ->
            form.receiverNo.value = no
            form.receiverName.value = name
            form.receiverAddressCode.value = addressCode
            showPicker = false
        },
    )
}
