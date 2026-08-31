package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
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
import com.dynops.bcwms.ui.StatusText
import com.dynops.bcwms.ui.WmsRefreshLabel
import com.dynops.bcwms.ui.normalizeQtyInput
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Mevcut serbest üretim emrindeki subcontractor iş merkezi operasyonlarını listeler.
 * Onay, BC'de doğrudan transfer emri + kayıtlı transfer sevki oluşturur; uygulama
 * kendi başına stok miktarı değiştirmez.
 */
@Composable
fun SubcontractingModule() {
    var tab by remember { mutableStateOf(0) }
    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab) {
            Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Fasona Sevk") })
            Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Fason Teslim Alma") })
        }
        when (tab) {
            0 -> SubcontractDispatchModule()
            else -> SubcontractReceiptModule()
        }
    }
}

@Composable
private fun SubcontractDispatchModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var selectedOperation by remember { mutableStateOf<JSONObject?>(null) }
    var selectedOrderRows by remember { mutableStateOf<List<JSONObject>?>(null) }
    var search by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun loadOrders(openBarcode: String? = null) {
        scope.launch {
            loading = true
            status = "Fason üretim emirleri yükleniyor..."
            val result = BcApi.getAllPages(
                context,
                "subcontractOrders?\$top=500&\$orderby=startingDate desc&" +
                    "\$select=status,prodOrderNo,routingReferenceNo,routingNo,operationNo,routingLinkCode," +
                    "workCenterNo,description,subcontractorNo,subcontractorName,targetLocationCode," +
                    "targetLocationName,componentCount,remainingDispatchQuantity,startingDate,endingDate",
            )
            loading = false
            rows = if (result.complete) result.rows else emptyList()
            if (!result.complete) {
                status = "HATA: Fason emir listesinin tamamı alınamadı. Yenileyin."
                return@launch
            }
            status = if (rows.isEmpty())
                "BOŞ: Fason iş merkezi atanmış serbest üretim emri yok."
            else
                "TAMAM: ${rows.map { it.optString("prodOrderNo") }.distinct().size} fason üretim emri"
            openBarcode?.trim()?.takeIf { it.isNotBlank() }?.let { raw ->
                val value = BarcodeIntentResolver.resolve(raw).value.trim()
                val matches = rows.filter {
                    it.optString("prodOrderNo").equals(value, true) ||
                        it.optString("prodOrderNo").equals(raw.trim(), true)
                }
                when (matches.size) {
                    1 -> selectedOperation = matches.first()
                    0 -> status = "HATA: '$value' barkoduna ait açık fason emri bulunamadı."
                    else -> {
                        selectedOrderRows = matches
                        status = "BİLGİ: Emrin ${matches.size} fason operasyonu var; operasyon satırını seçin."
                    }
                }
            }
        }
    }

    LaunchedEffect(Unit) { loadOrders() }

    selectedOperation?.let { operation ->
        SubcontractOperationDetail(
            operation = operation,
            onBack = { selectedOperation = null; loadOrders() },
        )
        return
    }

    selectedOrderRows?.let { orderRows ->
        SubcontractDispatchOrderDetail(
            operations = orderRows,
            onBack = { selectedOrderRows = null; loadOrders() },
            onOperationClick = { selectedOperation = it },
        )
        return
    }

    val query = search.trim()
    val displayed = rows.filter { row ->
        query.isBlank() || listOf(
            row.optString("prodOrderNo"), row.optString("operationNo"),
            row.optString("subcontractorNo"), row.optString("subcontractorName"),
            row.optString("workCenterNo"),
        ).any { it.contains(query, ignoreCase = true) }
    }
    val orderGroups = subcontractDispatchGroups(displayed)

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        ScanField(
            label = "Fason emri / barkod",
            value = search,
            onValueChange = { search = it },
            modifier = Modifier.fillMaxWidth(),
            enabled = !loading,
            onScanned = { loadOrders(it) },
        )
        Spacer(Modifier.height(8.dp))
        Row {
            Button(onClick = { loadOrders() }, enabled = !loading) { WmsRefreshLabel(loading) }
            Spacer(Modifier.width(8.dp))
            if (search.isNotBlank()) OutlinedButton(onClick = { search = "" }) { Text("Temizle") }
        }
        StatusText(status)
        Spacer(Modifier.height(6.dp))
        SubcontractListSummary(
            title = "Fason üretim emirleri",
            documentCount = orderGroups.size,
            lineCount = displayed.size,
            lineLabel = "operasyon",
        )
        Spacer(Modifier.height(6.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(orderGroups, key = { subcontractDispatchDocumentKey(it.first()) }) { orderRows ->
                val row = orderRows.first()
                val targetNames = orderRows.map { it.optString("targetLocationCode") }.filter(String::isNotBlank).distinct()
                val vendorNames = orderRows.map { it.optString("subcontractorName") }.filter(String::isNotBlank).distinct()
                Card(
                    onClick = { selectedOrderRows = orderRows },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Column(Modifier.padding(14.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(row.optString("prodOrderNo"), fontWeight = FontWeight.Bold, fontSize = 17.sp)
                            SubcontractStatusPill(if (row.optString("status").equals("Released", true)) "Serbest" else row.optString("status"))
                        }
                        Text(vendorNames.joinToString().ifBlank { row.optString("subcontractorNo") })
                        Text(
                            "Hedef ${targetNames.joinToString().ifBlank { "-" }} · ${orderRows.map { it.optString("workCenterNo") }.distinct().joinToString()}",
                            fontSize = 12.sp,
                            color = Color.Gray,
                        )
                        Spacer(Modifier.height(8.dp))
                        SubcontractMetricsRow(
                            listOf(
                                "Operasyon" to orderRows.size.toString(),
                                "Malzeme" to orderRows.sumOf { it.optInt("componentCount") }.toString(),
                                "Gönderilecek" to fmtSub(orderRows.sumOf { it.optDouble("remainingDispatchQuantity") }),
                            ),
                        )
                        if (orderRows.size > 1) Text("Operasyon satırlarını görüntüle ›", color = MaterialTheme.colorScheme.primary, fontSize = 12.sp)
                    }
                }
            }
            if (orderGroups.isEmpty() && !loading) item { EmptyState("Aramaya uyan fason emri yok.") }
        }
    }
}

