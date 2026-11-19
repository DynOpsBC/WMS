package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter

private fun outQty(value: Double, unit: String): String = receiptLabelQtyText(value, unit)

/**
 * DKÇ "Üretim Çıktısı": üretim emirleri, ne üretilecekti / ne kadarı çıktı.
 * Emre dokununca çıkan lotlar listelenir ve çıkan ürünün etiketi basılır.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DkcProductionOutputTab() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var search by remember { mutableStateOf("") }
    var finished by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<JSONObject?>(null) }

    fun load() {
        if (loading) return
        loading = true
        scope.launch {
            status = "Üretim emirleri yükleniyor..."
            val state = if (finished) "Finished" else "Released"
            val page = BcApi.getAllPages(
                context,
                "productionOrderLines?\$orderby=prodOrderNo desc,lineNo&\$filter=status eq '$state'",
            )
            loading = false
            rows = if (page.complete || page.rows.isNotEmpty()) page.rows else emptyList()
            status = when {
                page.error?.httpCode == 404 ->
                    "HATA: Üretim çıktısı servisi hazır değil. Sistem yöneticinize bildirin."
                !page.complete && page.rows.isEmpty() -> "HATA: Üretim emirleri alınamadı. Yenileyin."
                rows.isEmpty() -> if (finished) "Biten üretim emri yok." else "Açık üretim emri yok."
                else -> "${rows.size} üretim emri satırı" + if (!page.complete) " (ilk kayıtlar)" else ""
            }
        }
    }
    LaunchedEffect(finished) { load() }

    val sel = selected
    if (sel != null) {
        ProductionOutputDetail(line = sel, onBack = { selected = null; load() })
        return
    }

    val shown = rows.filter { productionOutputMatches(it, search) }
    ScrollAwayColumn(Modifier.fillMaxSize().padding(12.dp)) { fullScreenList ->
        Row(verticalAlignment = Alignment.CenterVertically) {
            FilterChip(enabled = !loading, selected = !finished, onClick = { finished = false }, label = { Text("Açık emirler", fontSize = 12.sp) })
            Spacer(Modifier.width(6.dp))
            FilterChip(enabled = !loading, selected = finished, onClick = { finished = true }, label = { Text("Bitenler", fontSize = 12.sp) })
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { load() }, enabled = !loading) { Text(if (loading) "…" else "Yenile") }
        }
        OutlinedTextField(
            value = search,
            onValueChange = { search = it },
            label = { Text("Emir no ya da ürün ara") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(6.dp))
        LazyColumn(fullScreenList, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(shown, key = { "${it.optString("prodOrderNo")}:${it.optInt("lineNo")}" }) { line ->
                ProductionOutputCard(line) { selected = line }
            }
            if (shown.isEmpty() && !loading && rows.isNotEmpty()) item { EmptyState("Aramaya uyan üretim emri yok.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProductionOutputCard(line: JSONObject, onOpen: (() -> Unit)?) {
    val unit = line.optString("unitOfMeasureCode")
    val planned = line.optDouble("quantity", 0.0)
    val done = line.optDouble("finishedQuantity", 0.0)
    val left = line.optDouble("remainingQuantity", 0.0)
    val pct = productionOutputPercent(planned, done)
    val palette = bcwmsStatus()
    val content: @Composable ColumnScope.() -> Unit = {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(line.optString("prodOrderNo"), fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.weight(1f))
                Text("%$pct", fontWeight = FontWeight.Bold, fontSize = 15.sp, color = if (pct >= 100) palette.success else MaterialTheme.colorScheme.primary)
            }
            Text(line.optString("itemNo"), fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
            val desc = line.optString("description")
            if (desc.isNotBlank() && desc != line.optString("itemNo")) Text(desc, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
            Spacer(Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = { (pct.coerceIn(0, 100)) / 100f },
                modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50)),
                color = if (pct >= 100) palette.success else MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.height(8.dp))
            Row(Modifier.fillMaxWidth()) {
                ProductionFigure("Üretilecek", outQty(planned, unit), Modifier.weight(1f))
                ProductionFigure("Çıkan", outQty(done, unit), Modifier.weight(1f), strong = true)
                ProductionFigure("Kalan", outQty(left.coerceAtLeast(0.0), unit), Modifier.weight(1f))
            }
        }
    }
    if (onOpen != null) Card(onClick = onOpen, modifier = Modifier.fillMaxWidth(), content = content)
    else Card(modifier = Modifier.fillMaxWidth(), content = content)
}

@Composable
private fun ProductionFigure(label: String, value: String, modifier: Modifier, strong: Boolean = false) {
    Column(modifier) {
        Text(label, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontSize = if (strong) 16.sp else 14.sp, fontWeight = if (strong) FontWeight.Bold else FontWeight.Medium, maxLines = 1)
    }
}

/** Bir üretim emri satırı: çıkan lotlar ve etiket. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProductionOutputDetail(line: JSONObject, onBack: () -> Unit) {
    androidx.activity.compose.BackHandler { onBack() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val orderNo = line.optString("prodOrderNo")
    val lineNo = line.optInt("lineNo")
    var current by remember(orderNo, lineNo) { mutableStateOf(line) }
    var lots by remember(orderNo, lineNo) { mutableStateOf<List<OutputLot>>(emptyList()) }
    var status by remember(orderNo, lineNo) { mutableStateOf("") }
    var loading by remember(orderNo, lineNo) { mutableStateOf(false) }
    var labelFor by remember(orderNo, lineNo) { mutableStateOf<OutputLot?>(null) }
    var showReport by remember(orderNo, lineNo) { mutableStateOf(false) }
    // Sarfiyat: bileşenler, bugüne kadar tüketilen ve üretim gözündeki stok.
    var components by remember(orderNo, lineNo) { mutableStateOf<List<JSONObject>>(emptyList()) }
    var consumed by remember(orderNo, lineNo) { mutableStateOf<Map<String, Double>>(emptyMap()) }
    var binStock by remember(orderNo, lineNo) { mutableStateOf<Map<String, Double>>(emptyMap()) }
    var consumeFor by remember(orderNo, lineNo) { mutableStateOf<JSONObject?>(null) }
    var consumeMsg by remember(orderNo, lineNo) { mutableStateOf("") }

    fun load() {
        if (loading) return
        loading = true
        scope.launch {
            status = "Çıktılar yükleniyor..."
            lots = emptyList()
            labelFor = null
            val safe = orderNo.replace("'", "''")
            val fresh = BcApi.get(context, "productionOrderLines?\$filter=prodOrderNo eq '$safe' and lineNo eq $lineNo&\$top=1")
            if (fresh.ok) BcApi.parseValueArray(fresh.body).firstOrNull()?.let { current = it }
            val page = BcApi.getAllPages(
                context,
                productionOutputEntriesPath(orderNo, lineNo, current.optString("itemNo")),
            )
            // Bileşenler ve tüketim durumu. Alınamazsa çıktı bölümü yine çalışır.
            val comp = BcApi.getAllPages(context, "productionConsumption?\$top=200&\$filter=prodOrderNo eq '$safe' and prodOrderLineNo eq $lineNo")
            components = if (comp.complete) comp.rows else emptyList()
            val used = BcApi.getAllPages(context, productionConsumptionEntriesPath(orderNo, lineNo))
            consumed = if (used.complete) consumedByItem(used.rows) else emptyMap()
            val stock = mutableMapOf<String, Double>()
            for (c in components) {
                val item = c.optString("itemNo"); val bin = c.optString("binCode")
                if (item.isBlank() || bin.isBlank()) continue
                val r = BcApi.get(context, "binContents?\$filter=itemNo eq '${item.replace("'", "''")}' and binCode eq '${bin.replace("'", "''")}'&\$select=quantity")
                if (r.ok) stock["$item|$bin"] = BcApi.parseValueArray(r.body).sumOf { it.optDouble("quantity", 0.0) }
            }
            binStock = stock
            loading = false
            lots = if (page.complete) productionOutputLots(page.rows) else emptyList()
            status = when {
                !page.complete -> "HATA: Çıktı kayıtlarının tamamı alınamadı. Yenileyin."
                lots.isEmpty() -> "Bu üretim emrinden henüz çıktı kaydı yok."
                else -> "${lots.size} lotta çıktı var. Etiket için lota dokunun."
            }
        }
    }
    LaunchedEffect(orderNo, lineNo) { load() }

    /** Mevcut Üretim > Sarfiyat kaydıyla aynı BC işlemi (productionConsumption.consume). */
    fun consume(c: JSONObject, qty: Double, lotNo: String) {
        if (loading) return
        loading = true
        scope.launch {
            consumeMsg = "Sarfiyat kaydediliyor..."
            val body = JSONObject()
                .put("prodOrderNo", orderNo).put("componentLineNo", c.optInt("componentLineNo"))
                .put("itemNo", c.optString("itemNo")).put("qty", qty).put("lpNo", "")
                .put("lotNo", lotNo).put("serialNo", "").put("binCode", c.optString("binCode")).toString()
            val key = "status='Released',prodOrderNo='${orderNo.replace("'", "''")}'," +
                "prodOrderLineNo=$lineNo,componentLineNo=${c.optInt("componentLineNo")}"
            val r = BcApi.post(context, "productionConsumption($key)/Microsoft.NAV.consume", body)
            loading = false
            consumeMsg = if (r.ok) "TAMAM: ${c.optString("itemNo")} · ${outQty(qty, c.optString("unitOfMeasureCode"))} tüketildi."
                else "HATA: ${BcApi.errorMessage(r.body)}"
            if (r.ok) load()
        }
    }

    val released = current.optString("status").equals("Released", true)
    val stocks = components.map { c ->
        ComponentStock(
            itemNo = c.optString("itemNo"),
            qtyPer = c.optDouble("quantity", 0.0),
            consumed = consumed[c.optString("itemNo")] ?: 0.0,
            remainingOnOrder = c.optDouble("remainingQuantity", 0.0),
            pickedInBin = pickedNotConsumed(c, binStock),
        )
    }
    val pending = pendingConsumption(current.optDouble("finishedQuantity", 0.0), stocks)
    val blockedReason = if (pending.isEmpty()) null
        else "Önce çıkan miktarın sarfiyatını yapın: ${pending.joinToString(", ")}. Sarfiyat tamamlanmadan yeni çıktı bildirilemez."
    val outputCap = maxOutputByPicked(stocks)
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Üretim Emirleri") }
            ProductionOutputCard(current, onOpen = null)
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            Spacer(Modifier.height(6.dp))
            if (lots.isNotEmpty()) Text("Çıkan lotlar", fontWeight = FontWeight.Bold, fontSize = 14.sp)
            Spacer(Modifier.height(4.dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                lots.forEach { lot ->
                    Card(onClick = { if (!loading && lot.unit.isNotBlank()) labelFor = lot }, modifier = Modifier.fillMaxWidth()) {
                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(lot.lotNo.ifBlank { "Lotsuz" }, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                                Text(
                                    listOf(outQty(lot.quantity, lot.unit), productionDateText(lot.lastDate))
                                        .filter { it.isNotBlank() }.joinToString(" · "),
                                    fontSize = 13.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            FilledTonalButton(onClick = { labelFor = lot }, enabled = !loading && lot.unit.isNotBlank()) { WmsActionLabel(WmsGlyph.LABEL, "Etiket") }
                        }
                    }
                }
            }
            if (components.isNotEmpty()) {
                Spacer(Modifier.height(14.dp))
                Text("Sarfiyat — çekilen malzeme ve çıkan miktara göre", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                if (blockedReason != null) Text(blockedReason, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = bcwmsStatus().warning)
                Text("Önce çıktıyı bildirin, sonra bileşeni tüketin. Tüketmek için bileşene dokunun.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                StatusText(consumeMsg)
                Spacer(Modifier.height(4.dp))
                val finished = current.optDouble("finishedQuantity", 0.0)
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    components.forEach { c ->
                        val item = c.optString("itemNo")
                        val cu = c.optString("unitOfMeasureCode")
                        val bin = c.optString("binCode")
                        val inBin = pickedNotConsumed(c, binStock)
                        val needOnly = componentConsumption(finished, c.optDouble("quantity", 0.0), consumed[item] ?: 0.0, c.optDouble("remainingQuantity", 0.0))
                        val state = componentConsumption(finished, c.optDouble("quantity", 0.0), consumed[item] ?: 0.0, c.optDouble("remainingQuantity", 0.0), inBin)
                        // DKC (19 Kas 2026): operatör çektiği malzemeden istediği kadarını
                        // tüketir (10.000 çekip 5.000 tüketebilir); sınır çekilen ve emirde
                        // kalan miktardır. Yeni çıktı yine önceki çıktının sarfiyatına bağlı.
                        val consumeLimit = minOf(
                            c.optDouble("remainingQuantity", 0.0),
                            inBin ?: c.optDouble("remainingQuantity", 0.0),
                        )
                        val canConsume = !loading && released && consumeLimit > 0.0
                        Card(onClick = { if (canConsume) consumeFor = c }, modifier = Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(12.dp)) {
                                Text(item, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                                val desc = c.optString("description")
                                if (desc.isNotBlank() && desc != item) Text(desc, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                                Spacer(Modifier.height(6.dp))
                                Row(Modifier.fillMaxWidth()) {
                                    ProductionFigure("Gereken", outQty(state.neededForOutput, cu), Modifier.weight(1f))
                                    ProductionFigure("Tüketilen", outQty(state.consumed, cu), Modifier.weight(1f))
                                    ProductionFigure("Tüketebileceğiniz", outQty(state.consumableNow, cu), Modifier.weight(1.2f), strong = true)
                                }
                                Spacer(Modifier.height(4.dp))
                                Text(
                                    when {
                                        bin.isBlank() -> "Bileşenin üretim gözü tanımlı değil."
                                        inBin == null -> "$bin gözündeki stok okunamadı."
                                        c.has("qtyPicked") -> "Bu emre toplanan: ${outQty(c.optDouble("qtyPicked", 0.0), cu)} · tüketilmemiş: ${outQty(inBin, cu)}"
                                        else -> "Çekilen ($bin gözünde): ${outQty(inBin, cu)}"
                                    } + if (needOnly.consumableNow > state.consumableNow + 0.000001) " — çekilen kadar tüketilir; kalan için toplama yapın." else "",
                                    fontSize = 12.sp,
                                    color = if (needOnly.consumableNow > state.consumableNow + 0.000001) bcwmsStatus().warning else MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
        BottomActionBar {
            OutlinedButton(onClick = { load() }, enabled = !loading, modifier = Modifier.weight(1f).height(46.dp)) {
                WmsActionLabel(WmsGlyph.ENTRIES, "Yenile")
            }
            Button(onClick = { showReport = true }, enabled = !loading, modifier = Modifier.weight(1.6f).height(46.dp)) {
                Text(if (current.optString("status").equals("Released", true)) "Çıktı Bildir" else "Bildirim Sonucu")
            }
        }
    }

    if (showReport) ProductionPostingSheet(
        newOutputBlockedReason = blockedReason,
        outputCapByPicked = outputCap,
        line = current,
        onDismiss = { showReport = false; load() },
        onPosted = { load() },
        onPrint = { lot -> showReport = false; labelFor = lot },
    )

    consumeFor?.let { c ->
        val item = c.optString("itemNo")
        val cu = c.optString("unitOfMeasureCode")
        val bin = c.optString("binCode")
        val remainingOnOrder = c.optDouble("remainingQuantity", 0.0)
        val inBin = pickedNotConsumed(c, binStock)
        val state = componentConsumption(current.optDouble("finishedQuantity", 0.0), c.optDouble("quantity", 0.0), consumed[item] ?: 0.0, remainingOnOrder, inBin)
        ConsumptionSheet(
            itemNo = item,
            description = c.optString("description"),
            unit = cu,
            locationCode = c.optString("locationCode"),
            binCode = bin,
            pickedInBin = inBin,
            initialQty = state.consumableNow,
            // Çekilen (üretim gözündeki) ve emirde kalan miktardan fazlası girilemez.
            maximumQuantity = minOf(remainingOnOrder, inBin ?: remainingOnOrder).coerceAtLeast(0.0),
            onDismiss = { consumeFor = null },
            onConfirm = { qty, lotNo -> consumeFor = null; consume(c, qty, lotNo) },
        )
    }

    labelFor?.let { lot ->
        ProductionLabelSheet(
            orderNo = orderNo,
            itemNo = current.optString("itemNo"),
            description = current.optString("description"),
            lot = lot,
            onDismiss = { labelFor = null },
        )
    }
}

/**
 * Üretim etiketi: etiketteki miktar ve adet operatörden. Varsayılan miktar lotun
 * net çıktısıdır; ürün palet/bobin başına etiketlenecekse operatör düşürür.
 * Hiçbir şey kendiliğinden yeniden gönderilmez: yanıtı kaybolan iş basılmış olabilir.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProductionLabelSheet(
    orderNo: String,
    itemNo: String,
    description: String,
    lot: OutputLot,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val unit = lot.unit
    val lotNo = lot.lotNo
    var qtyText by remember(lot) {
        mutableStateOf(if (lot.quantity > 0.0) java.math.BigDecimal.valueOf(lot.quantity).stripTrailingZeros().toPlainString() else "")
    }
    var copies by remember(lot) { mutableStateOf(1) }
    var busy by remember { mutableStateOf(false) }
    var attempted by remember(lot) { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    val printer = getDefaultPrinter(context)
    val qty = qtyText.toDoubleOrNull()?.takeIf { it.isFinite() } ?: 0.0

    SheetScaffold(onDismiss = { if (!busy) onDismiss() }, contentPadding = PaddingValues(20.dp)) {
        Text("Üretim etiketi", style = MaterialTheme.typography.titleLarge)
        Text(
            "$orderNo · $itemNo" + if (description.isNotBlank() && description != itemNo) "\n$description" else "",
            fontSize = 13.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text("Etiket yazıcısı: ${printer.ifBlank { "seçilmedi" }}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(10.dp))
        StatusText(status)
        OutlinedTextField(
            value = lotNo,
            onValueChange = {},
            readOnly = true,
            label = { Text("Lot No") },
            singleLine = true,
            enabled = !busy,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(
            value = qtyText,
            onValueChange = { qtyText = normalizeQtyInput(it) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            label = { Text("Etiketteki miktar${if (unit.isNotBlank()) " ($unit)" else ""}") },
            singleLine = true,
            enabled = !busy,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Etiket adedi", modifier = Modifier.weight(1f), fontSize = 15.sp)
            OutlinedButton(
                onClick = { copies = (copies - 1).coerceAtLeast(1) },
                enabled = !busy && copies > 1,
                modifier = Modifier.size(46.dp),
                contentPadding = PaddingValues(0.dp),
            ) { Text("−", fontSize = 20.sp) }
            Text("$copies", fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.width(48.dp), textAlign = TextAlign.Center)
            OutlinedButton(
                onClick = { copies = (copies + 1).coerceAtMost(RECEIPT_LABEL_COPIES_MAX) },
                enabled = !busy && copies < RECEIPT_LABEL_COPIES_MAX,
                modifier = Modifier.size(46.dp),
                contentPadding = PaddingValues(0.dp),
            ) { Text("+", fontSize = 20.sp) }
        }
        Spacer(Modifier.height(14.dp))
        Button(
            enabled = !busy && !attempted && qty > 0.0 && itemNo.isNotBlank() && unit.isNotBlank(),
            modifier = Modifier.fillMaxWidth().height(52.dp),
            onClick = {
                if (printer.isBlank()) {
                    status = "HATA: Etiket yazıcısı seçilmedi. Üstteki yazıcı şeridinden etiket yazıcısını seçin."
                    return@Button
                }
                busy = true
                attempted = true
                scope.launch {
                    val date = LocalDate.now().format(DateTimeFormatter.ofPattern("dd.MM.yyyy"))
                    val batches = receiptLabelBatches(productionLabelRows(itemNo, description, lotNo, qty, unit, copies))
                    var sent = 0
                    var failure = ""
                    for ((i, batch) in batches.withIndex()) {
                        status = "Etiketler gönderiliyor: ${i + 1}/${batches.size}"
                        val body = JSONObject()
                            .put("rowsJson", receiptLabelRowsJson(batch, orderNo, date))
                            .put("printerId", printer)
                            .toString()
                        val r = BcApi.boundAction(context, "items", itemNo, "printProductionLabels", body)
                        if (!r.ok) {
                            failure = QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                            break
                        }
                        sent += batch.sumOf { it.copies }
                    }
                    status = when {
                        failure.isEmpty() -> "TAMAM: $sent etiket $printer yazıcısına gönderildi."
                        sent > 0 -> "UYARI: $copies etiketin $sent adedi gönderildi, kalanı gönderilemedi: $failure Çıktıları kontrol etmeden tekrar basmayın."
                        else -> "HATA: Yazdırma sonucu doğrulanamadı: $failure Tekrar göndermeden önce yazıcıyı kontrol edin."
                    }
                    busy = false
                }
            },
        ) { Text(if (attempted) "Yazdırma isteği tamamlandı" else "Etiketi Yazdır ($copies)", fontWeight = FontWeight.Bold) }
        if (attempted && !busy) Text("Yeniden etiket basmak için bu pencereyi kapatıp lotu tekrar seçin.", fontSize = 12.sp)
        TextButton(onClick = onDismiss, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Kapat") }
        Spacer(Modifier.height(12.dp))
    }
}

/**
 * DKC (19 Kas 2026): sarfiyatta lot seçimi. DKC ürünlerinde lot rafta değil
 * madde defterinde tutulduğu için lotlar raf stoğundan değil, lokasyondaki açık
 * giriş kayıtlarından listelenir. Çıktıdaki "lot ata"nın karşılığı: lot seç,
 * miktarı yaz (çekilenin tamamı olmak zorunda değil), onayla.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ConsumptionSheet(
    itemNo: String,
    description: String,
    unit: String,
    locationCode: String,
    binCode: String,
    pickedInBin: Double?,
    initialQty: Double,
    maximumQuantity: Double,
    onDismiss: () -> Unit,
    onConfirm: (Double, String) -> Unit,
) {
    val context = LocalContext.current
    var lots by remember(itemNo) { mutableStateOf<List<InquiryLotStock>>(emptyList()) }
    var lotTracked by remember(itemNo) { mutableStateOf(false) }
    var loadingLots by remember(itemNo) { mutableStateOf(true) }
    var lotError by remember(itemNo) { mutableStateOf("") }
    var lotNo by remember(itemNo) { mutableStateOf("") }
    // Binlik ayırıcı yok: alan düzenlenince "1.000" → "1,000" (1) olmasın.
    var qtyText by remember(itemNo) { mutableStateOf(consumptionQtyInput(initialQty)) }

    LaunchedEffect(itemNo, locationCode) {
        loadingLots = true
        val safeItem = itemNo.replace("'", "''")
        val item = BcApi.get(context, "items?\$filter=no eq '$safeItem'&\$select=no,lotTrackingRequired&\$top=1")
        lotTracked = item.ok && BcApi.parseValueArray(item.body).firstOrNull()?.optBoolean("lotTrackingRequired") == true
        val locFilter = if (locationCode.isBlank()) "" else " and locationCode eq '${locationCode.replace("'", "''")}'"
        val page = BcApi.getAllPages(
            context,
            "itemLedgerEntries?\$filter=itemNo eq '$safeItem'$locFilter and remainingQuantity gt 0&\$select=entryNo,lotNo,remainingQuantity&\$top=500",
        )
        if (page.complete) {
            lots = inquiryLotStocks(page.rows, emptyList())
            if (lots.size == 1) lotNo = lots.first().lotNo
            lotError = ""
        } else {
            lots = emptyList()
            lotError = "Lot listesi alınamadı. Bağlantıyı kontrol edip pencereyi yeniden açın."
        }
        loadingLots = false
    }

    val qty = qtyText.replace(',', '.').toDoubleOrNull()
    val lotNeeded = lotTracked || lots.isNotEmpty()
    val problem = when {
        loadingLots -> "Lotlar yükleniyor..."
        lotError.isNotBlank() -> lotError
        lotTracked && lots.isEmpty() -> "Bu ürünün $locationCode lokasyonunda stokta lotu yok."
        lotNeeded && lotNo.isBlank() -> "Tüketilecek lotu seçin."
        qty == null || qty <= 0.0 -> "Tüketim miktarını yazın."
        qty > maximumQuantity + 0.00001 -> "En fazla ${receiptLabelQtyText(maximumQuantity, unit)} tüketebilirsiniz (çekilen ve emirde kalan)."
        else -> ""
    }

    SheetScaffold(onDismiss = onDismiss, contentPadding = PaddingValues(20.dp)) {
        Text("Sarfiyat", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text(itemNo, fontWeight = FontWeight.SemiBold)
        if (description.isNotBlank()) Text(description, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (pickedInBin != null) Text(
            "Bu emre toplanan, tüketilmemiş: ${receiptLabelQtyText(pickedInBin, unit)}",
            fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(12.dp))
        Text("1) Lot seçin", fontWeight = FontWeight.Medium)
        Spacer(Modifier.height(6.dp))
        when {
            loadingLots -> LinearProgressIndicator(Modifier.fillMaxWidth())
            lots.isEmpty() -> Text(
                if (lotTracked) "Stokta lot bulunamadı." else "Bu ürün lot takipli değil; lot seçmeden tüketin.",
                fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            else -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                lots.forEach { lot ->
                    val selected = lotNo == lot.lotNo
                    Card(
                        onClick = { lotNo = lot.lotNo },
                        colors = CardDefaults.cardColors(
                            containerColor = if (selected) MaterialTheme.colorScheme.primaryContainer
                                else MaterialTheme.colorScheme.surfaceVariant,
                        ),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            RadioButton(selected = selected, onClick = { lotNo = lot.lotNo })
                            Column(Modifier.weight(1f)) {
                                Text(lot.lotNo, fontWeight = FontWeight.Bold)
                                Text("Stokta: ${receiptLabelQtyText(lot.quantity, "")}".trim(), fontSize = 12.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        Text("2) Tüketim miktarı", fontWeight = FontWeight.Medium)
        Spacer(Modifier.height(6.dp))
        OutlinedTextField(
            value = qtyText,
            onValueChange = { qtyText = normalizeQtyInput(it).replace('.', ',') },
            label = { Text("Miktar ($unit)") },
            supportingText = { Text("En fazla ${receiptLabelQtyText(maximumQuantity, unit)}") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.fillMaxWidth(),
        )
        if (problem.isNotBlank() && !loadingLots) {
            Spacer(Modifier.height(4.dp))
            Text(problem, fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
        }
        Spacer(Modifier.height(12.dp))
        Button(
            onClick = { onConfirm(qty ?: 0.0, if (lots.isEmpty()) "" else lotNo) },
            enabled = problem.isBlank(),
            modifier = Modifier.fillMaxWidth().height(52.dp),
        ) { Text("Tüketimi Onayla", fontWeight = FontWeight.Bold) }
        TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text("Vazgeç") }
        Spacer(Modifier.height(16.dp))
    }
}

/** Miktar alanının ilk değeri: binlik ayırıcısız, ondalık virgüllü (ör. 10000,5). */
internal fun consumptionQtyInput(value: Double): String =
    java.math.BigDecimal.valueOf(value.coerceAtLeast(0.0)).setScale(3, java.math.RoundingMode.DOWN)
        .stripTrailingZeros().toPlainString().replace('.', ',')

/**
 * DKC (19 Kas 2026): BC sarfiyatı bu emre toplama (pick) ile kaydedilen miktarla
 * sınırlar ("a quantity of N remains to be picked"). Gözdeki stok başka emirlerin
 * malzemesi de olabileceği için ölçü olarak toplanan − tüketilen kullanılır;
 * eski BC (alan yok) gözdeki stoğa düşer.
 */
internal fun pickedNotConsumed(component: JSONObject, binStock: Map<String, Double>): Double? =
    if (component.has("qtyPicked"))
        (component.optDouble("qtyPicked", 0.0) - component.optDouble("actConsumptionQty", 0.0)).coerceAtLeast(0.0)
    else binStock["${component.optString("itemNo")}|${component.optString("binCode")}"]
