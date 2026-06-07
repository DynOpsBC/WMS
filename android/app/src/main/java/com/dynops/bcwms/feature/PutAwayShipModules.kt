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

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val r = BcApi.get(context, "putAways?\$top=30&\$select=no,locationCode,assignedUserId,status")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Yerleştirme listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "EMPTY: Açık yerleştirme belgesi yok (HTTP ${r.httpCode})"
                else "PASS: ${rows.size} belge (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(Unit) { load() }

    val sel = selected
    if (sel != null) { PutAwayDocument(no = sel, onBack = { selected = null; load() }); return }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { d ->
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(d.optString("no"), fontWeight = FontWeight.Bold)
                            Text(firstValue(d, "status"), fontSize = 12.sp, color = Color.Gray)
                        }
                        Text("Lokasyon: ${firstValue(d, "locationCode")} · Atanan: ${firstValue(d, "assignedUserId")}", fontSize = 12.sp, color = Color.Gray)
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Açık yerleştirme belgesi yok.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PutAwayDocument(no: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var binLine by remember { mutableStateOf<JSONObject?>(null) }

    fun reload() {
        scope.launch {
            busy = true
            val h = BcApi.get(context, "putAways('$no')")
            if (h.ok) header = JSONObject(h.body)
            val l = BcApi.get(context, "putAwayLines?\$filter=no eq '$no'&\$top=100")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    fun register() {
        scope.launch {
            busy = true; status = "Register..."
            val r = BcApi.boundAction(context, "putAways", no, "register", "{}")
            busy = false
            status = if (r.ok) "PASS: Yerleştirme kaydedildi (HTTP ${r.httpCode})" else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
            if (r.ok) reload()
        }
    }

    val h = header
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Belge Listesi") }
            DocHeaderCard(
                title = no,
                subtitle = "Lokasyon: ${h?.optString("locationCode") ?: ""} · ${firstValue(h ?: JSONObject(), "status")}",
            )
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            Spacer(Modifier.height(4.dp))
            Text("Satırlar (${lines.size}) — bin atamak için dokunun", fontWeight = FontWeight.Bold, fontSize = 14.sp)
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(lines) { ln ->
                    Card(onClick = { binLine = ln }, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(10.dp)) {
                            Text("${ln.optString("itemNo")} — ${firstValue(ln, "lpNo")}", fontWeight = FontWeight.Medium)
                            Text("Bin: ${firstValue(ln, "binCode")} · İşlenecek: ${ln.optDouble("qtyToHandle")}", fontSize = 12.sp, color = Color.Gray)
                        }
                    }
                }
                if (lines.isEmpty() && !busy) item { EmptyState("Bu belgede satır yok.") }
            }
        }
        BottomActionBar {
            Button(onClick = { register() }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                Text("✅ Register Put-Away", fontWeight = FontWeight.Bold)
            }
        }
    }

    val bl = binLine
    if (bl != null) {
        PutAwayBinSheet(
            line = bl,
            locationCode = h?.optString("locationCode") ?: "",
            onDismiss = { binLine = null },
            onConfirm = { bin, qty ->
                binLine = null
                scope.launch {
                    busy = true; status = "Satır güncelleniyor..."
                    val body = JSONObject().apply { put("binCode", bin); put("qtyToHandle", qty) }.toString()
                    val lineNo = bl.optInt("lineNo")
                    val actType = firstValue(bl, "activityType").ifBlank { BcEnum.WhseActivityType.PUT_AWAY }
                    val r = BcApi.patch(context, "putAwayLines(activityType='$actType',no='$no',lineNo=$lineNo)", body)
                    busy = false
                    status = if (r.ok) "PASS: Satır güncellendi → $bin (HTTP ${r.httpCode})" else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                    if (r.ok) reload()
                }
            }
        )
    }
}

