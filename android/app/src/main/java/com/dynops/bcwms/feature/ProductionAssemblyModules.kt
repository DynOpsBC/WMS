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
 * Production — WI §10.7-10.8 parity.
 * Two tabs: Consumption (component scan -> consume) and Output (routing line -> report output -> new LP).
 * BC: productionConsumption.consume(...) and productionOutput.report(...) bound actions (warehouse/v2.0).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProductionModule() {
    var tab by remember { mutableStateOf(0) }
    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab) {
            Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Sarfiyat") })
            Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Çıktı") })
        }
        when (tab) {
            0 -> ConsumptionTab()
            else -> OutputTab()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ConsumptionTab() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val navigator = com.dynops.bcwms.LocalNavigator.current
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var consumeLine by remember { mutableStateOf<JSONObject?>(null) }
    var selectedOrderNo by remember { mutableStateOf<String?>(null) }
    var search by remember { mutableStateOf("") }
    var columns by remember { mutableStateOf(ColumnPrefs.get(context, "consumption", GridColumns.consumption)) }
    var showColumns by remember { mutableStateOf(false) }
    var scanFilter by remember { mutableStateOf("") }

    fun load() {
        scope.launch {
            loading = true; status = "Bileşenler yükleniyor..."
            val filter = com.dynops.bcwms.ui.buildODataFilter(com.dynops.bcwms.ui.searchClause("prodOrderNo", search))
            val r = BcApi.get(context, "productionConsumption?\$top=500&\$orderby=prodOrderNo desc&\$select=prodOrderNo,prodOrderLineNo,componentLineNo,itemNo,description,quantity,remainingQuantity,binCode,locationCode,status,producedItemNo,producedItemDescription,productionQuantity,dueDate$filter")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Sarfiyat listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "BOŞ: Released üretim bileşeni yok (HTTP ${r.httpCode})"
                else "TAMAM: ${rows.map { it.optString("prodOrderNo") }.distinct().size} üretim emri · ${rows.size} bileşen"

            if (selectedOrderNo != null && rows.none { it.optString("prodOrderNo") == selectedOrderNo })
                selectedOrderNo = null
        }
    }
    LaunchedEffect(Unit) { load() }

    val selectedRows = selectedOrderNo?.let { no -> rows.filter { it.optString("prodOrderNo") == no } }.orEmpty()

    // Barkod taraması yalnızca seçilen üretim emrinin bileşenlerinde arama yapar.
    // Böylece aynı malzeme başka bir üretim emrine yanlışlıkla sarf edilmez.
    DocumentScanHandler(
        enabled = selectedOrderNo != null && consumeLine == null && !loading,
        lines = selectedRows,
        onSingleMatch = { line, _ -> scanFilter = ""; consumeLine = line },
        onMultiMatch = { itemNo, _ -> scanFilter = itemNo; status = "TAMAM: '$itemNo' için birden fazla satır — birini seçin" },
        onNoMatch = { r -> status = "⚠️ '${r.itemNo ?: r.value}' bu belgede yok" },
    )
    val displayRows = if (scanFilter.isBlank()) selectedRows else selectedRows.filter {
        matchLinesByBarcode(listOf(it), BarcodeIntentResolver.resolve(scanFilter)).isNotEmpty()
    }

    fun createPick() {
        val firstLine = selectedRows.firstOrNull() ?: return
        scope.launch {
            loading = true
            status = "Ambar Toplama oluşturuluyor..."
            val key = "status='${firstLine.optString("status").ifBlank { BcEnum.ProdOrderStatus.RELEASED }}'," +
                "prodOrderNo='${firstLine.optString("prodOrderNo")}'," +
                "prodOrderLineNo=${firstLine.optInt("prodOrderLineNo")}," +
                "componentLineNo=${firstLine.optInt("componentLineNo")}"
            val r = BcApi.post(context, "productionConsumption($key)/Microsoft.NAV.createPick", "{}")
            loading = false
            if (r.ok) {
                val pickNo = BcApi.scalarValue(r.body)
                if (pickNo.isBlank()) {
                    status = "HATA: Pick oluştu ancak belge numarası alınamadı."
                } else {
                    status = "TAMAM: $pickNo oluşturuldu"
                    com.dynops.bcwms.WhsePickNavigation.request(pickNo)
                    navigator(com.dynops.bcwms.Screen.Shipping)
                }
            } else {
                status = "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            }
        }
    }

    if (selectedOrderNo == null) {
        val grouped = rows.groupBy { it.optString("prodOrderNo") }.filterKeys { it.isNotBlank() }
        Column(Modifier.fillMaxSize().padding(12.dp)) {
            Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
            Spacer(Modifier.height(8.dp))
            com.dynops.bcwms.ui.DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() }, label = "PÜ no ile ara")
            Spacer(Modifier.height(4.dp))
            StatusText(status)
            Spacer(Modifier.height(8.dp))
            Text("Üretim Emirleri (${grouped.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
            Text("Bileşenleri görmek için üretim emrine dokunun.", fontSize = 12.sp, color = Color.Gray)
            Spacer(Modifier.height(8.dp))
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                grouped.forEach { (orderNo, lines) ->
                    item(key = orderNo) {
                        val header = lines.first()
                        val remaining = lines.sumOf { it.optDouble("remainingQuantity") }
                        Card(
                            onClick = { selectedOrderNo = orderNo; scanFilter = "" },
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(12.dp),
                        ) {
                            Column(Modifier.padding(14.dp)) {
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Text(orderNo, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                                    Text("${lines.size} bileşen", fontSize = 12.sp, color = MaterialTheme.colorScheme.primary)
                                }
                                Text(
                                    "${header.optString("producedItemNo")} · ${header.optString("producedItemDescription")}",
                                    fontWeight = FontWeight.Medium,
                                )
                                Text(
                                    "Üretim miktarı: ${fmt(header.optDouble("productionQuantity"))} · Bileşen kalan: ${fmt(remaining)}",
                                    fontSize = 12.sp,
                                    color = Color.Gray,
                                )
                                Text(
                                    "Lokasyon: ${header.optString("locationCode").ifBlank { "-" }} · Termin: ${header.optString("dueDate").ifBlank { "-" }}",
                                    fontSize = 12.sp,
                                    color = Color.Gray,
                                )
                            }
                        }
                    }
                }
                if (grouped.isEmpty() && !loading) item { EmptyState("Açık üretim emri yok.") }
            }
        }
    } else {
        val header = selectedRows.firstOrNull()
        Column(Modifier.fillMaxSize().padding(12.dp)) {
            TextButton(onClick = { selectedOrderNo = null; scanFilter = "" }) { Text("‹ Üretim Emri Listesi") }
            DocHeaderCard(
                title = selectedOrderNo.orEmpty(),
                subtitle = "Ürün: ${header?.optString("producedItemNo").orEmpty()} — ${header?.optString("producedItemDescription").orEmpty()}\n" +
                    "Üretim miktarı: ${fmt(header?.optDouble("productionQuantity") ?: 0.0)} · Lokasyon: ${header?.optString("locationCode").orEmpty()}",
            )
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Button(onClick = { createPick() }, enabled = !loading && selectedRows.isNotEmpty()) {
                    Text(if (loading) "..." else "📦 Pick Et")
                }
                Spacer(Modifier.width(8.dp))
                OutlinedButton(onClick = { load() }, enabled = !loading) { Text("🔄 Yenile") }
            }
            Spacer(Modifier.height(4.dp))
            StatusText(status)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Bileşenler (${displayRows.size}/${selectedRows.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { showColumns = true }) { Text("⚙ Kolonlar", fontSize = 12.sp) }
            }
            if (scanFilter.isNotBlank()) { ScanFilterChip(scanFilter) { scanFilter = "" }; Spacer(Modifier.height(4.dp)) }
            LineGrid(
                defs = GridColumns.consumption,
                columns = columns,
                rows = displayRows,
                modifier = Modifier.weight(1f),
                isDone = { it.optDouble("remainingQuantity") <= 0.0 },
                onRowClick = { consumeLine = it },
            )
        }
        if (showColumns) {
            ChooseColumnsSheet(GridColumns.consumption, columns, onDismiss = { showColumns = false }) { c ->
                columns = c; ColumnPrefs.save(context, "consumption", c); showColumns = false
            }
        }
    }

    val cl = consumeLine
    if (cl != null) {
        ConsumeSheet(
            line = cl,
            onDismiss = { consumeLine = null },
            onConfirm = { qty, lpNo, lotNo, serialNo, binCode ->
                consumeLine = null
                scope.launch {
                    loading = true; status = "Sarfiyat işleniyor..."
                    val body = JSONObject().apply {
                        put("prodOrderNo", cl.optString("prodOrderNo"))
                        put("componentLineNo", cl.optInt("componentLineNo"))
                        put("itemNo", cl.optString("itemNo"))
                        put("qty", qty)
                        put("lpNo", lpNo)
                        put("lotNo", lotNo)
                        put("serialNo", serialNo)
                        put("binCode", binCode.ifBlank { cl.optString("binCode") })
                    }.toString()
                    // Composite-key bound action target (status/prodOrderNo/prodOrderLineNo/componentLineNo).
                    val key = "status='${cl.optString("status").ifBlank { BcEnum.ProdOrderStatus.RELEASED }}'," +
                        "prodOrderNo='${cl.optString("prodOrderNo")}'," +
                        "prodOrderLineNo=${cl.optInt("prodOrderLineNo")}," +
                        "componentLineNo=${cl.optInt("componentLineNo")}"
                    val r = BcApi.post(context, "productionConsumption($key)/Microsoft.NAV.consume", body)
                    loading = false
                    status = if (r.ok) "TAMAM: Sarfiyat kaydedildi (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                    if (r.ok) load()
                }
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ConsumeSheet(line: JSONObject, onDismiss: () -> Unit, onConfirm: (qty: Double, lpNo: String, lotNo: String, serialNo: String, binCode: String) -> Unit) {
    var qty by remember { mutableStateOf(line.optDouble("remainingQuantity").takeIf { it > 0 }?.let { fmt(it) } ?: "1") }
    var lp by remember { mutableStateOf("") }
    var lot by remember { mutableStateOf("") }
    var serial by remember { mutableStateOf("") }
    var bin by remember { mutableStateOf(line.optString("binCode")) }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text("Sarfiyat — ${line.optString("itemNo")}", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Spacer(Modifier.height(12.dp))
        ScanField("Bileşen / LP", lp, { lp = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            val r = BarcodeIntentResolver.resolve(it)
            lp = r.value
            if (r.lotNo != null) lot = r.lotNo
        })
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(qty, { qty = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Miktar") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(bin, { bin = it }, label = { Text("Bin") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(lot, { lot = it }, label = { Text("Lot No (opsiyonel)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(serial, { serial = it }, label = { Text("Seri No (opsiyonel)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Button(modifier = Modifier.fillMaxWidth(), enabled = (qty.toDoubleOrNull() ?: 0.0) > 0, onClick = {
            onConfirm(qty.toDoubleOrNull() ?: 0.0, lp.trim(), lot.trim(), serial.trim(), bin.trim())
        }) { Text("Sarfiyatı Onayla") }
        Spacer(Modifier.height(24.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OutputTab() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var outputLine by remember { mutableStateOf<JSONObject?>(null) }
    var search by remember { mutableStateOf("") }
    var columns by remember { mutableStateOf(ColumnPrefs.get(context, "output", GridColumns.output)) }
    var showColumns by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Rota satırları yükleniyor..."
            val filter = com.dynops.bcwms.ui.buildODataFilter(com.dynops.bcwms.ui.searchClause("prodOrderNo", search))
            val r = BcApi.get(context, "productionOutput?\$top=200&\$orderby=prodOrderNo desc&\$select=prodOrderNo,routingLineNo,routingNo,operationNo,workCenterNo,description,runTime,status$filter")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Çıktı listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "BOŞ: Released üretim rota satırı yok (HTTP ${r.httpCode})"
                else "TAMAM: ${rows.size} rota satırı (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(Unit) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        Spacer(Modifier.height(8.dp))
        com.dynops.bcwms.ui.DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() }, label = "PÜ no ile ara")
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(4.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Rota Satırları (${rows.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { showColumns = true }) { Text("⚙ Kolonlar", fontSize = 12.sp) }
        }
        LineGrid(
            defs = GridColumns.output,
            columns = columns,
            rows = rows,
            modifier = Modifier.weight(1f),
            onRowClick = { outputLine = it },
        )
    }
    if (showColumns) {
        ChooseColumnsSheet(GridColumns.output, columns, onDismiss = { showColumns = false }) { c ->
            columns = c; ColumnPrefs.save(context, "output", c); showColumns = false
        }
    }

    val ol = outputLine
    if (ol != null) {
        OutputSheet(
            line = ol,
            onDismiss = { outputLine = null },
            onConfirm = { outQty, scrapQty, runtime, newLpTemplate, binCode ->
                outputLine = null
                scope.launch {
                    loading = true; status = "Çıktı işleniyor..."
                    val body = JSONObject().apply {
                        put("prodOrderNo", ol.optString("prodOrderNo"))
                        put("routingLineNo", ol.optInt("routingLineNo"))
                        put("outputQty", outQty)
                        put("scrapQty", scrapQty)
                        put("runtime", runtime)
                        put("newLpTemplate", newLpTemplate)
                        put("binCode", binCode)
                    }.toString()
                    val key = "status='${ol.optString("status").ifBlank { BcEnum.ProdOrderStatus.RELEASED }}'," +
                        "prodOrderNo='${ol.optString("prodOrderNo")}'," +
                        "routingLineNo=${ol.optInt("routingLineNo")}," +
                        "routingNo='${ol.optString("routingNo")}'," +
                        "operationNo='${ol.optString("operationNo")}'"
                    val r = BcApi.post(context, "productionOutput($key)/Microsoft.NAV.report", body)
                    loading = false
                    status = if (r.ok) {
                        val lp = BcApi.scalarValue(r.body)
                        "TAMAM: Çıktı kaydedildi${if (lp.isNotBlank()) " → LP $lp" else ""} (HTTP ${r.httpCode})"
                    } else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                    if (r.ok) load()
                }
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OutputSheet(line: JSONObject, onDismiss: () -> Unit, onConfirm: (outQty: Double, scrapQty: Double, runtime: Double, newLpTemplate: String, binCode: String) -> Unit) {
    var outQty by remember { mutableStateOf("1") }
    var scrapQty by remember { mutableStateOf("0") }
    var runtime by remember { mutableStateOf(fmt(line.optDouble("runTime"))) }
    var newLp by remember { mutableStateOf("") }
    var bin by remember { mutableStateOf("") }
    com.dynops.bcwms.ui.SheetScaffold(onDismiss = onDismiss, contentPadding = androidx.compose.foundation.layout.PaddingValues(20.dp)) {
        Text("Çıktı Bildir — ${firstValue(line, "operationNo")}", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(outQty, { outQty = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Çıktı Miktarı") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(scrapQty, { scrapQty = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Fire") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(runtime, { runtime = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Çalışma Süresi (dk)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(newLp, { newLp = it }, label = { Text("Yeni LP Şablonu (opsiyonel → output LP)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(bin, { bin = it }, label = { Text("Çıktı Bin'i (opsiyonel)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Button(modifier = Modifier.fillMaxWidth(), enabled = (outQty.toDoubleOrNull() ?: 0.0) > 0, onClick = {
            onConfirm(outQty.toDoubleOrNull() ?: 0.0, scrapQty.toDoubleOrNull() ?: 0.0, runtime.toDoubleOrNull() ?: 0.0, newLp.trim(), bin.trim())
        }) { Text("Çıktıyı Bildir") }
        Spacer(Modifier.height(24.dp))
    }
}

/**
 * Assembly — WI §10.9 parity.
 * Lookup (released orders) -> Assembly Document (components) -> Post.
 * BC: assemblies / assemblyLines (warehouse/v2.0, composite key documentType+no), bound action post().
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssemblyModule() {
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
            val r = BcApi.get(context, "assemblies?\$top=100&\$orderby=no desc&\$select=no,documentType,status,itemNo,description,quantity,remainingQuantity,locationCode,binCode,dueDate$filter")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Montaj listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "BOŞ: Released montaj emri yok (HTTP ${r.httpCode})"
                else "TAMAM: ${rows.size} emir (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(Unit) { load() }

    val sel = selected
    if (sel != null) { AssemblyDocument(no = sel, onBack = { selected = null; load() }); return }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        Spacer(Modifier.height(8.dp))
        com.dynops.bcwms.ui.DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() }, label = "Montaj no ile ara")
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { d ->
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text("${d.optString("no")} — ${d.optString("itemNo")}", fontWeight = FontWeight.Bold)
                        Text("${d.optString("description")} · Adet: ${d.optDouble("quantity")}", fontSize = 12.sp, color = Color.Gray)
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Serbest bırakılmış montaj emri yok.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AssemblyDocument(no: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var columns by remember { mutableStateOf(ColumnPrefs.get(context, "assembly", GridColumns.assembly)) }
    var showColumns by remember { mutableStateOf(false) }
    var scanFilter by remember { mutableStateOf("") }
    val key = "documentType='${BcEnum.AssemblyDocType.ORDER}',no='$no'"

    fun reload() {
        scope.launch {
            busy = true
            val h = BcApi.get(context, "assemblies($key)")
            if (h.ok) header = JSONObject(h.body)
            val l = BcApi.get(context, "assemblyLines?\$filter=documentNo eq '$no'&\$top=100")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    // Barkod-öncelikli akış: bileşeni okutunca listeyi o bileşene filtrele — 20
    // satırlı bir montaj emrinde manuel arama yapmaya gerek kalmasın.
    DocumentScanHandler(
        enabled = true,
        lines = lines,
        onSingleMatch = { line, _ -> scanFilter = line.optString("itemNo") },
        onMultiMatch = { itemNo, _ -> scanFilter = itemNo },
        onNoMatch = { r -> status = "⚠️ '${r.itemNo ?: r.value}' bu belgede yok" },
    )
    val displayLines = if (scanFilter.isBlank()) lines else lines.filter { matchLinesByBarcode(listOf(it), com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve(scanFilter)).isNotEmpty() }

    val h = header
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Belge Listesi") }
            DocHeaderCard(
                title = "$no — ${h?.optString("itemNo") ?: ""}",
                subtitle = "${h?.optString("description") ?: ""} · Adet: ${h?.optDouble("quantity") ?: 0.0} · ${firstValue(h ?: JSONObject(), "status")}",
            )
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Bileşenler (${displayLines.size}/${lines.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { showColumns = true }) { Text("⚙ Kolonlar", fontSize = 12.sp) }
            }
            if (scanFilter.isNotBlank()) { ScanFilterChip(scanFilter) { scanFilter = "" }; Spacer(Modifier.height(4.dp)) }
            LineGrid(
                defs = GridColumns.assembly,
                columns = columns,
                rows = displayLines,
                modifier = Modifier.weight(1f),
                isDone = { it.optDouble("consumedQuantity") >= it.optDouble("quantity") && it.optDouble("quantity") > 0.0 },
                onRowClick = { },
            )
        }
        if (showColumns) {
            ChooseColumnsSheet(GridColumns.assembly, columns, onDismiss = { showColumns = false }) { c ->
                columns = c; ColumnPrefs.save(context, "assembly", c); showColumns = false
            }
        }
        BottomActionBar {
            Button(
                onClick = {
                    scope.launch {
                        busy = true; status = "Kaydediliyor..."
                        val r = BcApi.post(context, "assemblies($key)/Microsoft.NAV.post", "{}")
                        busy = false
                        status = if (r.ok) "TAMAM: Montaj kaydedildi (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                        if (r.ok) reload()
                    }
                },
                enabled = !busy && com.dynops.bcwms.lib.ActionGuards.hasQuantity(lines, field = "qtyToAssemble"),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    if (com.dynops.bcwms.lib.ActionGuards.hasQuantity(lines, field = "qtyToAssemble")) "✅ Montajı Kaydet" else "Önce satırlara miktar girin",
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }
}

private fun fmt(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()
