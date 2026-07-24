package com.dynops.bcwms.feature

import androidx.compose.foundation.BorderStroke
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
import com.dynops.bcwms.ui.BottomActionBar
import com.dynops.bcwms.ui.EmptyState
import com.dynops.bcwms.ui.StatusText
import com.dynops.bcwms.ui.firstValue
import kotlinx.coroutines.launch
import org.json.JSONObject

private val PackAccent = Color(0xFF6C5CE7)

/**
 * ELOG pick-bazlı paketleme. Register edilen pick, siparişlerini paketleme
 * kuyruğuna bırakır (packingOrders, her satır bir sipariş + pickNo). Liste
 * PICK bazında gruplanır; bir pick'e girince o pick'in siparişleri SIRAYLA
 * paketlenir — sipariş bitince "fatura basılıyor" bildirimi + otomatik sonraki
 * siparişe geçiş. Sevk+fatura BC tarafında (PackStationMgmt.PostOrder →
 * PostSalesOrderShipAndInvoice) otomatik kesilir.
 */
@Composable
fun PackingModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var orders by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var selectedPick by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var search by remember { mutableStateOf("") }

    fun load() {
        scope.launch {
            loading = true
            status = "Paketlenecek siparişler yükleniyor..."
            val r = BcApi.get(context, "packingOrders?\$top=500&\$orderby=readyDateTime asc")
            orders = if (r.ok) BcApi.parseValueArray(r.body).filter {
                !firstValue(it, "status").equals("Completed", ignoreCase = true)
            } else emptyList()
            status = when {
                !r.ok -> "HATA: Paketleme kuyruğu alınamadı (HTTP ${r.httpCode})"
                orders.isEmpty() -> "BOŞ: Paketlenecek sipariş yok"
                else -> "TAMAM: ${orders.size} sipariş paketleme bekliyor"
            }
            loading = false
        }
    }
    LaunchedEffect(Unit) { load() }

    val sel = selectedPick
    if (sel != null) {
        val pickOrders = orders.filter { it.optString("pickNo") == sel }
            .map { it.optString("salesOrderNo") }
        PickPackingFlow(pickNo = sel, orderNos = pickOrders, onBack = { selectedPick = null; load() })
        return
    }

    // Pick bazında grupla — her pick kartı, altındaki siparişlerin özeti.
    val byPick = orders.groupBy { it.optString("pickNo").ifBlank { "—" } }
    val shownPicks = if (search.isBlank()) byPick else byPick.filter { (pick, ords) ->
        pick.contains(search, ignoreCase = true) ||
            ords.any {
                it.optString("salesOrderNo").contains(search, ignoreCase = true) ||
                    it.optString("customerName").contains(search, ignoreCase = true)
            }
    }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("📦 Paketleme", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Spacer(Modifier.weight(1f))
            OutlinedButton(onClick = { load() }, enabled = !loading) { Text(if (loading) "…" else "🔄") }
        }
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(
            value = search,
            onValueChange = { search = it },
            label = { Text("Pick, sipariş veya müşteri ara") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(shownPicks.entries.toList(), key = { it.key }) { (pickNo, ords) ->
                val anyInProgress = ords.any { firstValue(it, "status").contains("Progress", ignoreCase = true) }
                Card(
                    onClick = { selectedPick = pickNo },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(14.dp),
                    border = BorderStroke(1.dp, if (anyInProgress) Color(0xFFFFA000) else Color(0xFFEF5350)),
                    colors = CardDefaults.cardColors(containerColor = if (anyInProgress) Color(0xFFFFF8E1) else Color(0xFFFFEBEE)),
                ) {
                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(if (anyInProgress) "🟠" else "📦", fontSize = 22.sp)
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text("Pick $pickNo", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                            Text("${ords.size} sipariş · ${ords.firstOrNull()?.optString("locationCode").orEmpty()}", fontSize = 12.sp, color = Color.Gray)
                            // İlk birkaç siparişi göster.
                            Text(
                                ords.take(3).joinToString(" · ") { it.optString("salesOrderNo") } +
                                    if (ords.size > 3) " …" else "",
                                fontSize = 11.sp, color = Color.Gray,
                            )
                        }
                        Text("Paketle ›", fontWeight = FontWeight.Bold, color = Color(0xFFC62828))
                    }
                }
            }
            if (shownPicks.isEmpty() && !loading) item { EmptyState("Paketlenecek sipariş yok.") }
        }
    }
}

