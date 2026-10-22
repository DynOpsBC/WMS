package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.BarcodeKind
import com.dynops.bcwms.scanner.ScanBus
import com.dynops.bcwms.ui.StatusText
import com.dynops.bcwms.ui.WmsActionLabel
import com.dynops.bcwms.ui.WmsGlyph
import com.dynops.bcwms.ui.WmsRefreshLabel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

// Kitoko (22 Eki 2026): "LP okutunca içindeki şeyleri görelim". LP etiketinin QR'ı
// yalnız LP No taşır; LP (ya da SSCC) okutulunca bu kart açılır: durum, depo/göz,
// atandığı belge, satırlar (ürün, açıklama, lot, SKT, miktar), toplam ve
// "LP etiketi yazdır" / "Lot etiketi yazdır" / "İçeriği yenile".

/** Okutulan LP: LP No (QR / LP barkodu) ya da 18 haneli SSCC. */
internal sealed interface LpScanRef {
    val value: String

    data class ByNo(override val value: String) : LpScanRef
    data class BySscc(override val value: String) : LpScanRef
}

/** LP veya SSCC barkodu değilse null; diğer okutmalar (ürün, raf, belge) dokunulmadan kalır. */
internal fun lpScanRef(raw: String): LpScanRef? {
    val resolved = BarcodeIntentResolver.resolve(raw)
    if (resolved.kind != BarcodeKind.Lp) return null
    val value = resolved.value.trim()
    if (value.isEmpty()) return null
    return if (value.length == 18 && value.all(Char::isDigit)) LpScanRef.BySscc(value) else LpScanRef.ByNo(value.uppercase())
}

/** Ana menüde okutulan LP'yi LP ekranına taşır (WhsePickNavigation gibi tek kullanımlık). */
internal object LpCardNavigation {
    private var pending: LpScanRef? = null

    fun request(ref: LpScanRef) {
        pending = ref
    }

    fun consume(): LpScanRef? = pending.also { pending = null }
}

/** BC tarihi (yyyy-MM-dd) → gg.aa.yyyy; boş/0001-01-01 → "". */
internal fun lpCardDate(raw: String?): String {
    val value = raw?.trim().orEmpty()
    if (value.length < 10 || value.startsWith("0001")) return ""
    val (y, m, d) = Triple(value.substring(0, 4), value.substring(5, 7), value.substring(8, 10))
    return "$d.$m.$y"
}

/** Birim başına toplam: "48 KOLİ · 12 ADET"; satır yoksa "". */
internal fun lpCardTotals(lines: List<JSONObject>): String =
    lines.filter { it.optString("itemNo").isNotBlank() }
        .groupBy { it.optString("unitOfMeasure").trim() }
        .map { (uom, rows) -> "${fmtItemQty(rows.sumOf { it.optDouble("quantity", 0.0) })} $uom".trim() }
        .joinToString(" · ")

/** BC "DOPSWHS Assigned Doc Type" değer adı + no → "Depo kabul RE000123"; None/boş → "". */
internal fun lpAssignedDocLabel(type: String?, no: String?): String {
    val docNo = no?.trim().orEmpty().takeUnless { it == "null" }.orEmpty()
    if (docNo.isEmpty()) return ""
    val caption = when (type?.trim()) {
        "WhseReceipt" -> "Depo kabul"
        "WhsePick" -> "Toplama"
        "WhseShipment" -> "Sevkiyat"
        "WhsePutaway" -> "Yerleştirme"
        "WhseMovement" -> "Depo hareketi"
        "ProdConsumption" -> "Üretim tüketimi"
        "ProdOutput" -> "Üretim çıktısı"
        "Assembly" -> "Montaj"
        else -> ""
    }
    return if (caption.isEmpty()) docNo else "$caption $docNo"
}

/** Lot numaralı ürün satırı var mı (lot takipli ürün → lot etiketi önerilir). */
internal fun lpLinesHaveLots(lines: List<JSONObject>): Boolean =
    lines.any { it.optString("itemNo").isNotBlank() && it.optString("lotNo").trim().let { lot -> lot.isNotEmpty() && lot != "null" } }

/** Bir LP'de basılacak lot etiketi sayısı (ürün + varyant + lot başına bir etiket). */
internal fun lpLotLabelCount(lines: List<JSONObject>): Int =
    lines.filter { it.optString("itemNo").isNotBlank() && it.optString("lotNo").trim().let { lot -> lot.isNotEmpty() && lot != "null" } }
        .map { Triple(it.optString("itemNo").trim(), it.optString("variantCode").trim(), it.optString("lotNo").trim()) }
        .distinct().size