/** Bottom sheet: scan/enter target bin (with "Öner" = suggestBin) + qty. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PutAwayBinSheet(line: JSONObject, locationCode: String, onDismiss: () -> Unit, onConfirm: (bin: String, qty: Double) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var bin by remember { mutableStateOf(line.optString("binCode")) }
    var qty by remember { mutableStateOf(line.optDouble("qtyToHandle").let { if (it == it.toLong().toDouble()) it.toLong().toString() else it.toString() }) }
    var hint by remember { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().padding(20.dp)) {
            Text("Hedef Bin", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Text("Item: ${line.optString("itemNo")}", fontSize = 12.sp, color = Color.Gray)
            Spacer(Modifier.height(12.dp))
            ScanField("Bin", bin, { bin = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
                bin = BarcodeIntentResolver.resolve(it).value
            })
            Spacer(Modifier.height(6.dp))
            OutlinedButton(onClick = {
                scope.launch {
                    hint = "Bin öneriliyor..."
                    val body = JSONObject().apply {
                        put("itemNo", line.optString("itemNo"))
                        put("qty", qty.toDoubleOrNull() ?: 0.0)
                        put("locationCode", locationCode)
                    }.toString()
                    // suggestBin is bound to a record; call on the line's parent put-away header is not
                    // possible, so target the entity set generically with the line key context.
                    val r = BcApi.post(context, "putAways('${line.optString("no")}')/Microsoft.NAV.suggestBin", body)
                    hint = if (r.ok) {
                        val suggested = BcApi.scalarValue(r.body)
                        if (suggested.isNotBlank()) { bin = suggested; "Önerilen bin: $suggested" } else "Öneri boş döndü"
                    } else "Öneri alınamadı (HTTP ${r.httpCode})"
                }
            }) { Text("🎯 Bin Öner") }
            if (hint.isNotBlank()) { Spacer(Modifier.height(4.dp)); Text(hint, fontSize = 12.sp, color = Color.Gray) }
            Spacer(Modifier.height(10.dp))
            OutlinedTextField(qty, { qty = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Miktar") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(16.dp))
            Button(enabled = bin.isNotBlank(), modifier = Modifier.fillMaxWidth(), onClick = {
                onConfirm(bin.trim(), qty.toDoubleOrNull() ?: 0.0)
            }) { Text("Onayla") }
            Spacer(Modifier.height(24.dp))
        }
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
    var tab by remember { mutableStateOf(0) }
    val tabs = listOf("📋 Whse Shipment", "🛒 Sales Order")

    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab) {
            tabs.forEachIndexed { i, title ->
                Tab(selected = tab == i, onClick = { tab = i }, text = { Text(title, fontSize = 13.sp) })
            }
        }
        when (tab) {
            0 -> WhseShipmentTab()
            1 -> SalesOrderTab()
        }
    }
}

// ============================================================
// Tab 1: Warehouse Shipment (orijinal akış)
// ============================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WhseShipmentTab() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selected by remember { mutableStateOf<String?>(null) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val r = BcApi.get(context, "shipments?\$top=30&\$select=no,locationCode,assignedUserId,status,shipmentDate,sourceNo,shipTo,lineCount")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Sevkiyat listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "EMPTY: Released Whse Shipment yok (HTTP ${r.httpCode})"
                else "PASS: ${rows.size} belge (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(Unit) { load() }

    val sel = selected
    if (sel != null) { ShipDocument(no = sel, onBack = { selected = null; load() }); return }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { d ->
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(d.optString("no"), fontWeight = FontWeight.Bold)
                            Text(firstValue(d, "status"), fontSize = 12.sp, color = Color.Gray)
                        }
                        Text("Sevk: ${firstValue(d, "shipTo")} · Kaynak: ${firstValue(d, "sourceNo")}", fontSize = 12.sp, color = Color.Gray)
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Released Whse Shipment yok. SO'dan direkt sevkiyat için sağdaki sekmeyi kullanın.") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ShipDocument(no: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var printSlip by remember { mutableStateOf(true) }
    var invoice by remember { mutableStateOf(false) }
    var qtyLine by remember { mutableStateOf<JSONObject?>(null) }

    fun reload() {
        scope.launch {
            busy = true
            val h = BcApi.get(context, "shipments('$no')")
            if (h.ok) header = JSONObject(h.body)
            val l = BcApi.get(context, "shipmentLines?\$filter=no eq '$no'&\$top=100")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    val h = header
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Belge Listesi") }
            DocHeaderCard(
                title = no,
                subtitle = "Sevk: ${firstValue(h ?: JSONObject(), "shipTo")} · ${firstValue(h ?: JSONObject(), "status")}",
            )
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            Spacer(Modifier.height(4.dp))
            Text("Satırlar (${lines.size}) — qty/LP için dokunun", fontWeight = FontWeight.Bold, fontSize = 14.sp)
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(lines) { ln ->
                    Card(onClick = { qtyLine = ln }, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(10.dp)) {
                            Text("${ln.optString("itemNo")} — ${ln.optString("description")}", fontWeight = FontWeight.Medium)
                            Text("Sevk edilecek: ${ln.optDouble("qtyToShip")} / ${ln.optDouble("qtyOutstanding")} · LP: ${firstValue(ln, "licensePlateNo")}", fontSize = 12.sp, color = Color.Gray)
                        }
                    }
                }
                if (lines.isEmpty() && !busy) item { EmptyState("Bu belgede satır yok.") }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = printSlip, onCheckedChange = { printSlip = it })
                Text("Packing slip yazdır", fontSize = 13.sp)
                Spacer(Modifier.width(12.dp))
                Checkbox(checked = invoice, onCheckedChange = { invoice = it })
                Text("Faturalandır", fontSize = 13.sp)
            }
        }
        BottomActionBar {
            Button(
                onClick = {
                    scope.launch {
                        busy = true; status = "Post..."
                        val body = JSONObject().apply { put("print", printSlip); put("invoice", invoice) }.toString()
                        val r = BcApi.boundAction(context, "shipments", no, "post", body)
                        busy = false
                        status = if (r.ok) "PASS: Sevkiyat kaydedildi (HTTP ${r.httpCode})" else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                        if (r.ok) reload()
                    }
                },
                enabled = !busy, modifier = Modifier.fillMaxWidth()
            ) { Text("✅ Post Shipment", fontWeight = FontWeight.Bold) }
        }
    }

    val ql = qtyLine
    if (ql != null) {
        QuantityDialogSheet(
            title = "Sevk Miktarı + LP",
            itemNo = ql.optString("itemNo"),
            initialQty = ql.optDouble("qtyOutstanding").takeIf { it > 0 } ?: 1.0,
            initialUom = ql.optString("uomCode"),
            showLotSerial = false,
            onDismiss = { qtyLine = null },
            onConfirm = { res ->
                qtyLine = null
                scope.launch {
                    busy = true; status = "Satır güncelleniyor..."
                    val body = JSONObject().apply {
                        put("qtyToShip", res.quantity)
                        if (res.uom.isNotBlank()) put("binCode", firstValue(ql, "binCode"))
                    }.toString()
                    val lineNo = ql.optInt("lineNo")
                    val r = BcApi.patch(context, "shipmentLines(no='$no',lineNo=$lineNo)", body)
                    busy = false
                    status = if (r.ok) "PASS: Satır güncellendi (HTTP ${r.httpCode})" else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                    if (r.ok) reload()
                }
            }
        )
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

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val filter = if (releasedOnly) "&\$filter=status eq 'Released'" else ""
            val r = BcApi.get(
                context,
                "salesSources?\$top=30$filter&\$select=no,customerNo,customerName,shipToName,locationCode,shipmentDate,status,lineCount,outstandingQty,percentComplete,requiresWhseShipment,directShipAllowed"
            )
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: SO listesi alınamadı (HTTP ${r.httpCode}) — ${BcApi.errorMessage(r.body).take(120)}"
                else if (rows.isEmpty()) "EMPTY: ${if (releasedOnly) "Released" else "Açık"} SO yok (HTTP ${r.httpCode})"
                else "PASS: ${rows.size} satış siparişi (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(releasedOnly) { load() }

    val sel = selected
    if (sel != null) { ShipSalesOrder(no = sel, onBack = { selected = null; load() }); return }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
            Spacer(Modifier.width(12.dp))
            FilterChip(
                selected = releasedOnly,
                onClick = { releasedOnly = !releasedOnly },
                label = { Text(if (releasedOnly) "Sadece Released" else "Tüm Durumlar", fontSize = 12.sp) }
            )
        }
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { d ->
                val requiresWhse = d.optBoolean("requiresWhseShipment", false)
                Card(onClick = { selected = d.optString("no") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(d.optString("no"), fontWeight = FontWeight.Bold)
                            Row {
                                if (requiresWhse) Text("⚠ Whse Ship", fontSize = 11.sp, color = Color(0xFFD97706), modifier = Modifier.padding(end = 6.dp))
                                Text(firstValue(d, "status"), fontSize = 12.sp, color = Color.Gray)
                            }
                        }
                        Text("Müşteri: ${firstValue(d, "customerName")} (${firstValue(d, "customerNo")})", fontSize = 12.sp, color = Color.Gray)
                        val st = firstValue(d, "shipToName")
                        if (st.isNotBlank() && st != firstValue(d, "customerName")) {
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
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var invoiceToo by remember { mutableStateOf(false) }
    var qtyLine by remember { mutableStateOf<JSONObject?>(null) }
    var showScan by remember { mutableStateOf(false) }

    fun reload() {
        scope.launch {
            busy = true
            val h = BcApi.get(context, "salesSources('$no')")
            if (h.ok) header = JSONObject(h.body)
            val l = BcApi.get(context, "salesSourceLines?\$filter=no eq '$no' and type eq 'Item'&\$top=200&\$orderby=lineNo")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
            busy = false
        }
    }
    LaunchedEffect(no) { reload() }

    val h = header
    val directAllowed = h?.let { it.optBoolean("directShipAllowed", true) } ?: true
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
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
                        "⚠ Bu lokasyon (${firstValue(h, "locationCode")}) Warehouse Shipment zorunlu kılıyor. " +
                            "Direkt Post Ship yapılamaz. Whse Shipment sekmesinden ilgili belgeyi açıp sevkiyatı tamamlayın.",
                        modifier = Modifier.padding(10.dp),
                        fontSize = 12.sp,
                        color = Color(0xFF92400E),
                    )
                }
            }
            Spacer(Modifier.height(6.dp))
            StatusText(status)
            Spacer(Modifier.height(4.dp))
            Text("Satırlar (${lines.size}) — qty/bin için dokunun", fontWeight = FontWeight.Bold, fontSize = 14.sp)
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(lines) { ln ->
                    val outstanding = ln.optDouble("outstandingQuantity")
                    val toShip = ln.optDouble("qtyToShip")
                    val shipped = ln.optDouble("qtyShipped")
                    Card(
                        onClick = { if (directAllowed) qtyLine = ln },
                        enabled = directAllowed,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(Modifier.padding(10.dp)) {
                            Text("${ln.optString("itemNo")} — ${ln.optString("description")}", fontWeight = FontWeight.Medium)
                            Text("Kalan: $outstanding · Sevk: $toShip · Sevk edilen: $shipped", fontSize = 12.sp, color = Color.Gray)
                            Text("Bin: ${firstValue(ln, "binCode").ifBlank { "-" }} · UoM: ${firstValue(ln, "unitOfMeasureCode")}", fontSize = 12.sp, color = Color.Gray)
                        }
                    }
                }
                if (lines.isEmpty() && !busy) item { EmptyState("Bu SO'da satır yok (veya tümü tamamlandı).") }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = invoiceToo, onCheckedChange = { invoiceToo = it })
                Text("Aynı zamanda faturalandır", fontSize = 13.sp)
            }
        }

        BottomActionBar {
            OutlinedButton(onClick = { showScan = true }, enabled = !busy && directAllowed, modifier = Modifier.weight(1f)) { Text("📷 Item Tara") }
        }
        BottomActionBar {
            Button(
                onClick = {
                    scope.launch {
                        busy = true; status = "Post-Ship..."
                        val body = JSONObject().apply { put("invoice", invoiceToo) }.toString()
                        val r = BcApi.boundAction(context, "salesSources", no, "ship", body)
                        busy = false
                        status = if (r.ok) "PASS: SO sevkiyat kaydedildi (HTTP ${r.httpCode})"
                            else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                        if (r.ok) reload()
                    }
                },
                enabled = !busy && directAllowed, modifier = Modifier.fillMaxWidth()
            ) { Text(if (invoiceToo) "✅ Post Ship & Invoice" else "✅ Post Ship", fontWeight = FontWeight.Bold) }
        }
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
                    status = if (r.ok) "PASS: SO satırı qty=${res.quantity} (HTTP ${r.httpCode})"
                        else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                    if (r.ok) reload()
                }
            }
        )
    }

    if (showScan) {
        ScanItemSheet(title = "Item Tara (SO)", onDismiss = { showScan = false }, onItem = { _, line ->
            showScan = false
            qtyLine = line
        }, lines = lines, matchKey = "itemNo")
    }
}
