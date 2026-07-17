package com.dynops.bcwms.feature

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.ScanBus
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Paketleme İstasyonu — ELOG saha ziyareti (07.07.2026), 3 modlu akış:
 *  - SOLO  (multi pick sepeti): bir sepet = bir sipariş. Sepet → kutu →
 *    ürünler → tüm satırlar bitince fiş.
 *  - BULK  : aynı ürün birden çok siparişe bölünmüş (2+2+2). Sepet bir kez
 *    okutulur; her sipariş payı için KUTU → ürünler → payın fişi basılır,
 *    sıradaki pay yeni kutu ister.
 *  - BATCH (mono-SKU): tek ürünlük siparişler. Sepet bir kez okutulur;
 *    ÜRÜN → KUTU döngüsü — kutu okuması siparişi kapatır ve fişini bastırır.
 * Kutu SİPARİŞ başınadır; beklenmeyen ürün okutulursa sunucu hata döner.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PackingModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var mode by remember { mutableStateOf("solo") }
    var sessionId by remember { mutableStateOf<Int?>(null) }
    var session by remember { mutableStateOf<JSONObject?>(null) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var toteInput by remember { mutableStateOf("") }
    var boxInput by remember { mutableStateOf("") }
    var itemInput by remember { mutableStateOf("") }
    // Worksheet başlığındaki "Current Item" / "Last Scan" alanları (ELOG ekranı).
    var currentItem by remember { mutableStateOf("") }
    var lastScanText by remember { mutableStateOf("") }

    suspend fun reloadNow() {
        val id = sessionId ?: return
        val s = BcApi.get(context, "packSessions($id)")
        if (s.ok) session = JSONObject(s.body)
        val l = BcApi.get(context, "packSessionLines?\$filter=sessionEntryNo eq $id&\$top=200")
        if (l.ok) lines = BcApi.parseValueArray(l.body)
    }

    fun reload() { scope.launch { reloadNow() } }

    fun startSession(tote: String) {
        if (tote.isBlank() || busy) return
        scope.launch {
            busy = true; status = "Oturum başlatılıyor..."
            val body = JSONObject().apply { put("toteLpNo", tote.trim()); put("mode", mode) }.toString()
            val r = BcApi.boundAction(context, "packOps", "", "startSession", body)
            if (r.ok) {
                sessionId = BcApi.scalarValue(r.body).toIntOrNull()
                toteInput = ""
                lastScanText = tote.trim()
                status = "PASS: Sepet ${tote.trim()} açıldı (${modeLabel(mode)})"
                reloadNow()
            } else status = "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            busy = false
        }
    }

    fun setBoxForOrder(orderNo: String, box: String, newCarton: Boolean) {
        val id = sessionId ?: return
        if (busy || (!newCarton && box.isBlank())) return
        scope.launch {
            busy = true; status = if (newCarton) "Karton LP üretiliyor..." else "Kutu bağlanıyor..."
            val body = JSONObject().apply {
                put("sessionId", id)
                put("orderNo", orderNo)
                put("boxLpNo", if (newCarton) "" else box.trim())
                put("lpTemplateCode", "")
            }.toString()
            val r = BcApi.boundAction(context, "packOps", "", "setBoxForOrder", body)
            if (r.ok) {
                boxInput = ""
                lastScanText = BcApi.scalarValue(r.body).ifBlank { box.trim() }
                reloadNow()
                // Batch akışı: kutu okuması siparişi kapatmış olabilir.
                val completedNow = lines.filter { it.optString("sourceOrderNo") == orderNo }
                    .any { it.optBoolean("orderCompleted") }
                status = if (completedNow) "🧾 Sipariş $orderNo tamamlandı, fiş basıldı"
                    else "PASS: Kutu ${BcApi.scalarValue(r.body)} → sipariş $orderNo"
            } else status = "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            busy = false
        }
    }

    fun scanItem(itemNo: String, qty: Double = 1.0) {
        val id = sessionId ?: return
        if (itemNo.isBlank() || busy) return
        scope.launch {
            busy = true; status = "Ürün işleniyor..."
            val body = JSONObject().apply {
                put("sessionId", id); put("itemNo", itemNo.trim()); put("qty", qty)
            }.toString()
            val r = BcApi.boundAction(context, "packOps", "", "scanItem", body)
            if (r.ok) {
                itemInput = ""
                currentItem = itemNo.trim()
                lastScanText = itemNo.trim()
                val completed = BcApi.scalarValue(r.body)
                reloadNow()
                status = if (completed.isNotBlank()) "🧾 Sipariş tamamlandı, fiş basıldı: $completed"
                    else "PASS: ${itemNo.trim()} paketlendi"
            } else status = "❌ ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            busy = false
        }
    }

    fun resetForNextTote() {
        sessionId = null; session = null; lines = emptyList(); status = ""
        toteInput = ""; boxInput = ""; itemInput = ""
        currentItem = ""; lastScanText = ""
    }

    val sessionMode = session?.optString("mode")?.lowercase()?.takeIf { it.isNotBlank() && it != "null" } ?: mode
    val done = session?.optString("status") == "Completed"
    val boxNeeded = if (sessionId != null && !done) boxNeededOrder(lines, sessionMode) else null

    // Donanım tarayıcı: adım hangi okumayı bekliyorsa oraya yönlenir
    // (sepet → [kutu|ürün]); kutu bekleyen sipariş varsa okuma kutudur.
    LaunchedEffect(Unit) {
        ScanBus.events.collect { ev ->
            if (busy) return@collect
            val resolved = BarcodeIntentResolver.resolve(ev.raw)
            val needed = if (sessionId != null && session?.optString("status") != "Completed")
                boxNeededOrder(lines, session?.optString("mode")?.lowercase()?.takeIf { it.isNotBlank() && it != "null" } ?: mode) else null
            when {
                sessionId == null -> startSession(resolved.value.trim())
                session?.optString("status") == "Completed" -> Unit
                needed != null -> setBoxForOrder(needed, resolved.value.trim(), newCarton = false)
                else -> scanItem((resolved.itemNo ?: resolved.value).trim())
            }
        }
    }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Text("📦 Paketleme İstasyonu", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))

        when {
            // ---------- Adım 1: Mod seç + sepet okut ----------
            sessionId == null -> {
                Card(
                    Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(18.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.4f)),
                    elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                ) {
                    Column(Modifier.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                Modifier.size(26.dp).clip(RoundedCornerShape(50)).background(PackModeAccent),
                                contentAlignment = Alignment.Center,
                            ) { Text("1", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp) }
                            Spacer(Modifier.width(10.dp))
                            Text("Mod seçin ve sepeti okutun", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                        }
                        Spacer(Modifier.height(14.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            PackModeCard("🧍", "Solo", mode == "solo", Modifier.weight(1f)) { mode = "solo" }
                            PackModeCard("📚", "Bulk", mode == "bulk", Modifier.weight(1f)) { mode = "bulk" }
                            PackModeCard("1️⃣", "Batch", mode == "batch", Modifier.weight(1f)) { mode = "batch" }
                        }
                        Spacer(Modifier.height(10.dp))
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                                .background(PackModeAccent.copy(alpha = 0.07f)).padding(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                when (mode) { "bulk" -> "📚"; "batch" -> "1️⃣"; else -> "🧍" },
                                fontSize = 18.sp,
                            )
                            Spacer(Modifier.width(10.dp))
                            Text(
                                when (mode) {
                                    "bulk" -> "Aynı ürün birden çok siparişe bölünmüş (2+2+2). Her sipariş payı için kutu okutulur; pay dolunca fişi basılır."
                                    "batch" -> "Tek ürünlük siparişler (mono-SKU). Ürün okut → kutu okut → fatura; her okuma bir siparişi kapatır."
                                    else -> "Bir sepet = bir sipariş. Kutu okut → ürünleri okut → tüm satırlar bitince fiş basılır."
                                },
                                fontSize = 12.sp, lineHeight = 16.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Spacer(Modifier.height(14.dp))
                        ScanField("Sepet / Tote LP", toteInput, { toteInput = it },
                            modifier = Modifier.fillMaxWidth(),
                            onScanned = { startSession(BarcodeIntentResolver.resolve(it).value) })
                        Spacer(Modifier.height(12.dp))
                        Button(
                            enabled = toteInput.isNotBlank() && !busy,
                            onClick = { startSession(toteInput) },
                            shape = RoundedCornerShape(50),
                            colors = ButtonDefaults.buttonColors(containerColor = PackModeAccent),
                            modifier = Modifier.fillMaxWidth().height(52.dp),
                        ) { Text("🧺 Sepeti Aç", fontWeight = FontWeight.Bold, fontSize = 15.sp) }
                    }
                }
            }
            // ---------- Tamamlandı ----------
            done -> {
                Card(
                    Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = Color(0xFFE8F5E9)),
                ) {
                    Column(Modifier.padding(16.dp)) {
                        Text("✅ Sepet tamamlandı", fontWeight = FontWeight.Bold, fontSize = 16.sp, color = Color(0xFF2E7D32))
                        Text(
                            "Sepet: ${session?.optString("toteLpNo")} · ${modeLabel(sessionMode)} · " +
                                "${session?.optInt("ordersCompleted")}/${session?.optInt("ordersTotal")} sipariş sevk + faturalandı.",
                            fontSize = 12.sp, color = Color(0xFF2E7D32),
                        )
                        Spacer(Modifier.height(10.dp))
                        Button(
                            onClick = { resetForNextTote() },
                            shape = RoundedCornerShape(50),
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32)),
                            modifier = Modifier.fillMaxWidth().height(52.dp),
                        ) { Text("🧺 Yeni Sepet", fontWeight = FontWeight.Bold, fontSize = 15.sp) }
                    }
                }
                Spacer(Modifier.height(8.dp))
                PackLineList(lines, Modifier.weight(1f))
            }
            // ---------- Aktif oturum: kutu / ürün ----------
            else -> {
                PackWorksheetCard(
                    session = session,
                    lines = lines,
                    mode = sessionMode,
                    currentItem = currentItem,
                    lastScan = lastScanText,
                )
                Spacer(Modifier.height(8.dp))
                if (boxNeeded != null) {
                    Card(
                        Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(18.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                        border = BorderStroke(1.dp, PackModeAccent.copy(alpha = 0.45f)),
                        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                    ) {
                        Column(Modifier.padding(16.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(
                                    Modifier.size(38.dp).clip(RoundedCornerShape(12.dp)).background(PackModeAccent.copy(alpha = 0.12f)),
                                    contentAlignment = Alignment.Center,
                                ) { Text("📦", fontSize = 18.sp) }
                                Spacer(Modifier.width(10.dp))
                                Column {
                                    Text("Sipariş $boxNeeded için kutu okutun", fontWeight = FontWeight.Bold, fontSize = 15.sp)
                                    Text(
                                        if (sessionMode == "batch") "Kutu okutulunca sipariş kapanır ve fişi basılır."
                                        else "Kutu (karton LP) barkodu okutun ya da yeni karton üretin.",
                                        fontSize = 11.sp, color = Color.Gray,
                                    )
                                }
                            }
                            Spacer(Modifier.height(12.dp))
                            ScanField("Kutu / Karton LP", boxInput, { boxInput = it },
                                modifier = Modifier.fillMaxWidth(),
                                onScanned = { setBoxForOrder(boxNeeded, BarcodeIntentResolver.resolve(it).value, newCarton = false) })
                            Spacer(Modifier.height(12.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                OutlinedButton(
                                    enabled = !busy,
                                    onClick = { setBoxForOrder(boxNeeded, "", newCarton = true) },
                                    shape = RoundedCornerShape(50),
                                    modifier = Modifier.weight(1f).height(48.dp),
                                ) { Text("📦 Yeni Karton") }
                                Button(
                                    enabled = boxInput.isNotBlank() && !busy,
                                    onClick = { setBoxForOrder(boxNeeded, boxInput, newCarton = false) },
                                    shape = RoundedCornerShape(50),
                                    colors = ButtonDefaults.buttonColors(containerColor = PackModeAccent),
                                    modifier = Modifier.weight(1f).height(48.dp),
                                ) { Text("Kutuyu Bağla", fontWeight = FontWeight.Bold) }
                            }
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                } else {
                    ScanField("Ürün okut", itemInput, { itemInput = it },
                        modifier = Modifier.fillMaxWidth(),
                        onScanned = { raw ->
                            val res = BarcodeIntentResolver.resolve(raw)
                            scanItem((res.itemNo ?: res.value).trim())
                        })
                    Spacer(Modifier.height(8.dp))
                }
                PackLineList(lines, Modifier.weight(1f))
                BottomActionBar {
                    OutlinedButton(
                        enabled = !busy,
                        onClick = {
                            val id = sessionId
                            scope.launch {
                                busy = true
                                val r = BcApi.boundAction(context, "packOps", "", "cancelSession",
                                    JSONObject().apply { put("sessionId", id) }.toString())
                                busy = false
                                if (r.ok) { resetForNextTote(); status = "Oturum iptal edildi" }
                                else status = "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                            }
                        },
                        modifier = Modifier.weight(1f),
                    ) { Text("✕ İptal") }
                    OutlinedButton(onClick = { reload() }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("🔄 Yenile") }
                }
            }
        }
    }
}

/**
 * Şu an kutu okutulması gereken sipariş (yoksa null) — AL BoxNeededOrder'ın
 * terminal aynası:
 *  1) tam paketlenmiş ama kutusuz, kapanmamış sipariş (batch: ürün → kutu),
 *  2) solo/bulk'ta sıradaki siparişin kutusu yoksa o (kutu → ürünler).
 */
private fun boxNeededOrder(lines: List<JSONObject>, mode: String): String? {
    val open = lines.filter { !it.optBoolean("orderCompleted") }
    if (open.isEmpty()) return null
    val byOrder = open.groupBy { it.optString("sourceOrderNo") }
    for ((order, ls) in byOrder) {
        val fullyPacked = ls.all { it.optDouble("qtyPacked", 0.0) >= it.optDouble("qtyExpected", 0.0) }
        if (fullyPacked && !hasBox(ls)) return order
    }
    if (mode != "batch") {
        val currentOrder = open.first().optString("sourceOrderNo")
        if (!hasBox(byOrder[currentOrder].orEmpty())) return currentOrder
    }
    return null
}

private fun hasBox(orderLines: List<JSONObject>): Boolean =
    orderLines.any { ln -> ln.optString("boxLpNo").let { it.isNotBlank() && it != "null" } }

private fun modeLabel(mode: String): String = when (mode) {
    "bulk" -> "Bulk"
    "batch" -> "Batch (mono-SKU)"
    else -> "Solo"
}

private val PackModeAccent = Color(0xFF6C5CE7) // Ana menüdeki "Giden" kategorisiyle aynı vurgu rengi.

/**
 * ELOG worksheet başlığının terminal karşılığı: sepet + mod rozeti, ilerleme
 * çubuğu, Kalan Miktar / Kalan Satır / Sipariş sayaçları ve Güncel Ürün /
 * Son Okutma / Kutu bilgi satırları.
 */
@Composable
private fun PackWorksheetCard(
    session: JSONObject?,
    lines: List<JSONObject>,
    mode: String,
    currentItem: String,
    lastScan: String,
) {
    val expectedTotal = lines.sumOf { it.optDouble("qtyExpected", 0.0) }
    val packedTotal = lines.sumOf { it.optDouble("qtyPacked", 0.0) }
    val progress = if (expectedTotal > 0) (packedTotal / expectedTotal).toFloat().coerceIn(0f, 1f) else 0f
    val unpackedQty = (expectedTotal - packedTotal).coerceAtLeast(0.0)
    val unpackedLines = lines.count { it.optDouble("qtyPacked", 0.0) < it.optDouble("qtyExpected", 0.0) }

    Card(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, PackModeAccent.copy(alpha = 0.35f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Column(Modifier.padding(14.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "🧺 ${session?.optString("toteLpNo") ?: ""}",
                    fontWeight = FontWeight.Bold, fontSize = 16.sp,
                )
                Box(
                    Modifier.clip(RoundedCornerShape(50)).background(PackModeAccent.copy(alpha = 0.14f))
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                ) {
                    Text(modeLabel(mode), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = PackModeAccent)
                }
            }
            Text(
                "Pick: ${firstValue(session ?: JSONObject(), "pickNo").ifBlank { "—" }} · " +
                    "Lokasyon: ${firstValue(session ?: JSONObject(), "locationCode").ifBlank { "—" }}",
                fontSize = 11.sp, color = Color.Gray,
            )
            Spacer(Modifier.height(10.dp))
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)),
                color = PackModeAccent,
            )
            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                WorksheetStat("Kalan Miktar", fmtPack(unpackedQty), Modifier.weight(1f))
                WorksheetStat("Kalan Satır", "$unpackedLines", Modifier.weight(1f))
                WorksheetStat(
                    "Sipariş",
                    "${session?.optInt("ordersCompleted") ?: 0}/${session?.optInt("ordersTotal") ?: 0}",
                    Modifier.weight(1f),
                )
            }
            Spacer(Modifier.height(10.dp))
            WorksheetInfoRow("Güncel Ürün", currentItem.ifBlank { "—" })
            WorksheetInfoRow("Son Okutma", lastScan.ifBlank { "—" })
            WorksheetInfoRow("Kutu", (session?.optString("boxLpNo") ?: "").let { if (it.isBlank() || it == "null") "—" else it })
        }
    }
}