/**
 * Lot etiketi düğmesi: satırlarda lot var ve BC lot etiketi tasarımlarını tanıyor
 * (labelLayouts'ta Lot türü). Eski BC'de (404 / Lot türü yok) düğme gizli kalır.
 */
internal fun lotLabelOffered(lines: List<JSONObject>, lotLayouts: LabelLayoutLoad): Boolean =
    lpLinesHaveLots(lines) && lotLayouts is LabelLayoutLoad.Ready

internal data class LpCardData(val header: JSONObject, val lines: List<JSONObject>, val linesComplete: Boolean)

internal sealed interface LpCardLoad {
    data class Ready(val data: LpCardData) : LpCardLoad
    data class Failed(val status: String) : LpCardLoad
}

/** LP başlığı + tüm satırları (LP ekranı, LP kartı ve sorgu aynı okumayı kullanır). */
internal suspend fun fetchLpHeaderAndLines(context: Context, lpNo: String): LpCardLoad {
    val safeLpNo = lpNo.replace("'", "''")
    val h = BcApi.get(context, "licensePlates('$safeLpNo')")
    val header = if (h.ok) runCatching { JSONObject(h.body) }.getOrNull() else null
    if (header == null) {
        return LpCardLoad.Failed(
            if (h.httpCode == 404) "BOŞ: $lpNo numaralı LP bulunamadı."
            else "HATA: LP bilgisi alınamadı. Yenileyip tekrar deneyin.",
        )
    }
    val page = BcApi.getAllPages(context, "licensePlateLines?\$filter=lpNo eq '$safeLpNo'&\$orderby=lineNo")
    return LpCardLoad.Ready(LpCardData(header, page.rows, page.complete))
}

/** LP No ya da SSCC ile LP'yi bulur. */
internal suspend fun loadLpCard(context: Context, ref: LpScanRef): LpCardLoad {
    val lpNo = when (ref) {
        is LpScanRef.ByNo -> ref.value
        is LpScanRef.BySscc -> {
            val r = BcApi.get(context, "licensePlates?\$filter=sscc eq '${ref.value}'&\$top=1&\$select=no")
            if (!r.ok) return LpCardLoad.Failed("HATA: SSCC ${ref.value} sorgulanamadı (HTTP ${r.httpCode}).")
            BcApi.parseValueArray(r.body).firstOrNull()?.optString("no")?.takeIf { it.isNotBlank() }
                ?: return LpCardLoad.Failed("BOŞ: SSCC ${ref.value} hiçbir LP'de yok.")
        }
    }
    return fetchLpHeaderAndLines(context, lpNo)
}

/**
 * LP etiketi (printLabel / printLabelWithLayout) ya da lot etiketleri
 * (printLotLabels) adet kadar; 10'luk işlere bölünür, ilk hatada durur.
 */
internal suspend fun printLpCardLabels(context: Context, lpNo: String, lot: Boolean, total: Int, layoutCode: String): String {
    val choice = resolveInquiryPrinter(context).getOrElse { return "HATA: ${it.message}" }
    val what = if (lot) "lot etiketi" else "LP etiketi"
    var sent = 0
    for (copies in labelCopyBatches(total)) {
        val action = if (lot) LOT_LABELS_ACTION else labelPrintAction(layoutCode)
        val payload = if (lot) JSONObject().put("printerId", choice.printerCode).put("copies", copies).put("layoutCode", layoutCode).toString()
            else labelPrintPayload(choice.printerCode, copies, layoutCode)
        val r = try {
            BcApi.boundActionLongRunning(context, "licensePlates", lpNo, action, payload)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            return "HATA: $lpNo $what gönderilemedi. ${error.message.orEmpty()}" +
                if (sent > 0) " · $total adetin $sent adedi kuyruğa alınmıştı." else ""
        }
        if (!r.ok) {
            val old = lot && (r.httpCode == 404 || r.httpCode == 405 || r.httpCode == 400 && BcApi.errorMessage(r.body).contains("printLotLabels", ignoreCase = true))
            return if (old) "HATA: Lot etiketi için BC uzantısını 1.14.3.17'ye güncelleyin."
            else "🔴 $what: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})" +
                if (sent > 0) " · $total adetin $sent adedi kuyruğa alınmıştı." else ""
        }
        sent += copies
    }
    return "🟢 $lpNo $what × $total ${choice.printerCode} kuyruğuna alındı." + labelLayoutNote(layoutCode) +
        if (choice.warning.isBlank()) "" else " ${choice.warning}"
}

