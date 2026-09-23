package com.dynops.bcwms.feature

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.launch
import org.json.JSONObject

/** DKC Sipariş sekmesi yalnız BC'deki Araç bilgilerini okur; sevk işlemi yapmaz. */
@Composable
internal fun DkcSalesOrderVehicle(no: String, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var order by remember(no) { mutableStateOf<JSONObject?>(null) }
    var status by remember(no) { mutableStateOf("") }
    var loading by remember(no) { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true
            val result = BcApi.get(context, "salesSources('${no.replace("'", "''")}')")
            order = if (result.ok) runCatching { JSONObject(result.body) }.getOrNull() else null
            status = if (order == null) "Araç bilgileri alınamadı. Yenileyin." else ""
            loading = false
        }
    }
    LaunchedEffect(no) { load() }
    val values = order?.let { doc ->
        listOf(
            "Araç Plaka No." to rawValue(doc, "vehiclePlateNo"),
            "Dorse Plaka No." to rawValue(doc, "trailerPlateNo"),
            "Yabancı Plaka" to rawValue(doc, "foreignPlate"),
            "Sürücü Kodu" to rawValue(doc, "driverCode"),
            "Sürücü Adı" to rawValue(doc, "driverFirstName"),
            "Sürücü Soyadı" to rawValue(doc, "driverFamilyName"),
            "Sürücü Ünvanı" to rawValue(doc, "driverTitle"),
            "Sürücü Kimlik No." to rawValue(doc, "driverIdentificationNo"),
        )
    }.orEmpty()

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = onBack) { Text("‹ Siparişler") }
            TextButton(onClick = { load() }, enabled = !loading) { WmsRefreshLabel(loading) }
        }
        Text("$no · Araç", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        StatusText(status)
        if (order != null && values.all { it.second.isBlank() })
            Text("Bu siparişte BC araç bilgileri boş.", color = MaterialTheme.colorScheme.error)
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(values) { (label, value) ->
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(8.dp)) {
                    Column(Modifier.padding(10.dp)) {
                        Text(label, style = MaterialTheme.typography.labelMedium)
                        Text(value.ifBlank { "—" }, style = MaterialTheme.typography.bodyLarge)
                    }
                }
            }
        }
    }
}

/** Kayıtlı satış sevk irsaliyelerinin tamamı; e-belge PDF'si belge yazıcısına gider. */
@Composable
internal fun DkcPostedShipmentTab() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var selected by remember { mutableStateOf<String?>(null) }
    var search by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true
            val page = BcApi.getAllPages(
                context,
                "dkcPostedSalesShipments?\$orderby=postingDate desc&\$select=no,orderNo,customerNo,customerName,postingDate,shipmentDate,vehiclePlateNo,eDocumentNo,eDocumentPdfAvailable",
                maxPages = 1000,
            )
            rows = if (page.complete) page.rows else emptyList()
            status = if (!page.complete) "Kayıtlı sevk irsaliyelerinin tamamı alınamadı. Yenileyin."
                else "${rows.size} kayıtlı satış sevk irsaliyesi"
            loading = false
        }
    }
    LaunchedEffect(Unit) { load() }
    val current = selected
    if (current != null) {
        DkcPostedShipmentDetail(no = current, onBack = { selected = null })
        return
    }
    val shown = rows.filter {
        search.isBlank() || listOf("no", "orderNo", "customerName", "vehiclePlateNo")
            .any { key -> rawValue(it, key).contains(search.trim(), ignoreCase = true) }
    }
    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Kayıtlı Sevk İrsaliyeleri", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            TextButton(onClick = { load() }, enabled = !loading) { WmsRefreshLabel(loading) }
        }
        DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { }, label = "İrsaliye / sipariş ara")
        StatusText(status)
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(shown) { doc ->
                Card(onClick = { selected = doc.optString("no") }, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(10.dp)) {
                        Text(doc.optString("no"), fontWeight = FontWeight.Bold)
                        Text("Sipariş: ${firstValue(doc, "orderNo")} · ${firstValue(doc, "postingDate")}")
                        Text("${firstValue(doc, "customerName")} · Plaka: ${firstValue(doc, "vehiclePlateNo")}")
                        if (doc.optBoolean("eDocumentPdfAvailable")) Text("e-belge PDF hazır")
                    }
                }
            }
            if (shown.isEmpty() && !loading) item { Text("Kayıtlı sevk irsaliyesi bulunamadı.") }
        }
    }
}

@Composable
private fun DkcPostedShipmentDetail(no: String, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var document by remember(no) { mutableStateOf<JSONObject?>(null) }
    var status by remember(no) { mutableStateOf("") }
    var busy by remember(no) { mutableStateOf(false) }

    fun load() {
        scope.launch {
            val result = BcApi.get(context, "dkcPostedSalesShipments('${no.replace("'", "''")}')")
            document = if (result.ok) runCatching { JSONObject(result.body) }.getOrNull() else null
            if (document == null) status = "İrsaliye bilgileri alınamadı."
        }
    }
    LaunchedEffect(no) { load() }
    val doc = document
    Column(Modifier.fillMaxSize().padding(12.dp)) {
        TextButton(onClick = onBack) { Text("‹ İrsaliyeler") }
        Text(no, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        StatusText(status)
        if (doc != null) {
            Text("Sipariş: ${firstValue(doc, "orderNo")}")
            Text("Müşteri: ${firstValue(doc, "customerName")}")
            Text("Kayıt tarihi: ${firstValue(doc, "postingDate")}")
            Text("Araç Plaka: ${firstValue(doc, "vehiclePlateNo")}")
            Text("Dorse Plaka: ${firstValue(doc, "trailerPlateNo")}")
            Text("Sürücü: ${firstValue(doc, "driverName")}")
            Text("e-Belge No: ${firstValue(doc, "eDocumentNo")}")
            Spacer(Modifier.height(16.dp))
            Button(
                onClick = {
                    val printer = getDefaultPrinter(context, PRINTER_USAGE_DOCUMENT)
                    scope.launch {
                        busy = true
                        val body = JSONObject().apply { put("printerId", printer) }.toString()
                        val result = BcApi.boundAction(context, "dkcPostedSalesShipments", no, "printEDocument", body)
                        status = if (result.ok) "e-belge PDF belge yazıcısının kuyruğuna alındı."
                            else QcErrorParser.friendlyStatus(BcApi.errorMessage(result.body), result.httpCode)
                        busy = false
                    }
                },
                enabled = !busy && doc.optBoolean("eDocumentPdfAvailable"),
                modifier = Modifier.fillMaxWidth(),
            ) { Text(if (busy) "Gönderiliyor..." else "e-Belge PDF Yazdır") }
            if (!doc.optBoolean("eDocumentPdfAvailable")) Text("Bu irsaliyenin e-belge PDF bağlantısı henüz yok.")
        }
    }
}