/**
 * Bir pick'in siparişlerini SIRAYLA paketler. currentIndex ile ilerler; bir
 * sipariş tamamlanınca "fatura basılıyor" bildirimi gösterilir ve otomatik
 * sonrakine geçilir. Hepsi bitince pick özeti gösterilip listeye dönülür.
 */
@Composable
private fun PickPackingFlow(pickNo: String, orderNos: List<String>, onBack: () -> Unit) {
    var index by remember(pickNo) { mutableStateOf(0) }
    var doneCount by remember(pickNo) { mutableStateOf(0) }
    var pickDone by remember(pickNo) { mutableStateOf(false) }

    if (pickDone || orderNos.isEmpty()) {
        PickCompleteSummary(pickNo = pickNo, orderCount = orderNos.size, onBack = onBack)
        return
    }

    // index sınır aşarsa pick tamamlandı.
    if (index >= orderNos.size) {
        LaunchedEffect(index) { pickDone = true }
        return
    }

    val orderNo = orderNos[index]
    OrderPackingDocument(
        orderNo = orderNo,
        pickNo = pickNo,
        position = index + 1,
        total = orderNos.size,
        onOrderCompleted = {
            doneCount += 1
            if (index + 1 >= orderNos.size) pickDone = true else index += 1
        },
        onBack = onBack,
    )
}

@Composable
private fun PickCompleteSummary(pickNo: String, orderCount: Int, onBack: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("✅", fontSize = 56.sp)
        Spacer(Modifier.height(12.dp))
        Text("Pick $pickNo tamamlandı", fontWeight = FontWeight.Black, fontSize = 22.sp, color = Color(0xFF2E7D32))
        Spacer(Modifier.height(6.dp))
        Text("$orderCount sipariş sevk + fatura edildi.", fontSize = 14.sp, color = Color(0xFF2E7D32))
        Spacer(Modifier.height(24.dp))
        Button(onClick = onBack, modifier = Modifier.fillMaxWidth().height(52.dp)) {
            Text("‹ Paketleme Listesi", fontWeight = FontWeight.Bold)
        }
    }
}

/**
 * Tek siparişi paketler: session başlat → line'ları okut → tamamlanınca
 * "fatura basılıyor" bildirimi + onOrderCompleted (üst akış sonrakine geçer).
 */