internal const val LOT_LABELS_ACTION = "printLotLabels"

/**
 * Ekran açıkken donanım tarayıcıdan gelen LP/SSCC okutmalarını yakalar; diğer
 * barkodlar yok sayılır. Yalnız LP okutmasının başka anlamı olmayan ekranlarda
 * (ana menü, LP listesi, Etiket Çıkar → LP) kullanılır.
 */
@Composable
internal fun LpScanListener(enabled: Boolean, onLp: (LpScanRef) -> Unit) {
    val callback by rememberUpdatedState(onLp)
    val windowFocused = LocalWindowInfo.current.isWindowFocused
    LaunchedEffect(enabled, windowFocused) {
        if (!enabled || !windowFocused) return@LaunchedEffect
        ScanBus.events.collect { event -> lpScanRef(event.raw)?.let { callback(it) } }
    }
}

/**
 * LP kartı: okutulan LP'nin içeriği ve etiket aksiyonları. [onOpenDocument]
 * verilirse "LP İşlemleri" ile düzenleme ekranı açılır.
 */
@Composable
internal fun LpContentCard(
    ref: LpScanRef,
    onClose: (() -> Unit)?,
    closeLabel: String = "‹ Geri",
    onOpenDocument: ((String) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var data by remember(ref) { mutableStateOf<LpCardData?>(null) }
    var status by remember(ref) { mutableStateOf("") }
    var loading by remember(ref) { mutableStateOf(false) }
    var printing by remember { mutableStateOf(false) }
    var lpCopies by remember(ref) { mutableStateOf("1") }
    var lotCopies by remember(ref) { mutableStateOf("1") }
    val lpLayout = rememberLabelLayoutChoice(LabelLayoutKind.LP)
    val lotLayout = rememberLabelLayoutChoice(LabelLayoutKind.Lot)

    fun reload() {
        scope.launch {
            loading = true
            status = "LP içeriği yükleniyor..."
            when (val result = loadLpCard(context, ref)) {
                is LpCardLoad.Ready -> {
                    data = result.data
                    status = if (result.data.linesComplete) "" else "HATA: LP satırlarının tamamı alınamadı. İçeriği yenileyin."
                }
                is LpCardLoad.Failed -> {
                    data = null
                    status = result.status
                }
            }
            loading = false
        }
    }
    LaunchedEffect(ref) { reload() }
    LaunchedEffect(Unit) { lotLayout.ensureLoaded(context) }

    fun print(lot: Boolean) {
        val lpNo = data?.header?.optString("no")?.takeIf { it.isNotBlank() } ?: return
        if (printing) return
        val total = parseLabelCopies(if (lot) lotCopies else lpCopies)
            ?: run { status = "HATA: Etiket adedi 1 ile $LABEL_COPIES_MAX arasında olmalı."; return }
        printing = true
        status = if (lot) "🖨 Lot etiketleri gönderiliyor..." else "🖨 LP etiketi gönderiliyor..."
        scope.launch {
            try {
                val layout = if (lot) lotLayout.awaitLayoutCode(context) else lpLayout.awaitLayoutCode(context)
                status = printLpCardLabels(context, lpNo, lot, total, layout)
            } finally {
                printing = false
            }
        }
    }

    Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (onClose != null) TextButton(onClick = onClose, enabled = !printing) { Text(closeLabel) }
        val d = data
        if (d == null) {
            Text("LP ${ref.value}", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            StatusText(status)
            if (!loading) OutlinedButton(onClick = { reload() }, modifier = Modifier.fillMaxWidth()) { WmsRefreshLabel(false) }
            return@Column
        }
        val h = d.header
        val lpNo = h.optString("no")
        val itemLines = d.lines.filter { it.optString("itemNo").isNotBlank() }
        val childLps = d.lines.mapNotNull { it.optString("childLpNo").trim().takeIf { c -> c.isNotBlank() && c != "null" } }
        Card(
            Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.07f)),
        ) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(lpNo, fontSize = 24.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    LpStatusBadge(h.optString("status"))
                }
                val place = listOf(h.optString("locationCode"), h.optString("binCode").ifBlank { "göz atanmadı" })
                    .filter { it.isNotBlank() }.joinToString(" / ")
                LpCardInfo("Depo / Göz", place)
                LpCardInfo("Atandığı belge", lpAssignedDocLabel(h.optString("assignedDocumentType"), h.optString("assignedDocumentNo")))
                LpCardInfo("Bekleyen mal kabul", h.optString("pendingReceiptNo").takeUnless { it == "null" }.orEmpty())
                LpCardInfo("SSCC", h.optString("sscc"))
                LpCardInfo("Toplam", lpCardTotals(itemLines).ifBlank { "Boş LP" })
                if (childLps.isNotEmpty()) LpCardInfo("Alt LP", childLps.joinToString(", "))
            }
        }
        StatusText(status)
        Text("İçerik (${itemLines.size} satır)", fontWeight = FontWeight.Bold, fontSize = 14.sp)
        if (itemLines.isEmpty()) Text("Bu LP'de ürün yok.", style = MaterialTheme.typography.bodyMedium)
        itemLines.forEach { ln -> LpCardLine(ln) }

        HorizontalDivider(Modifier.padding(vertical = 4.dp))
        Text("LP etiketi (QR = LP No)", fontWeight = FontWeight.Bold, fontSize = 14.sp)
        LabelLayoutSelector(lpLayout, enabled = !printing)
        LabelCopiesField(lpCopies, { lpCopies = it }, enabled = !printing)
        Button(
            onClick = { print(lot = false) },
            enabled = !printing && !loading,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = RoundedCornerShape(14.dp),
        ) { WmsActionLabel(WmsGlyph.PRINTER, "LP Etiketi Yazdır") }

        if (lotLabelOffered(itemLines, lotLayout.load)) {
            Spacer(Modifier.height(4.dp))
            Text("Lot etiketi (${lpLotLabelCount(itemLines)} lot · QR = ürün no)", fontWeight = FontWeight.Bold, fontSize = 14.sp)
            LabelLayoutSelector(lotLayout, enabled = !printing)
            LabelCopiesField(lotCopies, { lotCopies = it }, enabled = !printing, label = "Lot başına adet")
            OutlinedButton(
                onClick = { print(lot = true) },
                enabled = !printing && !loading,
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(14.dp),
            ) { WmsActionLabel(WmsGlyph.LABEL, "Lot Etiketi Bas") }
        }

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { reload() }, enabled = !loading && !printing, modifier = Modifier.weight(1f).height(48.dp)) {
                if (loading) WmsRefreshLabel(true) else WmsActionLabel(WmsGlyph.REFRESH, "İçeriği Yenile")
            }
            if (onOpenDocument != null) OutlinedButton(
                onClick = { onOpenDocument(lpNo) },
                enabled = !printing,
                modifier = Modifier.weight(1f).height(48.dp),
            ) { WmsActionLabel(WmsGlyph.LICENSE_PLATE, "LP İşlemleri") }
        }
    }
}

