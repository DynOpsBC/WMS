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
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import org.json.JSONObject

private val PackAccent = Color(0xFF6C5CE7)

/**
 * İyimser paketleme için: verilen sipariş+ürünün ilk eksik satırında
 * paketlenen miktarı [delta] kadar artırıp YENİ liste döndürür (Compose'un
 * değişimi görmesi için nesneler kopyalanır).
 */
private fun bumpPackedQty(
    lines: List<JSONObject>,
    orderNo: String,
    itemNo: String,
    delta: Double,
): List<JSONObject> {
    var applied = false
    return lines.map { l ->
        if (applied) return@map l
        val matches = l.optString("sourceOrderNo").equals(orderNo, ignoreCase = true) &&
            l.optString("itemNo").equals(itemNo, ignoreCase = true) &&
            l.optDouble("qtyPacked") < l.optDouble("qtyExpected")
        if (!matches) return@map l
        applied = true
        JSONObject(l.toString()).apply {
            put("qtyPacked", (l.optDouble("qtyPacked") + delta).coerceAtMost(l.optDouble("qtyExpected")))
        }
    }
}

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
        val pickOrderCount = orders.count { it.optString("pickNo") == sel }
        PickPackingDocument(pickNo = sel, orderCount = pickOrderCount, onBack = { selectedPick = null; load() })
        return
    }

    // Pick bazında grupla — her pick kartı, altındaki siparişlerin özeti.
    val byPick = orders.groupBy { it.optString("pickNo").ifBlank { "—" } }
    val shownPicks = if (search.isBlank()) byPick else byPick.filter { (pick, ords) ->
        pick.contains(search, ignoreCase = true) ||
            ords.any {
                it.optString("salesOrderNo").contains(search, ignoreCase = true) ||
                    it.optString("customerName").contains(search, ignoreCase = true) ||
                    // Sepet (LP) ile de bulunabilsin.
                    it.optString("mainLpNo").contains(search, ignoreCase = true)
            }
    }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("📦 Paketleme", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Spacer(Modifier.weight(1f))
            OutlinedButton(onClick = { load() }, enabled = !loading) { Text(if (loading) "…" else "🔄") }
        }
        Spacer(Modifier.height(8.dp))
        // Sepet/LP, pick ya da sipariş okutulunca DOĞRUDAN o belgeye gir —
        // paketleyici listede aramakla uğraşmasın.
        ScanField(
            label = "📷 Sepet / pick / sipariş okut",
            value = search,
            onValueChange = { search = it },
            modifier = Modifier.fillMaxWidth(),
            enabled = !loading,
            onScanned = { raw ->
                val v = BarcodeIntentResolver.resolve(raw).value.trim()
                search = v
                val hit = byPick.entries.firstOrNull { (pick, ords) ->
                    pick.equals(v, ignoreCase = true) ||
                        ords.any {
                            it.optString("mainLpNo").equals(v, ignoreCase = true) ||
                                it.optString("salesOrderNo").equals(v, ignoreCase = true)
                        }
                }
                if (hit != null) {
                    search = ""
                    selectedPick = hit.key
                } else status = "⚠️ '$v' paketleme kuyruğunda bulunamadı"
            },
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
                            Text(
                                "📦 ${ords.size} sipariş · ${ords.firstOrNull()?.optString("locationCode").orEmpty()}",
                                fontSize = 12.sp, fontWeight = FontWeight.Medium,
                            )
                            // İlk birkaç siparişi göster.
                            Text(
                                ords.take(3).joinToString(" · ") { it.optString("salesOrderNo") } +
                                    if (ords.size > 3) " …" else "",
                                fontSize = 11.sp, color = Color.Gray,
                            )
                            // Ürünlerin toplandığı sepet (LP) — paketleyici
                            // sepeti okutarak da bu belgeye girebilir.
                            val lp = ords.firstNotNullOfOrNull {
                                it.optString("mainLpNo").takeIf { s -> s.isNotBlank() }
                            }
                            if (!lp.isNullOrBlank()) {
                                Text(
                                    "📦 Sepet: $lp",
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Color(0xFF4527A0),
                                )
                            }
                            // Paketlemeyi kim üstlendi (varsa).
                            val packer = ords.firstNotNullOfOrNull {
                                it.optString("startedByUser").takeIf { s -> s.isNotBlank() }
                            }
                            if (!packer.isNullOrBlank()) {
                                Text("👤 Paketleyen: $packer", fontSize = 11.sp, color = Color(0xFF6D4C41))
                            }
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
 * ELOG "ürün-önce" paketleme: pick'in TÜM siparişleri tek session'da toplanır.
 * Operatör sepetten eline gelen ürünü okutur; BC (ScanItem) o ürünü doğru
 * siparişe yazar. Satırlar siparişe göre gruplanıp bilgi amaçlı gösterilir.
 * Bir siparişin payı bitince o sipariş için kutu istenir; kutulanınca sevk+
 * fatura kesilir. Tüm siparişler kapanınca pick özeti gösterilir.
 */
@Composable
private fun PickPackingDocument(
    pickNo: String,
    orderCount: Int,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var sessionId by remember(pickNo) { mutableStateOf(0) }
    var lines by remember(pickNo) { mutableStateOf<List<JSONObject>>(emptyList()) }
    // Sipariş no -> müşteri adı (packingOrders'tan; başlıkta göstermek için).
    var customerByOrder by remember(pickNo) { mutableStateOf<Map<String, String>>(emptyMap()) }
    var status by remember(pickNo) { mutableStateOf("") }
    var busy by remember(pickNo) { mutableStateOf(false) }
    var itemInput by remember(pickNo) { mutableStateOf("") }
    var boxInput by remember(pickNo) { mutableStateOf("") }
    var showBoxScan by remember(pickNo) { mutableStateOf(false) }
    // BC'de artık açık olmayan (silinmiş/kaydedilmiş) siparişler. Bunlar asla
    // kapanamaz; kutu adımında ekranı kilitlememeleri için atlanır.
    var blockedOrders by remember(pickNo) { mutableStateOf<Set<String>>(emptySet()) }
    // Toplamada kullanılan ana sepet — paketleyici ürünleri nereden alacağını görsün.
    var mainLp by remember(pickNo) { mutableStateOf("") }
    var pickDone by remember(pickNo) { mutableStateOf(false) }
    // Kullanıcının elle açtığı (katlanmış) siparişler. Aktif sipariş her zaman açık.
    var expandedOrders by remember(pickNo) { mutableStateOf<Set<String>>(emptySet()) }

    suspend fun reloadLines() {
        if (sessionId > 0) {
            val l = BcApi.get(context, "packSessionLines?\$filter=sessionEntryNo eq $sessionId&\$top=1000")
            lines = if (l.ok) BcApi.parseValueArray(l.body) else emptyList()
        }
    }

    // Müşteri adlarını packingOrders'tan (pick filtresiyle) bir kez çek.
    suspend fun loadCustomers() {
        val r = BcApi.get(context, "packingOrders?\$filter=pickNo eq '$pickNo'&\$top=500")
        if (r.ok) {
            val rows = BcApi.parseValueArray(r.body)
            customerByOrder = rows.associate {
                it.optString("salesOrderNo") to it.optString("customerName")
            }
            // Ana sepet pick bazında aynı — ilk dolu değeri al.
            mainLp = rows.firstNotNullOfOrNull {
                it.optString("mainLpNo").takeIf { s -> s.isNotBlank() }
            }.orEmpty()
        }
    }

    suspend fun startIfNeeded() {
        status = "Paketleme başlatılıyor..."
        val me = BcApi.currentUserId(context)
        val body = JSONObject().apply {
            put("pickNo", pickNo)
            put("userId", me)
        }.toString()
        val r = BcApi.boundAction(context, "packOps", "", "startPickPacking", body)
        if (r.ok) {
            sessionId = BcApi.scalarValue(r.body).toIntOrNull() ?: 0
            // Müşteri adları ve satırlar birbirinden bağımsız — PARALEL çek
            // (sırayla ~2 istek beklemesi oluyordu, belge açılışı yavaşlıyordu).
            coroutineScope {
                launch { loadCustomers() }
                launch { reloadLines() }
            }
            status = "🔴 Sepetteki ürünleri okutun — sistem doğru siparişe yazar"
        } else if (r.httpCode == 404) {
            // startPickPacking AL action'ı henüz publish edilmemiş — sessiz
            // "hazırlanıyor" durumu (korkutucu HATA yazısı gösterme).
            status = "⏳ Paketleme hazırlanıyor…"
        } else status = "⏳ Paketleme hazırlanıyor…"
    }

    // ELOG katı kilit: bir siparişe başlandıysa (kısmen paketli ama bitmemiş),
    // o siparişin TÜM ürünleri bitmeden başka siparişin ürünü okutulamaz.
    // activeOrder = ilk kısmen-paketli sipariş; yoksa null (serbest okutma).
    fun activeLockedOrder(): String? =
        lines.groupBy { it.optString("sourceOrderNo") }
            .entries
            .firstOrNull { (_, ords) ->
                val packed = ords.sumOf { it.optDouble("qtyPacked") }
                val expected = ords.sumOf { it.optDouble("qtyExpected") }
                packed > 0 && packed < expected
            }?.key

    // Bir siparişte kalan (bekleyen) toplam ürün adedi.
    fun orderRemaining(orderNo: String): Double =
        lines.filter { it.optString("sourceOrderNo") == orderNo }
            .sumOf { (it.optDouble("qtyExpected") - it.optDouble("qtyPacked")).coerceAtLeast(0.0) }

    // Okutulan ürünün YAZILACAĞI siparişi seç:
    // 1) Aktif (yarım) sipariş varsa → o siparişin bekleyen satırı ise oraya.
    // 2) Yoksa → ürünün bekleyen satırı olan siparişlerden TOPLAM KALANI EN AZ
    //    olan (o sipariş daha çabuk kapanır). Eşitlikte sipariş no'ya göre.
    fun targetOrderFor(itemNo: String): String? {
        val candidates = lines.filter {
            it.optString("itemNo").equals(itemNo, ignoreCase = true) &&
                it.optDouble("qtyPacked") < it.optDouble("qtyExpected")
        }.map { it.optString("sourceOrderNo") }.distinct()
        if (candidates.isEmpty()) return null
        val locked = activeLockedOrder()
        if (locked != null) return if (locked in candidates) locked else null
        // En az kalan; eşitlikte sipariş no'ya göre deterministik.
        return candidates.sortedBy { it }.minByOrNull { orderRemaining(it) }
    }

    /**
     * Ürün okut. İYİMSER: satırın paketlenen miktarı anında yerelde artar ve
     * kırmızıdan yeşile döner; BC yazımı arka planda gider. Operatör ard arda
     * okutmaya devam edebilir — hata olursa gerçek durum geri yüklenir.
     */
    fun scanItem(raw: String) {
        if (raw.isBlank() || sessionId == 0) return
        val resolved = BarcodeIntentResolver.resolve(raw)
        val itemNo = (resolved.itemNo ?: resolved.value).trim()
        val locked = activeLockedOrder()
        val target = targetOrderFor(itemNo)
        // Aktif sipariş varsa ve bu ürün ona ait değilse → kilit reddi.
        if (locked != null && target == null) {
            status = "🔒 Önce $locked siparişini bitir — bu ürün o siparişte beklenmiyor"
            itemInput = ""
            return
        }
        if (target == null) {
            status = "❌ $itemNo bu pickte beklenmiyor veya tümü paketlendi"
            itemInput = ""
            return
        }
        // 1) Yerel artış — ekran anında tepki verir.
        itemInput = ""
        lines = bumpPackedQty(lines, target, itemNo, 1.0)
        status = "✅ $itemNo → $target"
        // 2) BC'ye arka planda yaz.
        scope.launch {
            val body = JSONObject().apply {
                put("sessionId", sessionId)
                put("orderNo", target)
                put("itemNo", itemNo)
                put("qty", 1)
            }.toString()
            val r = BcApi.boundAction(context, "packOps", "", "scanItemForOrder", body)
            if (r.ok) {
                // scanItemForOrder dönüşü: tamamlandıysa o sipariş no'su, yoksa boş.
                val done = BcApi.scalarValue(r.body).trim()
                if (done.isNotBlank()) {
                    status = "🧾 $done tamamlandı — kargo kolisini okutun"
                    reloadLines()   // sipariş kapandı → gerçek durumu al
                }
            } else {
                status = "❌ ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                reloadLines()       // iyimser artışı geri al
            }
        }
    }

    // Siparişe KARGO KOLİSİ bağla → sevk+fatura+fiş.
    // Okutulan barkod müşteriye giden kolinin barkodudur (kargo etiketi / SSCC /
    // matbu koli barkodu); sistemde kayıtlı bir LP olmak ZORUNDA DEĞİLDİR —
    // depoda kalan sepetle (tote) karıştırılmamalı. Boş gönderilirse BC karton üretir.
    fun scanBox(orderNo: String, raw: String) {
        if (sessionId == 0 || busy) return
        val boxLp = BarcodeIntentResolver.resolve(raw).value.trim()
        scope.launch {
            busy = true
            status = "📦 $orderNo için kargo kolisi bağlanıyor…"
            val body = JSONObject().apply {
                put("sessionId", sessionId)
                put("orderNo", orderNo)
                put("boxLpNo", boxLp)
                put("lpTemplateCode", "")
            }.toString()
            val r = BcApi.boundAction(context, "packOps", "", "setBoxForOrder", body)
            if (r.ok) {
                boxInput = ""; showBoxScan = false
                blockedOrders = blockedOrders - orderNo
                reloadLines()
                status = "🧾 $orderNo kolilendi · sevk+fatura+fiş kesildi"
            } else {
                val msg = BcApi.errorMessage(r.body)
                // Satış siparişi yoksa/kapalıysa bu sipariş ASLA kapanmaz;
                // ekran kutu adımında kilitleniyordu. Siparişi "engelli" işaretle,
                // operatör atlayıp sonraki siparişe geçebilsin.
                val gone = r.httpCode == 404 ||
                    msg.contains("Sales Header does not exist", ignoreCase = true) ||
                    msg.contains("artık açık değil", ignoreCase = true)
                if (gone) {
                    blockedOrders = blockedOrders + orderNo
                    boxInput = ""; showBoxScan = false
                    status = "⚠️ $orderNo BC'de açık değil — atlandı. Sorumluya bildirin."
                } else status = "❌ $msg (HTTP ${r.httpCode})"
            }
            busy = false
        }
    }

    LaunchedEffect(pickNo) { busy = true; startIfNeeded(); busy = false }

    if (pickDone) {
        PickCompleteSummary(pickNo = pickNo, orderCount = orderCount, onBack = onBack)
        return
    }

    // Satırları siparişe göre grupla (görsel bilgi). Her grup: sipariş no +
    // müşteri + paketlenen/toplam. Bekleyen satır pembe, tamamlanan yeşil.
    val byOrder = lines.groupBy { it.optString("sourceOrderNo") }
    // Kutu bekleyen siparişler: tüm satırları paketlenmiş ama henüz kutusuz.
    val boxNeeded = byOrder.filter { (orderNo, ords) ->
        // BC'de açık olmayan sipariş kapanamaz → kutu adımına düşürme,
        // yoksa ekran o siparişte kilitleniyor.
        orderNo !in blockedOrders &&
            ords.isNotEmpty() &&
            ords.all { it.optDouble("qtyPacked") >= it.optDouble("qtyExpected") } &&
            ords.any { it.optString("boxLpNo").isBlank() }
    }.keys.toList()
    // Tüm satırlar paketlendi + hepsi kutulandı → pick biter.
    val allBoxed = lines.isNotEmpty() &&
        lines.all { it.optDouble("qtyPacked") >= it.optDouble("qtyExpected") && it.optString("boxLpNo").isNotBlank() }
    LaunchedEffect(allBoxed) { if (allBoxed) { kotlinx.coroutines.delay(900); pickDone = true } }

    val totalExpected = lines.sumOf { it.optDouble("qtyExpected") }
    val totalPacked = lines.sumOf { it.optDouble("qtyPacked") }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Paketleme Listesi") }
            // Session açılınca gerçek sipariş sayısı satırlardan; açılmadan
            // liste kartından gelen orderCount kullanılır.
            val orderCountShown = if (byOrder.isNotEmpty()) byOrder.size else orderCount
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Surface(color = PackAccent.copy(alpha = 0.12f), shape = RoundedCornerShape(8.dp)) {
                            Text("Pick $pickNo", Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                                fontWeight = FontWeight.Bold, fontSize = 12.sp, color = PackAccent)
                        }
                        Spacer(Modifier.weight(1f))
                        Text(
                            "📦 $orderCountShown sipariş · 🧾 ${packQty(totalExpected)} ürün",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                    LinearProgressIndicator(
                        progress = { if (totalExpected > 0) (totalPacked / totalExpected).toFloat().coerceIn(0f, 1f) else 0f },
                        modifier = Modifier.fillMaxWidth(),
                        color = Color(0xFF2E7D32),
                    )
                    Text("Paketlenen: ${packQty(totalPacked)} / ${packQty(totalExpected)} ürün", fontSize = 12.sp)
                    // Ürünler hangi sepette toplandı — paketleyici nereden
                    // alacağını bilsin (toplamadaki ana sepet pick'ten taşınır).
                    if (mainLp.isNotBlank()) {
                        Spacer(Modifier.height(6.dp))
                        Surface(
                            color = Color(0xFF6C5CE7).copy(alpha = 0.12f),
                            shape = RoundedCornerShape(8.dp),
                        ) {
                            Text(
                                "📦 Bu sepete toplandı: $mainLp",
                                Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color(0xFF4527A0),
                            )
                        }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            StatusText(status)
            Spacer(Modifier.height(8.dp))

            // Kutu adımı yokken ürün okutma alanı sabit dursun (klavye/tetik
            // odağı kaymasın). Kutu adımı geldiğinde kart LİSTENİN İÇİNE alınır
            // (aşağıda) — yatay ekranda sabit dursaydı sipariş listesini
            // sıkıştırıp satırları kırpardı.
            if (boxNeeded.isEmpty()) {
                // Ürün okut alanı — sadece barkod okutarak, doğru siparişe otomatik.
                ScanField(
                    label = "📷 Ürün okut",
                    value = itemInput,
                    onValueChange = { itemInput = it },
                    modifier = Modifier.fillMaxWidth(),
                    // İyimser okutma: arka planda BC yazımı sürerken bile
                    // operatör sonraki ürünü okutabilsin.
                    enabled = sessionId > 0,
                    onScanned = { scanItem(it) },
                )
                Spacer(Modifier.height(10.dp))
            }

            val activeOrder = activeLockedOrder()
            // Sipariş sırası: AKTİF önce, sonra kalanı en az olan (öncelikli).
            // Kutulanmış/tamamlanmış olanlar en sona.
            val orderedKeys = byOrder.keys.sortedWith(
                compareByDescending<String> { it == activeOrder }
                    .thenBy { k -> byOrder[k]?.all { it.optString("boxLpNo").isNotBlank() } == true }
                    .thenBy { k -> orderRemaining(k) }
                    .thenBy { it }
            )
            Text(
                if (activeOrder != null) "🔒 Önce $activeOrder siparişini bitir"
                else "Sepetten bir ürün okut — sistem en uygun siparişe yazar.",
                fontWeight = FontWeight.Bold,
                color = if (activeOrder != null) Color(0xFF1565C0) else Color(0xFF333333),
            )
            Spacer(Modifier.height(8.dp))
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                // Kutu adımı listenin başında: yüksek kart artık listeyi
                // sıkıştırmıyor, gerekirse liste ile birlikte kaydırılıyor.
                if (boxNeeded.isNotEmpty()) {
                    val boxOrderNo = boxNeeded.first()
                    item(key = "box-step") {
                        BoxForOrderCard(
                            orderNo = boxOrderNo,
                            customer = customerByOrder[boxOrderNo].orEmpty(),
                            remaining = boxNeeded.size,
                            busy = busy,
                            showScan = showBoxScan,
                            boxInput = boxInput,
                            onBoxInput = { boxInput = it },
                            onUseCarton = { scanBox(boxOrderNo, "") },
                            onScanBox = { scanBox(boxOrderNo, it) },
                            onToggleScan = { showBoxScan = it },
                            onSkip = {
                                blockedOrders = blockedOrders + boxOrderNo
                                boxInput = ""; showBoxScan = false
                                status = "⏭ $boxOrderNo atlandı — sorumluya bildirin."
                            },
                        )
                    }
                }
                orderedKeys.forEach { orderNo ->
                    val ords = byOrder[orderNo].orEmpty()
                    val orderDone = ords.all { it.optDouble("qtyPacked") >= it.optDouble("qtyExpected") }
                    val boxed = ords.any { it.optString("boxLpNo").isNotBlank() }
                    val isActive = orderNo == activeOrder
                    val remainingInOrder = orderRemaining(orderNo).toInt()
                    // Aktif sipariş her zaman açık; diğerleri sadece elle açılınca.
                    val expanded = isActive || orderNo in expandedOrders
                    item(key = "hdr-$orderNo") {
                        Surface(
                            color = if (isActive) Color(0xFF1565C0) else Color(0xFFF3F0FF),
                            shape = RoundedCornerShape(10.dp),
                            modifier = Modifier.fillMaxWidth(),
                            onClick = {
                                if (!isActive) expandedOrders =
                                    if (orderNo in expandedOrders) expandedOrders - orderNo else expandedOrders + orderNo
                            },
                        ) {
                            Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(if (isActive) "🔵" else if (boxed) "✅" else "🧾", fontSize = 16.sp)
                                Spacer(Modifier.width(8.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(orderNo, fontWeight = FontWeight.Bold, fontSize = 14.sp,
                                        color = if (isActive) Color.White else PackAccent)
                                    Text(customerByOrder[orderNo].orEmpty(), fontSize = 11.sp,
                                        color = if (isActive) Color.White.copy(alpha = 0.85f) else Color.Gray)
                                }
                                Text(
                                    when {
                                        boxed -> "kolilendi"
                                        orderDone -> "📦 koli bekliyor"
                                        isActive -> "$remainingInOrder ürün kaldı"
                                        else -> "$remainingInOrder ürün"
                                    },
                                    fontSize = 12.sp, fontWeight = FontWeight.Bold,
                                    color = when {
                                        isActive -> Color.White
                                        boxed -> Color(0xFF2E7D32)
                                        orderDone -> Color(0xFFEF6C00)
                                        else -> Color.Gray
                                    },
                                )
                                if (!isActive) {
                                    Spacer(Modifier.width(6.dp))
                                    Text(if (expanded) "▾" else "▸", color = PackAccent, fontSize = 14.sp)
                                }
                            }
                        }
                    }
                    if (expanded) {
                        items(ords, key = { it.optInt("lineNo") }) { line ->
                            val done = line.optDouble("qtyPacked") >= line.optDouble("qtyExpected")
                            Card(
                                colors = CardDefaults.cardColors(containerColor = if (done) Color(0xFFE8F5E9) else Color(0xFFFFF0F0)),
                                border = BorderStroke(if (isActive && !done) 2.dp else 1.dp,
                                    if (done) Color(0xFF66BB6A) else if (isActive) Color(0xFF1565C0) else Color(0xFFF3BDBD)),
                                modifier = Modifier.fillMaxWidth().padding(start = 12.dp),
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
                    }
                }
                if (lines.isEmpty() && !busy) item { EmptyState("Paketlenecek satır bulunamadı.") }
            }
        }
        BottomActionBar {
            OutlinedButton(
                onClick = { scope.launch { busy = true; reloadLines(); busy = false } },
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("🔄 Yenile") }
        }
    }
}

/** Bir sipariş için kutu seçim kartı — "karton üret" birincil, "kendi kutunu okut" ikincil. */
@Composable
private fun BoxForOrderCard(
    orderNo: String,
    customer: String,
    remaining: Int,
    busy: Boolean,
    showScan: Boolean,
    boxInput: String,
    onBoxInput: (String) -> Unit,
    onUseCarton: () -> Unit,
    onScanBox: (String) -> Unit,
    onToggleScan: (Boolean) -> Unit,
    onSkip: () -> Unit = {},
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White),
        border = BorderStroke(1.dp, Color(0xFFE0E0E0)),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("✅", fontSize = 18.sp)
                Spacer(Modifier.width(6.dp))
                Column(Modifier.weight(1f)) {
                    Text("🧾 $orderNo paketlendi", fontWeight = FontWeight.Bold, fontSize = 16.sp, color = Color(0xFF2E7D32))
                    if (customer.isNotBlank()) Text(customer, fontSize = 12.sp, color = Color.Gray)
                }
                if (remaining > 1) Text("+${remaining - 1} bekliyor", fontSize = 11.sp, color = Color(0xFFEF6C00))
            }
            Text(
                "Bu sipariş müşteriye hangi koliyle gidecek? Elindeki kolinin barkodunu " +
                    "okut ya da sistem karton üretsin. (Depoda kalan sepet DEĞİL — kargoya çıkan koli.)",
                fontSize = 12.sp, color = Color.Gray,
            )
            Spacer(Modifier.height(14.dp))
            Card(
                colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF3E0)),
                border = BorderStroke(1.dp, Color(0xFFEF6C00).copy(alpha = 0.4f)),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("📦", fontSize = 26.sp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text("Önerilen kargo kolisi", fontSize = 11.sp, color = Color(0xFFBF360C))
                        Text("Karton koli üretilecek", fontWeight = FontWeight.Bold, color = Color(0xFFBF360C))
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = onUseCarton,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth().height(50.dp),
            ) { Text("✓ Karton üret ve siparişi kapat", fontWeight = FontWeight.Bold) }
            Spacer(Modifier.height(10.dp))
            if (!showScan) {
                TextButton(onClick = { onToggleScan(true) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                    Text("📷 Elimdeki koliyi okut")
                }
            } else {
                Text("Müşteriye gidecek kolinin barkodunu okut:", fontSize = 12.sp, color = Color.Gray)
                Spacer(Modifier.height(6.dp))
                ScanField(
                    label = "📦 Kargo kolisi okut",
                    value = boxInput,
                    onValueChange = onBoxInput,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !busy,
                    onScanned = onScanBox,
                )
                Spacer(Modifier.height(6.dp))
                TextButton(onClick = { onToggleScan(false) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                    Text("‹ Vazgeç, karton üretimine dön", fontSize = 12.sp)
                }
            }
            // Kaçış yolu: sipariş BC'de kapanamıyorsa (silinmiş/kaydedilmiş)
            // operatör burada kilitlenmesin, sonraki siparişe geçebilsin.
            Spacer(Modifier.height(4.dp))
            TextButton(onClick = onSkip, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                Text("Bu siparişi atla (kapatılamıyor)", fontSize = 11.sp, color = Color.Gray)
            }
        }
    }
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

private fun packQty(value: Double): String =
    if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()