@Composable
private fun WorksheetStat(label: String, value: String, modifier: Modifier = Modifier) {
    Column(
        modifier.clip(RoundedCornerShape(12.dp)).background(PackModeAccent.copy(alpha = 0.07f))
            .padding(vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(value, fontWeight = FontWeight.Bold, fontSize = 17.sp, color = PackModeAccent)
        Spacer(Modifier.height(2.dp))
        Text(label, fontSize = 10.sp, color = Color.Gray)
    }
}

@Composable
private fun WorksheetInfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, fontSize = 12.sp, color = Color.Gray)
        Text(value, fontSize = 12.sp, fontWeight = FontWeight.Medium)
    }
}

/** Segment tarzı mod kutusu: seçili olan düz mor dolgu + beyaz etiket. */
@Composable
private fun PackModeCard(emoji: String, label: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (selected) PackModeAccent else MaterialTheme.colorScheme.surface,
        ),
        border = if (selected) null else BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.4f)),
        elevation = CardDefaults.cardElevation(defaultElevation = if (selected) 3.dp else 0.dp),
        modifier = modifier.height(76.dp),
    ) {
        Column(
            Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(emoji, fontSize = 22.sp)
            Spacer(Modifier.height(4.dp))
            Text(
                label,
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                fontSize = 13.sp,
                color = if (selected) Color.White else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

/** Bekleyenler kırmızı, tamamlananlar yeşil — ELOG ekranındaki gibi. */
@Composable
private fun PackLineList(lines: List<JSONObject>, modifier: Modifier = Modifier) {
    LazyColumn(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        items(lines) { ln ->
            val expected = ln.optDouble("qtyExpected", 0.0)
            val packed = ln.optDouble("qtyPacked", 0.0)
            val lineDone = packed >= expected && expected > 0
            val colors = when {
                lineDone -> CardDefaults.cardColors(containerColor = Color(0xFFE8F5E9))
                else -> CardDefaults.cardColors(containerColor = Color(0xFFFFEBEE))
            }
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp), colors = colors) {
                Column(Modifier.padding(12.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(
                            "${if (lineDone) "✓ " else ""}${ln.optString("itemNo")} — ${firstValue(ln, "description")}",
                            fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                            color = if (lineDone) Color(0xFF2E7D32) else Color(0xFFB71C1C),
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            "${fmtPack(packed)}/${fmtPack(expected)}",
                            fontWeight = FontWeight.Bold, fontSize = 14.sp,
                            color = if (lineDone) Color(0xFF2E7D32) else Color(0xFFB71C1C),
                        )
                    }
                    Text(
                        buildList {
                            add("Sipariş: ${ln.optString("sourceOrderNo")}")
                            firstValue(ln, "boxLpNo").takeIf { it.isNotBlank() }?.let { add("Kutu: $it") }
                            if (ln.optBoolean("orderCompleted")) add("🧾 faturalandı")
                            firstValue(ln, "gtin").takeIf { it.isNotBlank() }?.let { add("GTIN $it") }
                        }.joinToString(" · "),
                        fontSize = 11.sp, color = Color.Gray,
                    )
                }
            }
        }
        if (lines.isEmpty()) item { EmptyState("Satır yok.") }
    }
}

private fun fmtPack(v: Double): String = if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()