@Composable
private fun SubcontractDispatchOrderDetail(
    operations: List<JSONObject>,
    onBack: () -> Unit,
    onOperationClick: (JSONObject) -> Unit,
) {
    androidx.activity.compose.BackHandler { onBack() }
    val first = operations.first()
    Column(Modifier.fillMaxSize().padding(12.dp)) {
        TextButton(onClick = onBack) { Text("‹ Fason Üretim Emirleri") }
        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
            Column(Modifier.padding(14.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(first.optString("prodOrderNo"), fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    SubcontractStatusPill(if (first.optString("status").equals("Released", true)) "Serbest" else first.optString("status"))
                }
                Text("Fason operasyonları", color = Color.Gray, fontSize = 12.sp)
                Spacer(Modifier.height(10.dp))
                SubcontractMetricsRow(
                    listOf(
                        "Operasyon" to operations.size.toString(),
                        "Malzeme" to operations.sumOf { it.optInt("componentCount") }.toString(),
                        "Gönderilecek" to fmtSub(operations.sumOf { it.optDouble("remainingDispatchQuantity") }),
                    ),
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        Text("Operasyon satırları (${operations.size})", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Spacer(Modifier.height(6.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(operations, key = { operationKey(it) }) { operation ->
                Card(
                    onClick = { onOperationClick(operation) },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Column(Modifier.padding(14.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("Operasyon ${operation.optString("operationNo")}", fontWeight = FontWeight.Bold)
                            Text("Detay ›", color = MaterialTheme.colorScheme.primary, fontSize = 12.sp)
                        }
                        Text(operation.optString("description").ifBlank { "Fason operasyonu" })
                        Text(
                            "İş merkezi ${operation.optString("workCenterNo")} · Rota bağı ${operation.optString("routingLinkCode").ifBlank { "-" }}",
                            fontSize = 12.sp,
                            color = Color.Gray,
                        )
                        Text(
                            "Firma ${operation.optString("subcontractorNo")} · ${operation.optString("subcontractorName")}",
                            fontSize = 12.sp,
                        )
                        Text(
                            "Hedef ${operation.optString("targetLocationCode")} · ${operation.optString("targetLocationName")}",
                            fontSize = 12.sp,
                        )
                        Spacer(Modifier.height(8.dp))
                        SubcontractMetricsRow(
                            listOf(
                                "Malzeme" to operation.optInt("componentCount").toString(),
                                "Kalan sevk" to fmtSub(operation.optDouble("remainingDispatchQuantity")),
                            ),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SubcontractListSummary(title: String, documentCount: Int, lineCount: Int, lineLabel: String) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
        shape = RoundedCornerShape(10.dp),
    ) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 9.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(title, fontWeight = FontWeight.Medium, fontSize = 13.sp)
            Text("$documentCount belge · $lineCount $lineLabel", color = Color.Gray, fontSize = 12.sp)
        }
    }
}

@Composable
private fun SubcontractStatusPill(text: String) {
    Surface(
        color = MaterialTheme.colorScheme.primaryContainer,
        shape = RoundedCornerShape(50),
    ) {
        Text(
            text.ifBlank { "Açık" },
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
            color = MaterialTheme.colorScheme.onPrimaryContainer,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun SubcontractMetricsRow(metrics: List<Pair<String, String>>) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        metrics.forEach { (label, value) ->
            Surface(
                modifier = Modifier.weight(1f),
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f),
                shape = RoundedCornerShape(8.dp),
            ) {
                Column(Modifier.padding(horizontal = 8.dp, vertical = 7.dp)) {
                    Text(value.ifBlank { "-" }, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    Text(label, color = Color.Gray, fontSize = 10.sp)
                }
            }
        }
    }
}

@Composable
private fun SubcontractReceiptModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var selectedLine by remember { mutableStateOf<JSONObject?>(null) }
    var selectedDocumentRows by remember { mutableStateOf<List<JSONObject>?>(null) }
    var search by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun load(openBarcode: String? = null) {
        scope.launch {
            loading = true
            status = "Açık fason dönüş siparişleri yükleniyor..."
            val result = BcApi.getAllPages(
                context,
                "subcontractReceipts?\$top=500&\$orderby=purchaseOrderNo,purchaseLineNo&" +
                    "\$select=documentType,purchaseOrderNo,purchaseLineNo,prodOrderNo,prodOrderLineNo," +
                    "routingReferenceNo,routingNo,operationNo,workCenterNo,finished,itemNo,description," +
                    "quantity,outstandingQuantity,quantityReceived,unitOfMeasureCode,locationCode,binCode," +
                    "vendorNo,vendorName,vendorOrderNo,externalDocumentNo,vendorShipmentNo," +
                    "outboundReferenceNo,outboundTransferShipmentNo,eDespatchStatus,eDespatchDocumentNo,canFinishOperation",
            )
            loading = false
            rows = if (result.complete) result.rows else emptyList()
            if (!result.complete) {
                val error = result.error
                val detail = error?.let { BcApi.errorMessage(it.body) }.orEmpty()
                val http = error?.httpCode?.takeIf { it > 0 }?.let { " (HTTP $it)" }.orEmpty()
                status = "HATA: Fason dönüş listesi alınamadı$http" +
                    detail.takeIf(String::isNotBlank)?.let { ": $it" }.orEmpty()
                return@launch
            }
            status = if (rows.isEmpty())
                "BOŞ: Teslim alınacak açık fason sipariş satırı yok."
            else
                "TAMAM: ${rows.size} açık fason teslim satırı"
            openBarcode?.trim()?.takeIf(String::isNotBlank)?.let { raw ->
                val resolved = BarcodeIntentResolver.resolve(raw).value.trim()
                val matches = rows.filter { subcontractReceiptMatchesReference(it, resolved) || subcontractReceiptMatchesReference(it, raw.trim()) }
                when (matches.size) {
                    1 -> selectedLine = matches.first()
                    0 -> status = "HATA: '$resolved' referansına ait açık fason teslim bulunamadı."
                    else -> {
                        selectedDocumentRows = matches
                        status = "BİLGİ: Referansta ${matches.size} ürün satırı var; teslim alınacak satırı seçin."
                    }
                }
            }
        }
    }

    LaunchedEffect(Unit) { load() }
    selectedLine?.let { line ->
        SubcontractReceiptDetail(line = line, onBack = { selectedLine = null; load() })
        return
    }
    selectedDocumentRows?.let { documentRows ->
        SubcontractReceiptDocumentDetail(
            lines = documentRows,
            onBack = { selectedDocumentRows = null; load() },
            onLineClick = { selectedLine = it },
        )
        return
    }

    val query = search.trim()
    val displayed = rows.filter { query.isBlank() || subcontractReceiptMatchesReference(it, query) }
    val documentGroups = subcontractReceiptGroups(displayed)
    Column(Modifier.fillMaxSize().padding(12.dp)) {
        ScanField(
            label = "İrsaliye / fason ref. / sipariş barkodu",
            value = search,
            onValueChange = { search = it },
            onScanned = { load(it) },
            enabled = !loading,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(8.dp))
        Row {
            Button(onClick = { load() }, enabled = !loading) { WmsRefreshLabel(loading) }
            Spacer(Modifier.width(8.dp))
            if (search.isNotBlank()) OutlinedButton(onClick = { search = "" }) { Text("Temizle") }
        }
        StatusText(status)
        SubcontractListSummary(
            title = "Açık fason dönüş belgeleri",
            documentCount = documentGroups.size,
            lineCount = displayed.size,
            lineLabel = "ürün satırı",
        )
        Spacer(Modifier.height(6.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(documentGroups, key = { subcontractReceiptDocumentKey(it.first()) }) { documentRows ->
                val row = documentRows.first()
                val reference = subcontractReceiptDocumentKey(row)
                val units = documentRows.map { it.optString("unitOfMeasureCode") }.filter(String::isNotBlank).distinct()
                val openQty = fmtSub(documentRows.sumOf { it.optDouble("outstandingQuantity") }) +
                    units.singleOrNull()?.let { " $it" }.orEmpty()
                Card(
                    onClick = { selectedDocumentRows = documentRows },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Column(Modifier.padding(14.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(reference, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                            SubcontractStatusPill(row.optString("eDespatchStatus").ifBlank { "Açık" })
                        }
                        Text("PO ${row.optString("purchaseOrderNo")} · ÜE ${documentRows.map { it.optString("prodOrderNo") }.distinct().joinToString()}", fontSize = 12.sp)
                        Text("${row.optString("vendorNo")} · ${row.optString("vendorName")}")
                        Text(
                            "Teslim yeri ${row.optString("locationCode")}/${row.optString("binCode").ifBlank { "-" }}",
                            fontSize = 12.sp,
                            color = Color.Gray,
                        )
                        Spacer(Modifier.height(8.dp))
                        SubcontractMetricsRow(
                            listOf(
                                "Satır" to documentRows.size.toString(),
                                "Operasyon" to documentRows.map { it.optString("operationNo") }.distinct().size.toString(),
                                "Açık miktar" to openQty,
                            ),
                        )
                        if (documentRows.size > 1) Text("Ürün satırlarını görüntüle ›", color = MaterialTheme.colorScheme.primary, fontSize = 12.sp)
                    }
                }
            }
            if (documentGroups.isEmpty() && !loading) item { EmptyState("Aramaya uyan açık fason teslim yok.") }
        }
    }
}

@Composable
private fun SubcontractReceiptDocumentDetail(
    lines: List<JSONObject>,
    onBack: () -> Unit,
    onLineClick: (JSONObject) -> Unit,
) {
    androidx.activity.compose.BackHandler { onBack() }
    val first = lines.first()
    val reference = subcontractReceiptDocumentKey(first)
    val units = lines.map { it.optString("unitOfMeasureCode") }.filter(String::isNotBlank).distinct()
    Column(Modifier.fillMaxSize().padding(12.dp)) {
        TextButton(onClick = onBack) { Text("‹ Fason Teslim Belgeleri") }
        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
            Column(Modifier.padding(14.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(reference, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    SubcontractStatusPill(first.optString("eDespatchStatus").ifBlank { "Açık" })
                }
                Text("Satın alma ${first.optString("purchaseOrderNo")}")
                Text("Firma ${first.optString("vendorNo")} · ${first.optString("vendorName")}", fontSize = 12.sp)
                Text(
                    "Giden transfer ${first.optString("outboundTransferShipmentNo").ifBlank { "-" }} · " +
                        "e-İrsaliye ${first.optString("eDespatchDocumentNo").ifBlank { "-" }}",
                    fontSize = 11.sp,
                    color = Color.Gray,
                )
                Spacer(Modifier.height(10.dp))
                SubcontractMetricsRow(
                    listOf(
                        "Ürün satırı" to lines.size.toString(),
                        "Üretim emri" to lines.map { it.optString("prodOrderNo") }.distinct().size.toString(),
                        "Açık miktar" to (fmtSub(lines.sumOf { it.optDouble("outstandingQuantity") }) + units.singleOrNull()?.let { " $it" }.orEmpty()),
                    ),
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        Text("Teslim alınacak satırlar (${lines.size})", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Spacer(Modifier.height(6.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(lines, key = { subcontractReceiptKey(it) }) { line ->
                Card(
                    onClick = { onLineClick(line) },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Column(Modifier.padding(14.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(line.optString("itemNo"), fontWeight = FontWeight.Bold)
                            Text("Satır ${line.optInt("purchaseLineNo")}", color = Color.Gray, fontSize = 11.sp)
                        }
                        Text(line.optString("description"), fontSize = 12.sp)
                        Text(
                            "ÜE ${line.optString("prodOrderNo")} · Operasyon ${line.optString("operationNo")} · ${line.optString("workCenterNo")}",
                            fontSize = 11.sp,
                            color = Color.Gray,
                        )
                        Spacer(Modifier.height(8.dp))
                        SubcontractMetricsRow(
                            listOf(
                                "Sipariş" to fmtSub(line.optDouble("quantity")),
                                "Alınan" to fmtSub(line.optDouble("quantityReceived")),
                                "Açık" to (fmtSub(line.optDouble("outstandingQuantity")) + " " + line.optString("unitOfMeasureCode")),
                            ),
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            "Teslim yeri ${line.optString("locationCode")}/${line.optString("binCode").ifBlank { "-" }} · Teslim al ›",
                            color = MaterialTheme.colorScheme.primary,
                            fontSize = 12.sp,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SubcontractReceiptDetail(line: JSONObject, onBack: () -> Unit) {
    androidx.activity.compose.BackHandler { onBack() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val maxQty = line.optDouble("outstandingQuantity")
    var quantity by remember(subcontractReceiptKey(line)) { mutableStateOf(fmtSub(maxQty)) }
    var vendorShipmentNo by remember(subcontractReceiptKey(line)) { mutableStateOf("") }
    var inboundReferenceNo by remember(subcontractReceiptKey(line)) {
        mutableStateOf(line.optString("outboundReferenceNo").ifBlank { line.optString("purchaseOrderNo") })
    }
    var binCode by remember(subcontractReceiptKey(line)) { mutableStateOf(line.optString("binCode")) }
    var vehiclePlateNo by remember(subcontractReceiptKey(line)) { mutableStateOf("") }
    var driverCode by remember(subcontractReceiptKey(line)) { mutableStateOf("") }
    var finishOperation by remember(subcontractReceiptKey(line)) { mutableStateOf(true) }
    var showConfirm by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    val idempotencyKey = remember(subcontractReceiptKey(line)) { UUID.randomUUID().toString() }
    val enteredQty = quantity.replace(',', '.').toDoubleOrNull() ?: 0.0
    val fullReceipt = canFinishSubcontractOperation(enteredQty, maxQty)
    val valid = enteredQty > 0.0 && enteredQty <= maxQty && vendorShipmentNo.trim().isNotBlank()

    fun receive() {
        showConfirm = false
        scope.launch {
            busy = true
            status = "Fason ürün standart BC kabulüyle stoka alınıyor..."
            val body = JSONObject().apply {
                put("quantity", enteredQty)
                put("vendorShipmentNo", vendorShipmentNo.trim())
                put("inboundReferenceNo", inboundReferenceNo.trim())
                put("binCode", binCode.trim())
                put("finishOperation", finishOperation && fullReceipt)
                put("vehiclePlateNo", vehiclePlateNo.trim())
                put("driverCode", driverCode.trim())
                put("idempotencyKey", idempotencyKey)
            }.toString()
            val response = BcApi.post(
                context,
                "subcontractReceipts(${subcontractReceiptODataKey(line)})/Microsoft.NAV.receive",
                body,
            )
            busy = false
            if (!response.ok) {
                status = "HATA: ${BcApi.errorMessage(response.body)} (HTTP ${response.httpCode})"
                return@launch
            }
            val result = runCatching { JSONObject(BcApi.scalarValue(response.body)) }.getOrNull()
            status = "TAMAM: ${result?.optString("postedPurchaseReceiptNo").orEmpty().ifBlank { "kayıtlı satın alma irsaliyesi" }} · " +
                if (result?.optBoolean("operationFinished") == true) "fason operasyonu kapandı; fatura bağlantısı korundu."
                else "parsiyel kabul işlendi; kalan miktar açık."
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp)) {
        TextButton(onClick = onBack, enabled = !busy) { Text("‹ Fason Teslim Listesi") }
        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
            Column(Modifier.padding(14.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(line.optString("outboundReferenceNo").ifBlank { line.optString("purchaseOrderNo") }, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    SubcontractStatusPill(if (line.optBoolean("finished")) "Tamamlandı" else "Açık")
                }
                Text("${line.optString("itemNo")} · ${line.optString("description")}", fontWeight = FontWeight.Medium)
                Text("Üretim emri ${line.optString("prodOrderNo")} · Operasyon ${line.optString("operationNo")} · ${line.optString("workCenterNo")}", fontSize = 12.sp)
                Text("Satın alma ${line.optString("purchaseOrderNo")} / satır ${line.optInt("purchaseLineNo")}", fontSize = 12.sp)
                Text("Firma ${line.optString("vendorNo")} · ${line.optString("vendorName")}", fontSize = 12.sp)
                Text("Teslim yeri ${line.optString("locationCode")}/${line.optString("binCode").ifBlank { "-" }}", fontSize = 12.sp, color = Color.Gray)
                Spacer(Modifier.height(10.dp))
                SubcontractMetricsRow(
                    listOf(
                        "Sipariş" to fmtSub(line.optDouble("quantity")),
                        "Önce alınan" to fmtSub(line.optDouble("quantityReceived")),
                        "Açık" to (fmtSub(maxQty) + " " + line.optString("unitOfMeasureCode")),
                    ),
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Text("Teslim belgesi", fontWeight = FontWeight.Bold, fontSize = 15.sp)
        ScanField(
            label = "Gelen irsaliye no. (zorunlu)", value = vendorShipmentNo,
            onValueChange = { vendorShipmentNo = it }, enabled = !busy, modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = inboundReferenceNo, onValueChange = { inboundReferenceNo = it },
            label = { Text("Gelen belge fason referansı") }, singleLine = true,
            enabled = !busy, modifier = Modifier.fillMaxWidth(),
        )
        Row(Modifier.fillMaxWidth()) {
            OutlinedTextField(
                value = quantity,
                onValueChange = {
                    quantity = normalizeQtyInput(it)
                    val parsed = normalizeQtyInput(it).toDoubleOrNull() ?: 0.0
                    if (!canFinishSubcontractOperation(parsed, maxQty)) finishOperation = false
                },
                label = { Text("Kabul miktarı (en çok ${fmtSub(maxQty)})") }, singleLine = true,
                enabled = !busy, modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(6.dp))
            OutlinedTextField(
                value = binCode, onValueChange = { binCode = it }, label = { Text("Hedef bin") },
                singleLine = true, enabled = !busy, modifier = Modifier.weight(1f),
            )
        }
        Spacer(Modifier.height(6.dp))
        Text("Araç ve sürücü", fontWeight = FontWeight.Bold, fontSize = 15.sp)
        Text("BADE ambar kabul lokasyonlarında aşağıdaki plaka ve sürücü zorunludur.", fontSize = 11.sp, color = Color.Gray)
        Row(Modifier.fillMaxWidth()) {
            OutlinedTextField(
                value = vehiclePlateNo, onValueChange = { vehiclePlateNo = it.uppercase() }, label = { Text("Araç plakası") },
                singleLine = true, enabled = !busy, modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(6.dp))
            ScanField(
                label = "Sürücü kodu", value = driverCode, onValueChange = { driverCode = it },
                enabled = !busy, modifier = Modifier.weight(1f),
            )
        }
        Row(Modifier.fillMaxWidth()) {
            Checkbox(
                checked = finishOperation,
                onCheckedChange = { finishOperation = it },
                enabled = fullReceipt && !busy,
            )
            Column {
                Text("Fason operasyonunu kapat", fontWeight = FontWeight.Medium)
                Text(
                    if (fullReceipt) "Tam kabulde standart BC Finished kaydı işlenir."
                    else "Parsiyel kabulde operasyon açık kalır.",
                    fontSize = 11.sp, color = Color.Gray,
                )
            }
        }
        StatusText(status)
        Button(
            onClick = { showConfirm = true }, enabled = valid && !busy,
            modifier = Modifier.fillMaxWidth(),
        ) { Text(if (fullReceipt && finishOperation) "Tam Kabul Et ve Operasyonu Kapat" else "Parsiyel Kabul Et") }
        Text(
            "Onay; standart fason satın alma kabulünü post eder, mamul/yarı mamul çıktısını stoka alır. Hizmet faturası eşleştirmesi için PO–üretim emri bağlantısı korunur.",
            fontSize = 11.sp, color = Color.Gray, modifier = Modifier.padding(vertical = 8.dp),
        )
    }

    if (showConfirm) AlertDialog(
        onDismissRequest = { showConfirm = false },
        title = { Text("Fason teslimi onayla") },
        text = {
            Text(
                "${line.optString("itemNo")} ürününden ${fmtSub(enteredQty)} ${line.optString("unitOfMeasureCode")} " +
                    "${line.optString("prodOrderNo")} / ${line.optString("operationNo")} referansıyla stoka alınacak."
            )
        },
        confirmButton = { Button(onClick = { receive() }) { Text("Stoka Al") } },
        dismissButton = { TextButton(onClick = { showConfirm = false }) { Text("Vazgeç") } },
    )
}

@Composable
private fun SubcontractOperationDetail(operation: JSONObject, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var components by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var showConfirm by remember { mutableStateOf(false) }
    val selected = remember { mutableStateMapOf<String, Boolean>() }
    val quantities = remember { mutableStateMapOf<String, String>() }
    val lpNos = remember { mutableStateMapOf<String, String>() }
    val lotNos = remember { mutableStateMapOf<String, String>() }
    val serialNos = remember { mutableStateMapOf<String, String>() }
    val bins = remember { mutableStateMapOf<String, String>() }

    fun loadComponents() {
        scope.launch {
            loading = true
            status = "Fasona gönderilecek malzemeler yükleniyor..."
            val no = operation.optString("prodOrderNo")
            val safeNo = no.replace("'", "''")
            val result = BcApi.getAllPages(
                context,
                "subcontractComponents?\$top=500&\$filter=prodOrderNo eq '$safeNo'&" +
                    "\$orderby=prodOrderLineNo,componentLineNo&" +
                    "\$select=status,prodOrderNo,prodOrderLineNo,componentLineNo,routingLinkCode,itemNo," +
                    "description,requiredQuantity,consumptionRemainingQuantity,dispatchedQuantity," +
                    "remainingDispatchQuantity,unitOfMeasureCode,locationCode,binCode",
            )
            loading = false
            val routeLink = operation.optString("routingLinkCode")
            components = if (result.complete) result.rows.filter {
                it.optString("routingLinkCode") == routeLink && it.optDouble("remainingDispatchQuantity") > 0.0
            } else emptyList()
            selected.clear(); quantities.clear(); bins.clear(); lpNos.clear(); lotNos.clear(); serialNos.clear()
            components.forEach { line ->
                val key = componentKey(line)
                selected[key] = true
                quantities[key] = fmtSub(line.optDouble("remainingDispatchQuantity"))
                bins[key] = line.optString("binCode")
            }
            status = when {
                !result.complete -> "HATA: Malzeme listesinin tamamı alınamadı; sevk kapatıldı."
                components.isEmpty() -> "TAMAM: Bu operasyonda fasona gönderilecek kalan malzeme yok."
                else -> "TAMAM: ${components.size} malzeme sevke hazır."
            }
        }
    }

    LaunchedEffect(operationKey(operation)) { loadComponents() }

    val chosen = components.filter { selected[componentKey(it)] == true }
    fun dispatch() {
        showConfirm = false
        scope.launch {
            loading = true
            val groups = chosen.groupBy { it.optString("locationCode") }
            val posted = mutableListOf<String>()
            for ((sourceLocation, lines) in groups) {
                status = "$sourceLocation stokları fasona aktarılıyor..."
                val payloadLines = JSONArray()
                for (line in lines) {
                    val key = componentKey(line)
                    val requestedQty = quantities[key]?.replace(',', '.')?.toDoubleOrNull() ?: 0.0
                    val enteredLps = lpNos[key].orEmpty().split(Regex("[,;\\s]+"))
                        .map(String::trim).filter(String::isNotBlank).distinct()
                    fun addAllocation(qty: Double, lpNo: String, lotNo: String, serialNo: String, fromBin: String) {
                        payloadLines.put(JSONObject().apply {
                            put("prodOrderLineNo", line.optInt("prodOrderLineNo"))
                            put("componentLineNo", line.optInt("componentLineNo"))
                            put("quantity", qty)
                            put("lpNo", lpNo)
                            put("lotNo", lotNo)
                            put("serialNo", serialNo)
                            put("fromBinCode", fromBin)
                        })
                    }
                    if (enteredLps.isEmpty()) {
                        addAllocation(
                            requestedQty, "", lotNos[key].orEmpty().trim(), serialNos[key].orEmpty().trim(),
                            bins[key].orEmpty().trim(),
                        )
                    } else {
                        var remaining = requestedQty
                        for (lpNo in enteredLps) {
                            if (remaining <= 0.0) break
                            val safeLp = lpNo.replace("'", "''")
                            val safeItem = line.optString("itemNo").replace("'", "''")
                            val lpResult = BcApi.getAllPages(
                                context,
                                "licensePlateLines?\$top=200&\$filter=lpNo eq '$safeLp' and itemNo eq '$safeItem'&" +
                                    "\$select=lpNo,itemNo,quantity,lotNo,serialNo,sourceBinCode",
                            )
                            if (!lpResult.complete) {
                                loading = false
                                status = "HATA: $lpNo LP içeriği doğrulanamadı; stok post edilmedi."
                                return@launch
                            }
                            val wantedLot = lotNos[key].orEmpty().trim()
                            val wantedSerial = serialNos[key].orEmpty().trim()
                            val lpLines = lpResult.rows.filter {
                                (wantedLot.isBlank() || it.optString("lotNo") == wantedLot) &&
                                    (wantedSerial.isBlank() || it.optString("serialNo") == wantedSerial)
                            }
                            for (lpLine in lpLines) {
                                if (remaining <= 0.0) break
                                val allocation = minOf(remaining, lpLine.optDouble("quantity"))
                                if (allocation > 0.0) {
                                    addAllocation(
                                        allocation,
                                        lpNo,
                                        lpLine.optString("lotNo"),
                                        lpLine.optString("serialNo"),
                                        lpLine.optString("sourceBinCode").ifBlank { bins[key].orEmpty().trim() },
                                    )
                                    remaining -= allocation
                                }
                            }
                        }
                        if (remaining > 0.000001) {
                            loading = false
                            status = "HATA: ${line.optString("itemNo")} için okutulan LP'lerde ${fmtSub(requestedQty - remaining)} var; istenen ${fmtSub(requestedQty)}. Stok post edilmedi."
                            return@launch
                        }
                    }
                }
                val body = JSONObject().apply {
                    put("linesJson", payloadLines.toString())
                    put("idempotencyKey", UUID.randomUUID().toString())
                }.toString()
                val api = BcApi.post(
                    context,
                    "subcontractOrders(${operationODataKey(operation)})/Microsoft.NAV.dispatch",
                    body,
                )
                if (!api.ok) {
                    loading = false
                    val prefix = if (posted.isEmpty()) "" else "ÖNCE POST EDİLEN: ${posted.joinToString()} · "
                    status = "${prefix}HATA: ${BcApi.errorMessage(api.body)} (HTTP ${api.httpCode})"
                    return@launch
                }
                val value = BcApi.scalarValue(api.body)
                val result = runCatching { JSONObject(value) }.getOrNull()
                val shipment = result?.optString("postedTransferShipmentNo").orEmpty().ifBlank { "kayıtlı irsaliye" }
                val reference = result?.optString("fasonReferenceNo").orEmpty().ifBlank { operation.optString("prodOrderNo") }
                val eDespatch = result?.optString("eDespatchStatus").orEmpty().ifBlank { "durum alınamadı" }
                posted += "$shipment · Ref $reference · E-İrsaliye $eDespatch"
            }
            loading = false
            status = "TAMAM: Ana stoktan düşüldü, fason lokasyonuna aktarıldı ve e-İrsaliye kuyruğu oluşturuldu · ${posted.joinToString()}"
            loadComponents()
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp)) {
        TextButton(onClick = onBack, enabled = !loading) { Text("‹ Fason Emirleri") }
        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
            Column(Modifier.padding(14.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(operation.optString("prodOrderNo"), fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    SubcontractStatusPill("Operasyon ${operation.optString("operationNo")}")
                }
                Text("Operasyon ${operation.optString("operationNo")} · ${operation.optString("description")}")
                Text("Firma: ${operation.optString("subcontractorNo")} · ${operation.optString("subcontractorName")}")
                Text("Hedef: ${operation.optString("targetLocationCode")} · ${operation.optString("targetLocationName")}")
                Text(
                    "İş merkezi ${operation.optString("workCenterNo")} · Rota ${operation.optString("routingNo")} · Bağ ${operation.optString("routingLinkCode").ifBlank { "-" }}",
                    fontSize = 11.sp,
                    color = Color.Gray,
                )
                Spacer(Modifier.height(10.dp))
                SubcontractMetricsRow(
                    listOf(
                        "Malzeme satırı" to components.size.toString(),
                        "Seçili" to chosen.size.toString(),
                        "Kalan sevk" to fmtSub(components.sumOf { it.optDouble("remainingDispatchQuantity") }),
                    ),
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Row {
            OutlinedButton(onClick = { loadComponents() }, enabled = !loading) { WmsRefreshLabel(loading) }
            Spacer(Modifier.width(8.dp))
            TextButton(onClick = { components.forEach { selected[componentKey(it)] = true } }) { Text("Tümünü seç") }
            TextButton(onClick = { selected.clear() }) { Text("Seçimi kaldır") }
        }
        StatusText(status)
        Text("Malzeme satırları (${components.size})", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        components.forEach { line ->
            val key = componentKey(line)
            val maxQty = line.optDouble("remainingDispatchQuantity")
            Card(Modifier.fillMaxWidth().padding(vertical = 5.dp), shape = RoundedCornerShape(12.dp)) {
                Column(Modifier.padding(12.dp)) {
                    Row(Modifier.fillMaxWidth()) {
                        Checkbox(
                            checked = selected[key] == true,
                            onCheckedChange = { selected[key] = it },
                            enabled = !loading,
                        )
                        Column(Modifier.weight(1f)) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(line.optString("itemNo"), fontWeight = FontWeight.Bold)
                                Text("Satır ${line.optInt("componentLineNo")}", color = Color.Gray, fontSize = 10.sp)
                            }
                            Text(line.optString("description"), fontSize = 12.sp)
                            Text(
                                "Kaynak ${line.optString("locationCode")}/${line.optString("binCode")} · " +
                                    "Gerekli ${fmtSub(line.optDouble("requiredQuantity"))} · Gönderildi ${fmtSub(line.optDouble("dispatchedQuantity"))}",
                                fontSize = 11.sp,
                                color = Color.Gray,
                            )
                        }
                    }
                    OutlinedTextField(
                        value = quantities[key].orEmpty(),
                        onValueChange = { quantities[key] = normalizeQtyInput(it) },
                        label = { Text("Sevk miktarı (en çok ${fmtSub(maxQty)})") },
                        singleLine = true,
                        enabled = selected[key] == true && !loading,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Row(Modifier.fillMaxWidth()) {
                        OutlinedTextField(
                            value = bins[key].orEmpty(), onValueChange = { bins[key] = it },
                            label = { Text("Kaynak bin") }, singleLine = true,
                            enabled = selected[key] == true && !loading, modifier = Modifier.weight(1f),
                        )
                        Spacer(Modifier.width(6.dp))
                        ScanField(
                            label = "LP / çoklu LP (virgülle)", value = lpNos[key].orEmpty(), onValueChange = { lpNos[key] = it },
                            onScanned = { lpNos[key] = appendLpBarcode(lpNos[key].orEmpty(), BarcodeIntentResolver.resolve(it).value) },
                            updateValueOnScan = false,
                            enabled = selected[key] == true && !loading, modifier = Modifier.weight(1f),
                        )
                    }
                    Row(Modifier.fillMaxWidth()) {
                        ScanField(
                            label = "Lot (gerekiyorsa)", value = lotNos[key].orEmpty(), onValueChange = { lotNos[key] = it },
                            enabled = selected[key] == true && !loading, modifier = Modifier.weight(1f),
                        )
                        Spacer(Modifier.width(6.dp))
                        ScanField(
                            label = "Seri (gerekiyorsa)", value = serialNos[key].orEmpty(), onValueChange = { serialNos[key] = it },
                            enabled = selected[key] == true && !loading, modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        val invalidQuantity = chosen.any { line ->
            val qty = quantities[componentKey(line)]?.replace(',', '.')?.toDoubleOrNull() ?: 0.0
            qty <= 0.0 || qty > line.optDouble("remainingDispatchQuantity")
        }
        Button(
            onClick = { showConfirm = true },
            enabled = chosen.isNotEmpty() && !invalidQuantity && !loading,
            modifier = Modifier.fillMaxWidth(),
        ) { Text("Fasona Sevk Et (${chosen.size} satır)", fontWeight = FontWeight.Bold) }
        Text(
            "Onay, standart doğrudan transferi post eder: kaynak stok azalır, fason lokasyon stoku aynı işlemde artar ve transfer irsaliyesi oluşur.",
            fontSize = 11.sp,
            color = Color.Gray,
            modifier = Modifier.padding(vertical = 8.dp),
        )
    }

    if (showConfirm) AlertDialog(
        onDismissRequest = { showConfirm = false },
        title = { Text("Fason sevki onayla") },
        text = {
            Text(
                "${operation.optString("prodOrderNo")} için ${chosen.size} malzeme " +
                    "${operation.optString("targetLocationCode")} lokasyonuna aktarılacak. Bu işlem stok kaydı oluşturur."
            )
        },
        confirmButton = { Button(onClick = { dispatch() }) { Text("Stok Aktar ve İrsaliye Oluştur") } },
        dismissButton = { TextButton(onClick = { showConfirm = false }) { Text("Vazgeç") } },
    )
}

internal fun subcontractDispatchDocumentKey(row: JSONObject): String =
    row.optString("prodOrderNo").trim()

internal fun subcontractDispatchGroups(rows: List<JSONObject>): List<List<JSONObject>> =
    rows.groupByTo(linkedMapOf(), ::subcontractDispatchDocumentKey).values.toList()

internal fun subcontractReceiptDocumentKey(row: JSONObject): String =
    row.optString("outboundReferenceNo").trim().ifBlank { row.optString("purchaseOrderNo").trim() }

internal fun subcontractReceiptGroups(rows: List<JSONObject>): List<List<JSONObject>> =
    rows.groupByTo(linkedMapOf(), ::subcontractReceiptDocumentKey).values.toList()

internal fun operationKey(row: JSONObject): String = listOf(
    row.optString("status"), row.optString("prodOrderNo"), row.optInt("routingReferenceNo").toString(),
    row.optString("routingNo"), row.optString("operationNo"),
).joinToString("|")

internal fun operationODataKey(row: JSONObject): String =
    "status='${row.optString("status").ifBlank { "Released" }.replace("'", "''")}'," +
        "prodOrderNo='${row.optString("prodOrderNo").replace("'", "''")}'," +
        "routingReferenceNo=${row.optInt("routingReferenceNo")}," +
        "routingNo='${row.optString("routingNo").replace("'", "''")}'," +
        "operationNo='${row.optString("operationNo").replace("'", "''")}'"

internal fun componentKey(row: JSONObject): String =
    "${row.optInt("prodOrderLineNo")}|${row.optInt("componentLineNo")}"

internal fun appendLpBarcode(existing: String, scanned: String): String {
    val value = scanned.trim()
    if (value.isBlank()) return existing.trim()
    val current = existing.split(Regex("[,;\\s]+"))
        .map(String::trim).filter(String::isNotBlank)
    return (current + value).distinct().joinToString(",")
}

internal fun subcontractReceiptKey(row: JSONObject): String =
    "${row.optString("documentType").ifBlank { "Order" }}|${row.optString("purchaseOrderNo")}|${row.optInt("purchaseLineNo")}"

internal fun subcontractReceiptODataKey(row: JSONObject): String =
    "documentType='${row.optString("documentType").ifBlank { "Order" }.replace("'", "''")}'," +
        "purchaseOrderNo='${row.optString("purchaseOrderNo").replace("'", "''")}'," +
        "purchaseLineNo=${row.optInt("purchaseLineNo")}"

internal fun subcontractReceiptMatchesReference(row: JSONObject, query: String): Boolean {
    val value = query.trim()
    if (value.isBlank()) return true
    return listOf(
        "outboundReferenceNo", "purchaseOrderNo", "prodOrderNo", "vendorOrderNo",
        "externalDocumentNo", "vendorShipmentNo", "outboundTransferShipmentNo",
        "itemNo", "vendorNo", "vendorName",
    ).any { row.optString(it).contains(value, ignoreCase = true) }
}

internal fun canFinishSubcontractOperation(quantity: Double, outstandingQuantity: Double): Boolean =
    quantity > 0.0 && kotlin.math.abs(quantity - outstandingQuantity) <= 0.000001

private fun fmtSub(value: Double): String =
    if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()