@Composable
private fun LpCardInfo(label: String, value: String) {
    if (value.isBlank()) return
    Row {
        Text("$label: ", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun LpCardLine(ln: JSONObject) {
    Card(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(ln.optString("itemNo"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                ln.optString("itemDescription").takeIf { it.isNotBlank() && it != "null" }?.let {
                    Text(it, style = MaterialTheme.typography.bodyMedium)
                }
                val extra = listOfNotNull(
                    ln.optString("lotNo").takeIf { it.isNotBlank() && it != "null" }?.let { "Lot $it" },
                    lpCardDate(ln.optString("expirationDate")).takeIf { it.isNotBlank() }?.let { "SKT $it" },
                    ln.optString("variantCode").takeIf { it.isNotBlank() && it != "null" }?.let { "Varyant $it" },
                    ln.optString("serialNo").takeIf { it.isNotBlank() && it != "null" }?.let { "Seri $it" },
                    ln.optString("packageNo").takeIf { it.isNotBlank() && it != "null" }?.let { "Paket $it" },
                ).joinToString(" · ")
                if (extra.isNotBlank()) Text(extra, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.width(10.dp))
            Column(horizontalAlignment = Alignment.End) {
                Text(fmtItemQty(ln.optDouble("quantity", 0.0)), style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                Text(ln.optString("unitOfMeasure"), style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