@Composable
private fun OrderPackingDocument(
    orderNo: String,
    pickNo: String,
    position: Int,
    total: Int,
    onOrderCompleted: () -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var queue by remember(orderNo) { mutableStateOf<JSONObject?>(null) }
    var lines by remember(orderNo) { mutableStateOf<List<JSONObject>>(emptyList()) }
    var sessionId by remember(orderNo) { mutableStateOf(0) }
    var status by remember(orderNo) { mutableStateOf("") }
    var busy by remember(orderNo) { mutableStateOf(false) }
    var itemInput by remember(orderNo) { mutableStateOf("") }
    var boxInput by remember(orderNo) { mutableStateOf("") }
    // ELOG: kutu adımında varsayılan "karton üret" öne çıkar; kullanıcı kendi
    // kutusunu okutmak isterse bu bayrakla scan alanı açılır.
    var showBoxScan by remember(orderNo) { mutableStateOf(false) }
    var invoicing by remember(orderNo) { mutableStateOf(false) }

    suspend fun reloadNow() {
        val q = BcApi.get(context, "packingOrders('$orderNo')")
        if (q.ok) {
            queue = JSONObject(q.body)
            sessionId = queue?.optInt("sessionEntryNo") ?: 0
        }
        if (sessionId > 0) {
            val l = BcApi.get(context, "packSessionLines?\$filter=sessionEntryNo eq $sessionId&\$top=500")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
        }
    }

    suspend fun startIfNeeded() {
        reloadNow()
        if (sessionId > 0) return
        status = "Paketleme başlatılıyor..."
        // ELOG: paketlemeyi ÜSTLENEN WMS operatörünü kaydet (başlatan = üstlenen).
        // Eski publish'te startPackingAs yoksa (400/404) düz startPacking'e düş.
        val me = BcApi.currentUserId(context)
        var r = if (me.isNotBlank())
            BcApi.boundAction(context, "packingOrders", orderNo, "startPackingAs",
                JSONObject().apply { put("userId", me) }.toString())
        else BcApi.boundAction(context, "packingOrders", orderNo, "startPacking", "{}")
        if (!r.ok && (r.httpCode == 400 || r.httpCode == 404))
            r = BcApi.boundAction(context, "packingOrders", orderNo, "startPacking", "{}")
        if (r.ok) {
            sessionId = BcApi.scalarValue(r.body).toIntOrNull() ?: 0
            status = "🔴 Eksik ürünleri sırayla okutun"
            reloadNow()
        } else status = "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
    }

    fun scanItem(raw: String) {
        if (raw.isBlank() || sessionId == 0 || busy || invoicing) return
        val resolved = BarcodeIntentResolver.resolve(raw)
        val itemNo = (resolved.itemNo ?: resolved.value).trim()
        scope.launch {
            busy = true
            status = "$itemNo kontrol ediliyor..."
            val body = JSONObject().apply {
                put("sessionId", sessionId)
                put("itemNo", itemNo)
                put("qty", 1)
            }.toString()
            val r = BcApi.boundAction(context, "packOps", "", "scanItem", body)
            if (r.ok) {
                itemInput = ""
                reloadNow()
                // ELOG kutu-sonra: ürünler bitse bile sipariş kutu okutulmadan
                // KAPANMAZ (AL TryCompleteOrder kutu ister). Tüm satır yeşilse
                // kutu adımı UI'da otomatik belirir (aşağıdaki allPacked).
                val nowComplete = firstValue(queue ?: JSONObject(), "status").equals("Completed", true)
                status = if (nowComplete) {
                    invoicing = true; "🧾 $orderNo tamamlandı · fatura basılıyor…"
                } else "✅ $itemNo paketlendi"
            } else status = "❌ ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            busy = false
        }
    }

    // ELOG kutu-sonra: tüm ürünler okununca kutuyu okut → sipariş kapanır + fiş.
    // Kutu barkodu boş bırakılırsa BC geçici karton (CARTON-S) üretir.
    fun scanBox(raw: String) {
        if (sessionId == 0 || busy || invoicing) return
        val boxLp = BarcodeIntentResolver.resolve(raw).value.trim()
        scope.launch {
            busy = true
            status = "📦 Kutu bağlanıyor…"
            val body = JSONObject().apply {
                put("sessionId", sessionId)
                put("orderNo", orderNo)
                put("boxLpNo", boxLp) // boş → BC karton üretir
                put("lpTemplateCode", "")
            }.toString()
            val r = BcApi.boundAction(context, "packOps", "", "setBoxForOrder", body)
            if (r.ok) {
                boxInput = ""
                reloadNow()
                // setBoxForOrder içinde TryCompleteOrder çağrılır → sipariş kapanır.
                val nowComplete = firstValue(queue ?: JSONObject(), "status").equals("Completed", true)
                if (nowComplete) {
                    invoicing = true
                    status = "🧾 $orderNo kutulandı · sevk+fatura+fiş…"
                } else status = "📦 Kutu bağlandı: ${BcApi.scalarValue(r.body)}"
            } else status = "❌ ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            busy = false
        }
    }

    LaunchedEffect(orderNo) { busy = true; startIfNeeded(); busy = false }

    // "Fatura basılıyor" bildirimi kısa süre gösterilip otomatik sonraki siparişe geçer.
    LaunchedEffect(invoicing) {
        if (invoicing) {
            kotlinx.coroutines.delay(1400)
            onOrderCompleted()
        }
    }

    val expected = lines.sumOf { it.optDouble("qtyExpected") }
    val packed = lines.sumOf { it.optDouble("qtyPacked") }
    // Tüm satırlar tam paketlendi mi? Öyleyse kutu okutma adımı gösterilir.
    val allPacked = lines.isNotEmpty() && lines.all { it.optDouble("qtyPacked") >= it.optDouble("qtyExpected") }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Paketleme Listesi") }
            // Pick + sipariş başlığı — hangi pick'in kaçıncı siparişindeyiz.
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = if (invoicing) Color(0xFFE8F5E9) else MaterialTheme.colorScheme.surface),
            ) {
                Column(Modifier.padding(14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Surface(color = PackAccent.copy(alpha = 0.12f), shape = RoundedCornerShape(8.dp)) {
                            Text("Pick $pickNo", Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                                fontWeight = FontWeight.Bold, fontSize = 12.sp, color = PackAccent)
                        }
                        Spacer(Modifier.weight(1f))
                        Text("Sipariş $position / $total", fontSize = 12.sp, color = Color.Gray)
                    }
                    Spacer(Modifier.height(6.dp))
                    Text("🧾 $orderNo", fontWeight = FontWeight.Bold, fontSize = 20.sp)
                    Text(queue?.optString("customerName").orEmpty(), fontSize = 14.sp)
                    queue?.optString("startedByUser")?.takeIf { it.isNotBlank() }?.let {
                        Text("👤 Paketleyen: $it", fontSize = 11.sp, color = Color.Gray)
                    }
                    Spacer(Modifier.height(8.dp))
                    LinearProgressIndicator(
                        progress = { if (expected > 0) (packed / expected).toFloat().coerceIn(0f, 1f) else 0f },
                        modifier = Modifier.fillMaxWidth(),
                        color = if (invoicing) Color(0xFF2E7D32) else Color(0xFFC62828),
                    )
                    Text("Paketlenen: ${packQty(packed)} / ${packQty(expected)}", fontSize = 12.sp)
                }
            }
            Spacer(Modifier.height(8.dp))
            StatusText(status)
            Spacer(Modifier.height(8.dp))

            when {
                invoicing -> {
                    Card(colors = CardDefaults.cardColors(containerColor = Color(0xFFE8F5E9)), modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.fillMaxWidth().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("🧾 SİPARİŞ TAMAMLANDI", color = Color(0xFF2E7D32), fontWeight = FontWeight.Black, fontSize = 18.sp)
                            Text("Sevk + fatura kesiliyor… Sonraki siparişe geçiliyor.", color = Color(0xFF2E7D32), fontSize = 12.sp)
                        }
                    }
                }
                // ELOG kutu-sonra: ürünler bitti → kutuyu okut → sipariş kapanır + fiş.
                allPacked -> {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = Color.White),
                        border = BorderStroke(1.dp, Color(0xFFE0E0E0)),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(Modifier.fillMaxWidth().padding(16.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("✅", fontSize = 18.sp)
                                Spacer(Modifier.width(6.dp))
                                Text("Tüm ürünler paketlendi", fontWeight = FontWeight.Bold, fontSize = 16.sp, color = Color(0xFF2E7D32))
                            }
                            Text("Şimdi sevk kutusunu seç. Kendi kutunu okutabilir ya da sistemin karton üretmesini sağlayabilirsin.", fontSize = 12.sp, color = Color.Gray)
                            Spacer(Modifier.height(14.dp))

                            // Önerilen: sistem karton üretsin (birincil aksiyon).
                            Card(
                                colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF3E0)),
                                border = BorderStroke(1.dp, Color(0xFFEF6C00).copy(alpha = 0.4f)),
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Text("📦", fontSize = 26.sp)
                                    Spacer(Modifier.width(12.dp))
                                    Column(Modifier.weight(1f)) {
                                        Text("Önerilen kutu", fontSize = 11.sp, color = Color(0xFFBF360C))
                                        Text("Karton kutu üretilecek", fontWeight = FontWeight.Bold, color = Color(0xFFBF360C))
                                    }
                                }
                            }
                            Spacer(Modifier.height(12.dp))
                            Button(
                                onClick = { scanBox("") },
                                enabled = !busy,
                                modifier = Modifier.fillMaxWidth().height(50.dp),
                            ) { Text("✓ Karton üret ve siparişi kapat", fontWeight = FontWeight.Bold) }

                            Spacer(Modifier.height(10.dp))
                            if (!showBoxScan) {
                                TextButton(
                                    onClick = { showBoxScan = true },
                                    enabled = !busy,
                                    modifier = Modifier.fillMaxWidth(),
                                ) { Text("📷 Kendi kutunu okut") }
                            } else {
                                Text("Sevk kutusunun barkodunu okut:", fontSize = 12.sp, color = Color.Gray)
                                Spacer(Modifier.height(6.dp))
                                ScanField(
                                    label = "📦 Kutu / karton okut",
                                    value = boxInput,
                                    onValueChange = { boxInput = it },
                                    modifier = Modifier.fillMaxWidth(),
                                    enabled = !busy,
                                    onScanned = { scanBox(it) },
                                )
                                Spacer(Modifier.height(6.dp))
                                TextButton(
                                    onClick = { showBoxScan = false; boxInput = "" },
                                    enabled = !busy,
                                    modifier = Modifier.fillMaxWidth(),
                                ) { Text("‹ Vazgeç, karton üretimine dön", fontSize = 12.sp) }
                            }
                        }
                    }
                }
                else -> {
                    ScanField(
                        label = "📷 Ürün okut",
                        value = itemInput,
                        onValueChange = { itemInput = it },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !busy,
                        onScanned = { scanItem(it) },
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Paketlenecek ürünler", fontWeight = FontWeight.Bold)
                    Text("Kırmızı = bekliyor · Yeşil = paketlendi", fontSize = 11.sp, color = Color.Gray)
                }
                val doneCount = lines.count { it.optDouble("qtyPacked") >= it.optDouble("qtyExpected") }
                Surface(color = PackAccent.copy(alpha = 0.12f), shape = RoundedCornerShape(8.dp)) {
                    Text(
                        "$doneCount/${lines.size}",
                        Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                        fontWeight = FontWeight.Bold, fontSize = 14.sp, color = PackAccent,
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(lines, key = { it.optInt("lineNo") }) { line ->
                    val done = line.optDouble("qtyPacked") >= line.optDouble("qtyExpected")
                    Card(
                        // Toplama ekranıyla tutarlı: bekleyen satırlar yumuşak pembe zemin.
                        colors = CardDefaults.cardColors(containerColor = if (done) Color(0xFFE8F5E9) else Color(0xFFFFF0F0)),
                        border = BorderStroke(1.dp, if (done) Color(0xFF66BB6A) else Color(0xFFF3BDBD)),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(if (done) "✅" else "📦", fontSize = 20.sp)
                            Spacer(Modifier.width(10.dp))
                            Column(Modifier.weight(1f)) {
                                Text(line.optString("itemNo"), fontWeight = FontWeight.Bold)
                                Text(line.optString("description"), fontSize = 12.sp, color = Color.Gray)
                            }
                            Spacer(Modifier.width(8.dp))
                            Text(
                                "${packQty(line.optDouble("qtyPacked"))}/${packQty(line.optDouble("qtyExpected"))}",
                                fontSize = 20.sp, fontWeight = FontWeight.Black,
                                color = if (done) Color(0xFF2E7D32) else Color(0xFFC62828),
                            )
                        }
                    }
                }
                if (lines.isEmpty() && !busy) item { EmptyState("Sipariş satırları hazırlanamadı.") }
            }
        }
        BottomActionBar {
            OutlinedButton(
                onClick = { scope.launch { busy = true; reloadNow(); busy = false } },
                enabled = !busy && !invoicing,
                modifier = Modifier.weight(1f),
            ) { Text("🔄 Yenile") }
            // Sonraki siparişi elle atlama (isteğe bağlı).
            OutlinedButton(
                onClick = { onOrderCompleted() },
                enabled = !busy && !invoicing && position < total,
                modifier = Modifier.weight(1f),
            ) { Text("Sonraki ›") }
        }
    }
}

private fun packQty(value: Double): String =
    if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()
