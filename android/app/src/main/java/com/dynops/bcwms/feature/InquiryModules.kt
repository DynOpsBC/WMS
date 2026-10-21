package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

internal data class QueriedLpSummary(
    val lpNo: String,
    val quantity: Double,
    val lotNos: List<String>,
)

internal fun queriedLpSummary(lpNo: String, lines: List<JSONObject>): QueriedLpSummary? {
    val normalizedLpNo = lpNo.trim()
    if (normalizedLpNo.isBlank()) return null
    val matchingLines = lines.filter {
        it.optString("lpNo").trim().equals(normalizedLpNo, ignoreCase = true)
    }
    if (matchingLines.isEmpty()) return null
    return QueriedLpSummary(
        lpNo = matchingLines.first().optString("lpNo").trim().ifBlank { normalizedLpNo },
        quantity = matchingLines.sumOf { it.optDouble("quantity", 0.0) },
        lotNos = matchingLines.mapNotNull { line ->
            line.optString("lotNo").trim().takeIf { it.isNotBlank() }
        }.distinctBy { it.lowercase() },
    )
}

/** BADE (16 Eyl 2026): LP ile sorguda paletin bulunduğu lokasyon/raf ve alan (zone) kodu. */
internal data class LpPlacement(val locationCode: String, val binCode: String, val zoneCode: String)

internal fun lpPlacementLabel(p: LpPlacement?): String {
    if (p == null) return ""
    val place = listOf(p.locationCode.trim(), p.binCode.trim()).filter { it.isNotBlank() }.joinToString("/")
    return listOfNotNull(
        place.takeIf { it.isNotBlank() }?.let { "Raf: $it" },
        p.zoneCode.trim().takeIf { it.isNotBlank() }?.let { "Alan: $it" },
    ).joinToString(" · ")
}

internal fun odataOrFilter(values: List<String>, build: (String) -> String): String =
    values.joinToString(" or ") { build(it.replace("'", "''")) }

/** LP başlıklarından lokasyon/raf, raf kaydından alan kodu; eksik veri boş kalır, ekran kırılmaz. */
internal suspend fun loadLpPlacements(context: android.content.Context, lpNos: List<String>): Map<String, LpPlacement> {
    val keys = lpNos.map { it.trim() }.filter { it.isNotBlank() }.distinct().take(25)
    if (keys.isEmpty()) return emptyMap()
    val heads = BcApi.getAllPages(context, "licensePlates?\$filter=${odataOrFilter(keys) { "no eq '$it'" }}&\$select=no,locationCode,binCode&\$top=50")
    if (!heads.complete) return emptyMap()
    val placements = heads.rows.associate { h ->
        h.optString("no").trim() to LpPlacement(h.optString("locationCode").trim(), h.optString("binCode").trim(), "")
    }
    val binKeys = placements.values.filter { it.binCode.isNotBlank() }.map { it.locationCode to it.binCode }.distinct()
    if (binKeys.isEmpty()) return placements
    val binFilter = binKeys.joinToString(" or ") { (loc, bin) ->
        "(locationCode eq '${loc.replace("'", "''")}' and code eq '${bin.replace("'", "''")}')"
    }
    val bins = BcApi.getAllPages(context, "bins?\$filter=$binFilter&\$select=locationCode,code,zoneCode&\$top=50")
    if (!bins.complete) return placements
    val zones = bins.rows.associate { (it.optString("locationCode").trim() to it.optString("code").trim()) to it.optString("zoneCode").trim() }
    return placements.mapValues { (_, p) -> p.copy(zoneCode = zones[p.locationCode to p.binCode].orEmpty()) }
}

/** Kitoko (19 Eki 2026): EMU etiket ekranı — art arda okutulan ürünler listede kalır. */
internal data class InquiryItemEntry(
    val queryKey: String,
    val item: JSONObject?,
    val lpLines: List<JSONObject>,
    val ledger: List<JSONObject>,
    val queriedLpNo: String,
    val uom: String,
    val labelCopies: String = "1",
)

internal fun addInquiryEntry(
    entries: List<InquiryItemEntry>,
    entry: InquiryItemEntry,
): List<InquiryItemEntry> {
    if (entry.item == null && entry.queriedLpNo.isBlank()) return entries
    val previous = entries.firstOrNull { it.queryKey.equals(entry.queryKey, ignoreCase = true) }
    return listOf(entry.copy(labelCopies = previous?.labelCopies ?: "1")) +
        entries.filterNot { it.queryKey.equals(entry.queryKey, ignoreCase = true) }
}

/** Ürün no veya açıklamasında geçen ürünler; BC iki alan arasında OR desteklemediği için iki istek. */
internal fun itemLookupPaths(value: String): List<String> {
    val safe = value.trim().replace("'", "''")
    val suffix = "&\$select=no,description,baseUnitOfMeasure,itemCategoryCode&\$orderby=no&\$top=25"
    return listOf(
        "items?\$filter=contains(no,'$safe')$suffix",
        "items?\$filter=contains(description,'$safe')$suffix",
    )
}

internal fun mergeItemLookupRows(pages: List<List<JSONObject>>): List<JSONObject> =
    pages.flatten()
        .distinctBy { firstValue(it, "no", "number").trim().uppercase() }
        .sortedBy { firstValue(it, "no", "number").trim().uppercase() }
        .take(25)

private const val LABEL_COPIES_INVALID = "HATA: Etiket adedi 1 ile $LABEL_COPIES_MAX arasında olmalı."

private fun binLabelKey(locationCode: String, code: String) =
    "locationCode='${locationCode.replace("'", "''")}',code='${code.replace("'", "''")}'"

private fun labelPayload(printerCode: String, copies: Int) =
    JSONObject().put("printerId", printerCode).put("copies", copies).toString()

/**
 * Kitoko (19 Eki 2026): EMU'nun adetli ürün etiketi. Adet, BC ve yazıcı ajanının
 * kabul ettiği 10'luk işlere bölünür; ilk hatada durur, otomatik tekrar denemez.
 * Yazıcı [resolveInquiryPrinter] ile çözülür; seçili yazıcı yoksa istek gitmez.
 */
internal suspend fun printItemLabelCopies(context: Context, itemNo: String, total: Int): String {
    val choice = resolveInquiryPrinter(context).getOrElse { return "HATA: ${it.message}" }
    var sent = 0
    for (copies in labelCopyBatches(total)) {
        val r = try {
            BcApi.boundAction(context, "items", itemNo, "printLabel", labelPayload(choice.printerCode, copies))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            return "HATA: $itemNo etiketi gönderilemedi. ${error.message.orEmpty()}" +
                if (sent > 0) " · $total etiketin $sent adedi kuyruğa alınmıştı." else ""
        }
        if (!r.ok) return "🔴 Yazdırma: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})" +
            if (sent > 0) " · $total etiketin $sent adedi kuyruğa alınmıştı." else ""
        sent += copies
    }
    return "🟢 $total adet ürün etiketi ${choice.printerCode} kuyruğuna alındı ($itemNo)." +
        if (choice.warning.isBlank()) "" else " ${choice.warning}"
}

/** Prints one selected item's QR-only ETIKETV2 label. */
internal suspend fun sendSingleItemLabelV2(context: Context, itemNo: String): String {
    val choice = resolveInquiryPrinter(context).getOrElse { return "HATA: ${it.message}" }
    val payload = JSONObject()
        .put("itemNosJson", JSONArray().put(itemNo).toString())
        .put("printerId", choice.printerCode)
        .toString()
    val response = try {
        BcApi.boundActionLongRunning(context, "items", itemNo, "printLabelsV2", payload)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (error: Exception) {
        return "HATA: $itemNo ETIKETV2 etiketi gönderilemedi. ${error.message.orEmpty()}"
    }
    if (!response.ok) return "🔴 ETIKETV2: ${BcApi.errorMessage(response.body)} (HTTP ${response.httpCode})"
    return "🟢 $itemNo ETIKETV2 etiketi ${choice.printerCode} kuyruğuna alındı." +
        if (choice.warning.isBlank()) "" else " ${choice.warning}"
}

/** Raf etiketleri: her raf için adet kadar etiket; ilk hatada durur ve kaçının gittiğini söyler. */
internal suspend fun printBinLabelCopies(
    context: Context,
    rows: List<JSONObject>,
    total: Int,
    onProgress: (String) -> Unit = {},
): String {
    if (rows.isEmpty()) return "BOŞ: Yazdırılacak raf yok."
    val choice = resolveInquiryPrinter(context).getOrElse { return "HATA: ${it.message}" }
    var sent = 0
    for ((index, row) in rows.withIndex()) {
        val loc = rawValue(row, "locationCode"); val code = rawValue(row, "code")
        if (rows.size > 1) onProgress("🖨 ${rows.size} raf · $code (${index + 1}.)")
        for (copies in labelCopyBatches(total)) {
            val r = try {
                BcApi.boundAction(context, "bins", binLabelKey(loc, code), "printLabel", labelPayload(choice.printerCode, copies))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                return "HATA: $code raf etiketi gönderilemedi. ${error.message.orEmpty()}" +
                    if (sent > 0) " · $sent etiket kuyruğa alınmıştı." else ""
            }
            if (!r.ok) return "🔴 $code rafında durdu: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})" +
                if (sent > 0) " · $sent etiket kuyruğa alınmıştı." else ""
            sent += copies
        }
    }
    val target = if (rows.size == 1) "${rawValue(rows[0], "locationCode")}/${rawValue(rows[0], "code")} raf etiketi × $total"
        else "${rows.size} raf × $total etiket"
    return "🟢 $target ${choice.printerCode} kuyruğuna alındı." +
        if (choice.warning.isBlank()) "" else " ${choice.warning}"
}

/** DKÇ (17 Eyl 2026): alanın kendi QR etiketi (zones/printLabel). */
internal suspend fun printZoneLabelCopies(context: Context, locationCode: String, zoneCode: String, total: Int): String {
    val choice = resolveInquiryPrinter(context).getOrElse { return "HATA: ${it.message}" }
    for (copies in labelCopyBatches(total)) {
        val r = try {
            BcApi.boundAction(context, "zones", binLabelKey(locationCode, zoneCode), "printLabel", labelPayload(choice.printerCode, copies))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            return "HATA: $zoneCode alan etiketi gönderilemedi. ${error.message.orEmpty()}"
        }
        if (!r.ok) return "🔴 Alan etiketi: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})" +
            if (r.httpCode == 404) " · BC uzantısını güncelleyin." else ""
    }
    return "🟢 $zoneCode alan etiketi × $total ${choice.printerCode} kuyruğuna alındı." +
        if (choice.warning.isBlank()) "" else " ${choice.warning}"
}

/** Kitoko (19 Eki 2026): EMU'nun tekli ürün etiketi penceresi — yazıcı kartı ve adet. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ItemLabelPrintSheet(
    itemNo: String,
    copies: String,
    onCopies: (String) -> Unit,
    printing: Boolean,
    status: String,
    onPrint: () -> Unit,
    onPrintV2: () -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = { if (!printing) onDismiss() }) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Ürün etiketi yazdır", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(itemNo, style = MaterialTheme.typography.titleMedium)
            PrinterDestinationCard(inquiryFallback = true)
            LabelCopiesField(copies, onCopies, enabled = !printing)
            if (status.isNotBlank()) StatusText(status)
            val count = parseLabelCopies(copies)
            Button(
                onClick = onPrint,
                enabled = !printing && count != null,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            ) {
                WmsActionLabel(WmsGlyph.PRINTER, if (printing) "Gönderiliyor…" else "${count ?: "—"} adet etiket yazdır")
            }
            OutlinedButton(
                onClick = onPrintV2,
                enabled = !printing,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            ) {
                WmsActionLabel(WmsGlyph.PRINTER, if (printing) "Gönderiliyor…" else "1 adet ETIKETV2 yazdır (QR + madde no)")
            }
            TextButton(onClick = onDismiss, enabled = !printing, modifier = Modifier.fillMaxWidth()) {
                Text("Kapat")
            }
        }
    }
}

/**
 * Item Inquiry — item card + LP lines that contain the item (on-hand by LP).
 * [labelsOnly] = Etiket Çıkar ekranının ürün sekmesi (EMU akışı).
 */
@Composable
fun ItemInquiryModule(labelsOnly: Boolean = false) {
    if (labelsOnly) ItemLabelInquiry() else ItemStockInquiry()
}

/** BADE Ürün Sorgu: tek ürün kartı, LP yerleşimi ve son hareketler. */
@Composable
private fun ItemStockInquiry() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // PDF Item Inquiry §1: hardcoded "1004" preset removed — start empty so
    // the screen does not falsely claim an item exists before the operator
    // scans/types one.
    var query by remember { mutableStateOf("") }
    var item by remember { mutableStateOf<JSONObject?>(null) }
    var lpLines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var ledger by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var queriedLpNo by remember { mutableStateOf("") }
    var lpPlacement by remember { mutableStateOf<Map<String, LpPlacement>>(emptyMap()) }
    var status by remember { mutableStateOf("Ürün No. veya LP No. tarayın/girin.") }
    var loading by remember { mutableStateOf(false) }
    // Kitoko (19 Eki 2026): ürün etiketi EMU'daki gibi adetli ve yazıcı kartlı pencerede.
    var showLabelSheet by remember { mutableStateOf(false) }
    var labelCopies by remember { mutableStateOf("1") }
    var labelStatus by remember { mutableStateOf("") }
    var printing by remember { mutableStateOf(false) }

    fun load() {
        if (query.trim().isBlank() || printing) return
        scope.launch {
            loading = true; status = "Sorgulanıyor..."
            item = null; lpLines = emptyList(); ledger = emptyList(); queriedLpNo = ""; lpPlacement = emptyMap()
            labelCopies = "1"; showLabelSheet = false
            val q = query.trim()
            val safeQ = q.replace("'", "''")
            val byLp = BcApi.getAllPages(context, "licensePlateLines?\$filter=lpNo eq '$safeQ'&\$top=200")
            if (byLp.complete && byLp.rows.isNotEmpty()) {
                queriedLpNo = byLp.rows.first().optString("lpNo").trim().ifBlank { q }
            }
            val resolvedItemNo = if (byLp.complete && byLp.rows.isNotEmpty()) byLp.rows.first().optString("itemNo") else q
            val safeItemNo = resolvedItemNo.replace("'", "''")
            val r = BcApi.getWithStandardFallback(context, "items?\$filter=no eq '$safeItemNo'&\$top=1", "items?\$filter=number eq '$safeItemNo'&\$top=1")
            if (r.ok) {
                val list = BcApi.parseValueArray(r.body)
                item = list.firstOrNull()
            }
            // on-hand by LP: lines for this item across license plates
            val lpPage = if (byLp.complete && byLp.rows.isNotEmpty()) byLp
                else BcApi.getAllPages(context, "licensePlateLines?\$filter=itemNo eq '$safeItemNo'&\$top=50")
            if (lpPage.complete) lpLines = lpPage.rows
            // BADE (16 Eyl 2026): LP ile sorguda Alan Kodu ve Raf/Depo Gözü de gelsin.
            lpPlacement = loadLpPlacements(context, lpLines.map { it.optString("lpNo") })
            // Son Hareketler (Item Ledger) — WI "Recent Transactions" pariteti.
            val le = BcApi.get(context, "itemLedgerEntries?\$filter=itemNo eq '$safeItemNo'&\$orderby=postingDate desc,entryNo desc&\$top=20")
            if (le.ok) ledger = BcApi.parseValueArray(le.body)
            loading = false
            status = when {
                !lpPage.complete -> "HATA: Ürünün LP kayıtlarının tamamı alınamadı. Yenileyin."
                item == null -> "BOŞ: '$q' için ürün veya LP bulunamadı."
                byLp.rows.isNotEmpty() -> "TAMAM: $q LP içeriği · ${lpLines.size} satır · ${ledger.size} ürün hareketi."
                else -> "TAMAM: ürün bulundu · ${lpLines.size} LP · ${ledger.size} hareket."
            }
        }
    }

    fun printItemLabel() {
        if (printing) return
        val no = item?.let { rawValue(it, "no", "number") }?.takeIf { it.isNotBlank() } ?: return
        val total = parseLabelCopies(labelCopies) ?: run { labelStatus = LABEL_COPIES_INVALID; return }
        printing = true
        labelStatus = "🖨 $total adet ürün etiketi yazdırılıyor..."
        scope.launch {
            try {
                labelStatus = printItemLabelCopies(context, no, total)
                status = labelStatus
            } finally {
                printing = false
            }
        }
    }

    fun printItemLabelV2() {
        if (printing) return
        val no = item?.let { rawValue(it, "no", "number") }?.takeIf { it.isNotBlank() } ?: return
        printing = true
        labelStatus = "🖨 $no ETIKETV2 yazdırılıyor..."
        scope.launch {
            try {
                labelStatus = sendSingleItemLabelV2(context, no)
                status = labelStatus
            } finally {
                printing = false
            }
        }
    }

    val palette = bcwmsStatus()
    val itemUom = item?.let { firstValue(it, "baseUnitOfMeasure", "baseUoM") }.orEmpty()
    Column(Modifier.fillMaxSize().padding(12.dp)) {
        ScanField("Ürün No / LP No", query, { query = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            val resolved = BarcodeIntentResolver.resolve(it)
            query = resolved.itemNo ?: resolved.value
        })
        Spacer(Modifier.height(8.dp))
        Button(onClick = { load() }, enabled = !loading, modifier = Modifier.fillMaxWidth()) {
            Text(if (loading) "..." else "🔎 Sorgula", fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(8.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        item?.let { it ->
            val blocked = it.optBoolean("blocked", false)
            val inventory = it.optDouble("inventory", Double.NaN)
            val qtyOnPo = it.optDouble("quantityOnPurchOrder", 0.0)
            val qtyOnSo = it.optDouble("quantityOnSalesOrder", 0.0)
            val qtyOnProd = it.optDouble("quantityOnProdOrder", 0.0)
            val reserved = it.optDouble("reservedQtyOnInventory", 0.0)
            val uom = itemUom
            val available = (if (inventory.isNaN()) 0.0 else inventory) - reserved
            val totalOnLp = lpLines.sumOf { l -> l.optDouble("quantity") }
            val scannedLp = queriedLpSummary(queriedLpNo, lpLines)
            Card(
                Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (blocked) palette.danger.copy(alpha = 0.10f)
                    else MaterialTheme.colorScheme.primary.copy(alpha = 0.07f),
                ),
            ) {
                Column(Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(firstValue(it, "no", "number"), fontWeight = FontWeight.Bold, fontSize = 18.sp, color = MaterialTheme.colorScheme.onSurface)
                        if (blocked) {
                            Spacer(Modifier.width(8.dp))
                            InfoPill("🚫 Bloke", containerColor = palette.danger, contentColor = Color.White)
                        }
                    }
                    Text(firstValue(it, "description", "displayName"), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
                    Spacer(Modifier.height(10.dp))
                    scannedLp?.let { lp ->
                        Surface(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(12.dp),
                            color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.72f),
                        ) {
                            Column(Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
                                Text(
                                    "Okutulan LP",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                                )
                                Text(
                                    "${lp.lpNo} · Adet: ${fmtItemQty(lp.quantity)}",
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                                )
                                Text(
                                    "Lot: ${lp.lotNos.joinToString(" · ").ifBlank { "-" }}",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                                )
                                lpPlacementLabel(lpPlacement[lp.lpNo]).takeIf { it.isNotBlank() }?.let { place ->
                                    Text(
                                        place,
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                                    )
                                }
                            }
                        }
                        Spacer(Modifier.height(10.dp))
                    }
                    // Stock block — PDF Item Inquiry §1 critical fix.
                    if (!inventory.isNaN()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            StockTile("Stok", inventory, uom, palette.success, Modifier.weight(1f))
                            StockTile("Müsait", available, uom, MaterialTheme.colorScheme.primary, Modifier.weight(1f))
                            StockTile("Rezerve", reserved, uom, palette.warning, Modifier.weight(1f))
                        }
                        Spacer(Modifier.height(8.dp))
                        Text("Gelen ${fmtItemQty(qtyOnPo)} · Giden ${fmtItemQty(qtyOnSo)} · Üretim ${fmtItemQty(qtyOnProd)}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Spacer(Modifier.height(8.dp))
                    Text("Temel UOM: $uom", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Kategori: ${firstValue(it, "itemCategoryCode")} · LP Şablonu: ${firstValue(it, "defaultLpTemplateCode")}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("LP'lerdeki toplam: ${fmtItemQty(totalOnLp)} $uom", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = { labelStatus = ""; showLabelSheet = true },
                enabled = !printing,
                modifier = Modifier.fillMaxWidth().height(48.dp),
            ) {
                WmsActionLabel(WmsGlyph.PRINTER, "Ürün Etiketi Bas")
            }
            Spacer(Modifier.height(12.dp))
            Text("LP'lerde (${lpLines.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
            Spacer(Modifier.height(6.dp))
        }
        // weight(1f): üstteki sabit ürün kartı listeyi sıfır yüksekliğe
        // sıkıştırıp LP/hareket satırlarını kesiyordu (yatay mod / küçük ekran).
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(lpLines) { ln ->
                Card(Modifier.fillMaxWidth().heightIn(min = 82.dp), shape = RoundedCornerShape(12.dp)) {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(
                                ln.optString("lpNo"),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                            val extra = listOfNotNull(
                                ln.optString("lotNo").takeIf { it.isNotBlank() }?.let { "Lot $it" },
                                ln.optString("serialNo").takeIf { it.isNotBlank() }?.let { "Seri $it" },
                                lpPlacementLabel(lpPlacement[ln.optString("lpNo").trim()]).takeIf { it.isNotBlank() },
                            ).joinToString(" · ")
                            if (extra.isNotBlank()) {
                                Text(extra, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        Spacer(Modifier.width(12.dp))
                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                fmtItemQty(ln.optDouble("quantity")),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.primary,
                            )
                            Text(
                                itemUom.ifBlank { "ADET" },
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
            if (item != null && lpLines.isEmpty() && !loading) item { EmptyState("Bu ürün hiçbir LP'de bulunmuyor.") }
            if (ledger.isNotEmpty()) {
                item {
                    Text("Son Hareketler (${ledger.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.padding(top = 10.dp, bottom = 4.dp))
                }
                items(ledger) { e ->
                    val qty = e.optDouble("quantity")
                    Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text("${bcEntryTypeLabelTr(e.optString("entryType"))} · ${e.optString("documentNo")}", fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurface)
                                Text("${e.optString("postingDate").take(10)} · ${firstValue(e, "locationCode")}" + e.optString("lotNo").takeIf { it.isNotBlank() }?.let { " · Lot $it" }.orEmpty(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Text(fmtItemQty(qty), fontWeight = FontWeight.Bold, color = if (qty < 0) bcwmsStatus().danger else bcwmsStatus().success)
                        }
                    }
                }
            }
        }
    }
    val labelItem = item
    if (showLabelSheet && labelItem != null) ItemLabelPrintSheet(
        itemNo = firstValue(labelItem, "no", "number"),
        copies = labelCopies,
        onCopies = { labelCopies = it },
        printing = printing,
        status = labelStatus,
        onPrint = { printItemLabel() },
        onPrintV2 = { printItemLabelV2() },
        onDismiss = { if (!printing) showLabelSheet = false },
    )
}

/**
 * Kitoko (19 Eki 2026): DKÇ/EMU "Etiket Çıkar → Ürün Etiketi". Okutulan ürünler
 * listede birikir; tekli (adetli), toplu ve tüm ürünlerin etiketi buradan basılır.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ItemLabelInquiry() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val focusRequester = remember { FocusRequester() }
    val listState = rememberLazyListState()

    var query by remember { mutableStateOf("") }
    var queriedItems by remember { mutableStateOf<List<InquiryItemEntry>>(emptyList()) }
    var expandedKey by remember { mutableStateOf<String?>(null) }
    var printKey by remember { mutableStateOf<String?>(null) }
    var showPrintStatus by remember { mutableStateOf(false) }
    var bulkProducts by remember { mutableStateOf<List<InquiryLabelProduct>?>(null) }
    var bulkResult by remember { mutableStateOf<InquiryLabelBatchResult?>(null) }
    var bulkProgress by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("Ürün No. veya LP No. tarayın/girin.") }
    var loading by remember { mutableStateOf(false) }
    var printing by remember { mutableStateOf(false) }
    var suggestions by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var suggestionsLoading by remember { mutableStateOf(false) }

    var pullOffset by remember { mutableFloatStateOf(0f) }
    val pullThreshold = 75f

    // Sayfa açılır açılmaz donanım tarayıcıya odaklan (ekrana dokunmaya gerek kalmadan doğrudan okut)
    LaunchedEffect(Unit) {
        delay(150)
        runCatching { focusRequester.requestFocus() }
    }

    // Yazarken ürün no / açıklamada geçen ürünler önerilir.
    LaunchedEffect(query) {
        val needle = query.trim()
        if (needle.isEmpty()) {
            suggestions = emptyList()
            suggestionsLoading = false
            return@LaunchedEffect
        }
        if (loading) return@LaunchedEffect
        delay(250)
        suggestionsLoading = true
        try {
            val pages = itemLookupPaths(needle).map { path ->
                async { runCatching { BcApi.getAllPages(context, path) }.getOrNull() }
            }.awaitAll()
            suggestions = mergeItemLookupRows(pages.filter { it?.complete == true }.map { requireNotNull(it).rows })
        } finally {
            suggestionsLoading = false
        }
    }

    fun clearInquiry() {
        query = ""
        suggestions = emptyList()
        status = "Sorgu temizlendi. Yeni barkod okutabilirsiniz."
        scope.launch {
            delay(80)
            runCatching { focusRequester.requestFocus() }
        }
    }

    fun clearAllItems() {
        queriedItems = emptyList()
        expandedKey = null
        clearInquiry()
    }

    fun load(requestedQuery: String = query, clearQueryAfter: Boolean = false) {
        if (requestedQuery.trim().isBlank() || loading || printing || bulkProducts != null) return
        loading = true
        scope.launch {
            try {
                status = "Sorgulanıyor..."
                suggestions = emptyList()
                val q = requestedQuery.trim()
                val safeQ = q.replace("'", "''")

                var queriedLpNo = ""
                var resolvedItem: JSONObject? = null

                val byLp = BcApi.getAllPages(context, "licensePlateLines?\$filter=lpNo eq '$safeQ'&\$top=200")
                if (byLp.complete && byLp.rows.isNotEmpty()) {
                    queriedLpNo = byLp.rows.first().optString("lpNo").trim().ifBlank { q }
                }
                val resolvedItemNo = if (byLp.complete && byLp.rows.isNotEmpty()) byLp.rows.first().optString("itemNo") else q
                val safeItemNo = resolvedItemNo.replace("'", "''")
                val r = BcApi.getWithStandardFallback(context, "items?\$filter=no eq '$safeItemNo'&\$top=1", "items?\$filter=number eq '$safeItemNo'&\$top=1")
                if (r.ok) {
                    val list = BcApi.parseValueArray(r.body)
                    resolvedItem = list.firstOrNull()
                }

                val resolvedUom = resolvedItem?.let { firstValue(it, "baseUnitOfMeasure", "baseUoM") }.orEmpty()
                val newEntry = InquiryItemEntry(
                    queryKey = q,
                    item = resolvedItem,
                    lpLines = emptyList(),
                    ledger = emptyList(),
                    queriedLpNo = queriedLpNo,
                    uom = resolvedUom,
                )

                queriedItems = addInquiryEntry(queriedItems, newEntry)
                if (resolvedItem != null || queriedLpNo.isNotBlank()) expandedKey = q

                if (clearQueryAfter) {
                    query = ""
                } else {
                    query = q
                }

                status = when {
                    resolvedItem == null && queriedLpNo.isBlank() -> "BOŞ: '$q' için ürün veya LP bulunamadı."
                    else -> "TAMAM: ${firstValue(resolvedItem ?: JSONObject(), "no", "number")} bulundu."
                }

                delay(100)
                runCatching { focusRequester.requestFocus() }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                status = "HATA: Ürün sorgulanamadı. ${error.message.orEmpty()}"
            } finally {
                loading = false
            }
        }
    }

    fun printItemLabel(entry: InquiryItemEntry) {
        if (printing) return
        val no = entry.item?.let { rawValue(it, "no", "number") }?.takeIf { it.isNotBlank() } ?: return
        val total = parseLabelCopies(entry.labelCopies) ?: run {
            status = "HATA: Etiket adedi 1 ile $LABEL_COPIES_MAX arasında olmalı."
            return
        }
        printing = true
        status = "🖨 $total adet ürün etiketi yazdırılıyor..."
        scope.launch {
            try {
                status = printItemLabelCopies(context, no, total)
            } finally {
                printing = false
            }
        }
    }

    fun printItemLabelV2(entry: InquiryItemEntry) {
        if (printing) return
        val no = entry.item?.let { rawValue(it, "no", "number") }?.takeIf { it.isNotBlank() } ?: return
        printing = true
        status = "🖨 $no ETIKETV2 yazdırılıyor..."
        scope.launch {
            try {
                status = sendSingleItemLabelV2(context, no)
            } finally {
                printing = false
            }
        }
    }

    fun printSelectedLabels(jobs: List<InquiryLabelJob>) {
        if (printing || jobs.isEmpty() || bulkResult != null) return
        printing = true
        bulkProgress = "Yazıcı hazırlanıyor…"
        queriedItems = queriedItems.map { entry ->
            val no = entry.item?.let { rawValue(it, "no", "number") }.orEmpty()
            val job = jobs.firstOrNull { it.itemNo.equals(no, ignoreCase = true) }
            if (job == null) entry else entry.copy(labelCopies = job.copies.toString())
        }
        scope.launch {
            try {
                val choice = resolveInquiryPrinter(context).getOrElse {
                    bulkResult = InquiryLabelBatchResult(emptyMap(), it.message ?: "Yazıcı seçimi doğrulanamadı.")
                    return@launch
                }
                bulkResult = sendInquiryLabelBatch(jobs, send = { no, copies ->
                    val payload = JSONObject().put("printerId", choice.printerCode).put("copies", copies).toString()
                    val response = BcApi.boundAction(context, "items", no, "printLabel", payload)
                    if (response.ok) Result.success(Unit)
                    else Result.failure(IllegalStateException("$no: ${BcApi.errorMessage(response.body)} (HTTP ${response.httpCode})"))
                }, onProgress = { no, sent, total ->
                    bulkProgress = "$sent / $total etiket gönderildi · $no"
                })
                val outcome = requireNotNull(bulkResult)
                status = if (outcome.complete) "TAMAM: ${jobs.size} ürünün ${outcome.totalSent} etiketi kuyruğa alındı."
                    else "HATA: ${outcome.error} · ${outcome.totalSent} etiketin gönderimi doğrulandı."
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                bulkResult = InquiryLabelBatchResult(emptyMap(), error.message ?: "Yazdırma başlatılamadı.")
            } finally {
                printing = false
            }
        }
    }

    val palette = bcwmsStatus()

    LazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectVerticalDragGestures(
                    onDragEnd = {
                        if (pullOffset > pullThreshold) {
                            clearInquiry()
                        }
                        pullOffset = 0f
                    },
                    onDragCancel = { pullOffset = 0f },
                    onVerticalDrag = { change, dragAmount ->
                        if (listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset == 0) {
                            if (dragAmount > 0 || pullOffset > 0) {
                                pullOffset = (pullOffset + dragAmount * 0.5f).coerceIn(0f, 160f)
                                change.consume()
                            }
                        }
                    }
                )
            }
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // Kitoko (21 Eki 2026): EMU'dan Excel'den sıralı ürün / göz etiketleri.
        if (com.dynops.bcwms.BuildConfig.FLAVOR == "kitoko") item { ExcelItemLabelsCard(enabled = !loading && !printing) }
        // DKÇ (9 Eki 2026): Etiket Çıkar → Ürün Etiketi'nde bütün ürünler tek seferde.
        item { AllItemLabelsCard(enabled = !loading && !printing) }
        item { AllItemLabelsCard(enabled = !loading && !printing, v2Format = true) }
        item { AllItemLabelsCard(enabled = !loading && !printing, v2Format = true, itemLimit = 300) }
        // Aşağı çekerek silme bildirimi (Swipe down to clear)
        if (pullOffset > 10f) {
            item {
                Surface(
                    modifier = Modifier.fillMaxWidth().height((pullOffset * 0.6f).coerceIn(32f, 56f).dp),
                    shape = RoundedCornerShape(12.dp),
                    color = if (pullOffset >= pullThreshold) palette.danger.copy(alpha = 0.15f)
                            else MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.85f),
                ) {
                    Row(
                        Modifier.fillMaxSize(),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        WmsIcon(
                            glyph = if (pullOffset >= pullThreshold) WmsGlyph.CLOSE else WmsGlyph.REFRESH,
                            color = if (pullOffset >= pullThreshold) palette.danger else MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            if (pullOffset >= pullThreshold) "Bırakınca arama alanı silinecek"
                            else "Aramayı silmek için aşağı çekin...",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold,
                            color = if (pullOffset >= pullThreshold) palette.danger else MaterialTheme.colorScheme.onSecondaryContainer
                        )
                    }
                }
            }
        }

        item {
            Surface(
                color = MaterialTheme.colorScheme.surface,
                shape = RoundedCornerShape(16.dp),
                border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.65f)),
            ) {
                Column(Modifier.padding(10.dp)) {
            ScanField(
                label = "Ürün No / LP No",
                value = query,
                onValueChange = { query = it },
                modifier = Modifier.fillMaxWidth(),
                enabled = !loading,
                okButton = false,
                autoFocus = true,
                focusRequester = focusRequester,
                onClear = { clearInquiry() },
                onScanned = {
                    val resolved = BarcodeIntentResolver.resolve(it)
                    val scanned = resolved.itemNo ?: resolved.value
                    query = scanned
                    load(scanned, clearQueryAfter = true)
                }
            )

            Spacer(Modifier.height(6.dp))

            // Hızlı butonlar: Sorgula ve Temizle
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Spacer(Modifier.weight(1f))
                if (query.isNotBlank()) {
                    OutlinedButton(
                        onClick = { clearInquiry() },
                        modifier = Modifier.height(36.dp),
                        contentPadding = PaddingValues(horizontal = 10.dp)
                    ) {
                        Text("Temizle", fontSize = 12.sp)
                    }
                }
                Button(
                    onClick = { load(query, clearQueryAfter = false) },
                    enabled = !loading && query.isNotBlank(),
                    modifier = Modifier.height(36.dp),
                    contentPadding = PaddingValues(horizontal = 14.dp)
                ) {
                    Text(if (loading) "..." else "Sorgula", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                }
            }

                }
            }

            if (suggestionsLoading) {
                Spacer(Modifier.height(6.dp))
                LinearProgressIndicator(Modifier.fillMaxWidth())
            }

            if (suggestions.isNotEmpty()) {
                Text(
                    "Eşleşen ürünler (${suggestions.size})",
                    modifier = Modifier.padding(top = 8.dp),
                    fontWeight = FontWeight.Bold,
                    fontSize = 13.sp,
                )
            }

            suggestions.forEach { suggestion ->
                val no = firstValue(suggestion, "no", "number")
                val description = firstValue(suggestion, "description", "displayName")
                val cat = firstValue(suggestion, "itemCategoryCode")
                Card(
                    onClick = {
                        query = no
                        load(no, clearQueryAfter = true)
                    },
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                    shape = RoundedCornerShape(10.dp),
                ) {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 9.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(no, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                            if (description.isNotBlank()) Text(description, fontSize = 12.sp, color = Color.Gray, maxLines = 2)
                        }
                        if (cat.isNotBlank()) {
                            Spacer(Modifier.width(6.dp))
                            InfoPill(cat, containerColor = MaterialTheme.colorScheme.surfaceVariant, contentColor = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }

            // The result card already confirms a successful lookup.
            if (queriedItems.isEmpty() || !status.startsWith("TAMAM:")) {
                Spacer(Modifier.height(6.dp))
                StatusText(status)
            }

            // Çoklu Ürün Sorgu Başlığı
            if (queriedItems.isNotEmpty()) {
                Row(
                    Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 2.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        "Sorgulanan ürünler · ${queriedItems.size}",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    TextButton(
                        onClick = { clearAllItems() },
                        enabled = !loading && !printing,
                        contentPadding = PaddingValues(horizontal = 6.dp, vertical = 2.dp)
                    ) {
                        Text("Listeyi temizle", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                    }
                }
            }
        }

        val printableProducts = inquiryLabelProducts(queriedItems)
        if (printableProducts.isNotEmpty()) {
            item {
                FilledTonalButton(
                    onClick = {
                        bulkResult = null
                        bulkProgress = ""
                        bulkProducts = printableProducts
                    },
                    enabled = !loading && !printing,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    WmsActionLabel(WmsGlyph.PRINTER, "Toplu etiket yazdır · ${printableProducts.size} ürün")
                }
            }
        }

        // Çoklu Ürün Kartları Listesi
        items(queriedItems, key = { it.queryKey }) { entry ->
            val isExpanded = expandedKey == entry.queryKey

            val removeEntry = {
                queriedItems = queriedItems.filterNot { it.queryKey == entry.queryKey }
                if (expandedKey == entry.queryKey) expandedKey = null
            }
            val dismissState = rememberSwipeToDismissBoxState(
                confirmValueChange = { value ->
                    if (value == SwipeToDismissBoxValue.EndToStart && !printing && !loading) {
                        removeEntry()
                    }
                    // The list owns removal; keep the gesture reusable if queried again.
                    false
                },
            )
            SwipeToDismissBox(
                state = dismissState,
                enableDismissFromStartToEnd = false,
                enableDismissFromEndToStart = !printing && !loading,
                backgroundContent = {
                    Surface(
                        modifier = Modifier.fillMaxSize(),
                        shape = RoundedCornerShape(14.dp),
                        color = if (dismissState.dismissDirection == SwipeToDismissBoxValue.EndToStart) palette.danger else Color.Transparent,
                    ) {
                        Box(Modifier.padding(16.dp), contentAlignment = Alignment.CenterEnd) {
                            Text("Listeden çıkar", color = Color.White, fontWeight = FontWeight.Bold)
                        }
                    }
                },
            ) {
                InquiryItemCard(
                    entry = entry,
                    expanded = isExpanded,
                    labelsOnly = true,
                    busy = printing || loading,
                    onToggle = { expandedKey = if (isExpanded) null else entry.queryKey },
                    onRemove = removeEntry,
                    onPrint = {
                        showPrintStatus = false
                        printKey = entry.queryKey
                    },
                )
            }
        }
    }

    bulkProducts?.let { products ->
        BulkItemLabelsSheet(
            products = products,
            printing = printing,
            progress = bulkProgress,
            result = bulkResult,
            onPrint = ::printSelectedLabels,
            onTestPrint = { itemNo -> printItemLabelCopies(context, itemNo, 1) },
            onDismiss = { if (!printing) bulkProducts = null },
        )
    }

    val printEntry = queriedItems.firstOrNull { it.queryKey == printKey }
    if (printEntry != null) {
        ItemLabelPrintSheet(
            itemNo = printEntry.item?.let { firstValue(it, "no", "number") } ?: printEntry.queryKey,
            copies = printEntry.labelCopies,
            onCopies = { copies ->
                queriedItems = queriedItems.map { row ->
                    if (row.queryKey == printEntry.queryKey) row.copy(labelCopies = copies) else row
                }
            },
            printing = printing,
            status = if (showPrintStatus) status else "",
            onPrint = { showPrintStatus = true; printItemLabel(printEntry) },
            onPrintV2 = { showPrintStatus = true; printItemLabelV2(printEntry) },
            onDismiss = { if (!printing) printKey = null },
        )
    }
}

/**
 * Bin Inquiry — bin card + real bin contents (item × qty) + LPs in the bin.
 * [labelsOnly] = Etiket Çıkar ekranının raf sekmesi (EMU akışı).
 */
@Composable
fun BinInquiryModule(labelsOnly: Boolean = false) {
    if (labelsOnly) BinLabelInquiry() else BinStockInquiry()
}

/** BADE Raf Sorgu: raf kartı, içerik, LP'ler (LP etiketi) ve ambar kayıtları. */
@Composable
private fun BinStockInquiry() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // PDF Bin Inquiry §2: hardcoded SILVER/S-1-01 preset removed.
    var location by remember { mutableStateOf("") }
    var binCode by remember { mutableStateOf("") }
    var bin by remember { mutableStateOf<JSONObject?>(null) }
    var contents by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var lps by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var selectedLpNos by remember { mutableStateOf<Set<String>>(emptySet()) }
    var whseEntries by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("Lokasyon + Bin girin.") }
    var loading by remember { mutableStateOf(false) }
    // Kitoko (19 Eki 2026): EMU Raf Sorgu — adetli raf etiketi veya A4 raf belgesi.
    var showLabelSheet by remember { mutableStateOf(false) }
    var documentOutput by rememberSaveable { mutableStateOf(false) }
    var labelCopies by remember { mutableStateOf("1") }
    var labelStatus by remember { mutableStateOf("") }
    var printing by remember { mutableStateOf(false) }

    fun load() {
        if (location.trim().isBlank() || binCode.trim().isBlank() || printing) return
        scope.launch {
            loading = true; status = "Yükleniyor..."
            bin = null; contents = emptyList(); lps = emptyList(); selectedLpNos = emptySet(); whseEntries = emptyList()
            labelCopies = "1"; showLabelSheet = false
            val loc = location.trim(); val code = binCode.trim()
            val b = BcApi.get(context, "bins?\$filter=locationCode eq '$loc' and code eq '$code'&\$top=1")
            if (b.ok) bin = BcApi.parseValueArray(b.body).firstOrNull()
            // PDF Bin Inquiry §2 critical fix: now also fetch the real item
            // quantities from the new BinContent API page (T7302 Bin Content).
            val contentsPage = BcApi.getAllPages(context, "binContents?\$filter=locationCode eq '$loc' and binCode eq '$code'")
            if (contentsPage.complete) contents = contentsPage.rows
                .filter { it.optDouble("quantity", 0.0) != 0.0 }
                .sortedWith(compareBy(warehouseBinCodeComparator) { it.optString("itemNo") })
            val lpPage = BcApi.getAllPages(context, "licensePlates?\$filter=locationCode eq '$loc' and binCode eq '$code'&\$orderby=no")
            if (lpPage.complete) lps = lpPage.rows
                .filter { activeLicensePlateStatus(it.optString("status")) }
                .sortedWith(compareBy(warehouseBinCodeComparator) { it.optString("no") })
            // Whse Entries (raf hareket geçmişi) — WI pariteti.
            val we = BcApi.get(context, "warehouseEntries?\$filter=locationCode eq '$loc' and binCode eq '$code'&\$orderby=registeringDate desc,entryNo desc&\$top=20")
            if (we.ok) whseEntries = BcApi.parseValueArray(we.body)
            loading = false
            status = if (!contentsPage.complete || !lpPage.complete) "HATA: Raf içeriğinin tamamı alınamadı. Yenileyin."
                else if (bin == null && contents.isEmpty() && lps.isEmpty()) "BOŞ: '$loc/$code' için içerik yok."
                else "TAMAM: ${contents.size} ürün · ${lps.size} LP · ${whseEntries.size} hareket."
        }
    }

    fun printBinLabel() {
        if (printing) return
        val b = bin ?: return
        if (rawValue(b, "locationCode").isBlank() || rawValue(b, "code").isBlank()) return
        val total = parseLabelCopies(labelCopies) ?: run { labelStatus = LABEL_COPIES_INVALID; return }
        printing = true
        labelStatus = "🖨 Bin etiketi yazdırılıyor..."
        scope.launch {
            try {
                labelStatus = printBinLabelCopies(context, listOf(b), total)
                status = labelStatus
            } finally {
                printing = false
            }
        }
    }

    fun printSelectedLpLabels() {
        if (loading || selectedLpNos.isEmpty()) return
        val requested = lps.map { it.optString("no") }.filter { it in selectedLpNos }
        if (requested.isEmpty()) return
        scope.launch {
            loading = true
            val failures = linkedMapOf<String, String>()
            val labelPrinter = getDefaultPrinter(context, PRINTER_USAGE_LABEL)
            val documentPrinter = getDefaultPrinter(context, PRINTER_USAGE_DOCUMENT)
            var completed = 0
            for (batch in bulkLpPrintBatches(requested)) {
                status = "LP etiketleri kuyruğa alınıyor: $completed/${requested.size}"
                val results = batch.map { no ->
                    val lp = lps.first { it.optString("no") == no }
                    val route = bulkLpPrintRoute(lp.optInt("lineCount"), labelPrinter, documentPrinter)
                    async {
                        val payload = JSONObject().apply {
                            put("printerId", route.printerCode)
                            put("copies", 1)
                        }.toString()
                        val response = BcApi.boundActionLongRunning(context, "licensePlates", no, route.action, payload)
                        no to if (response.ok) null else QcErrorParser.friendlyStatus(
                            BcApi.errorMessage(response.body), response.httpCode,
                        ).removePrefix("HATA: ")
                    }
                }.awaitAll()
                results.forEach { (no, error) -> if (error != null) failures[no] = error }
                completed += batch.size
            }
            selectedLpNos = failures.keys.toSet()
            loading = false
            status = if (failures.isEmpty()) "TAMAM: ${requested.size} LP etiketi yazdırma kuyruğuna alındı."
                else "UYARI: ${failures.size} LP etiketi yazdırılamadı. ${failures.entries.first().key}: ${failures.values.first()}"
        }
    }

    val palette = bcwmsStatus()
    Column(Modifier.fillMaxSize().padding(12.dp)) {
        ScanField("Lokasyon", location, { location = it }, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        ScanField("Bin", binCode, { binCode = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            binCode = BarcodeIntentResolver.resolve(it).value
        })
        Spacer(Modifier.height(8.dp))
        Button(onClick = { load() }, enabled = !loading, modifier = Modifier.fillMaxWidth()) {
            Text(if (loading) "..." else "🔎 Sorgula", fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(8.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        bin?.let { b ->
            val blocked = b.optBoolean("blockMovement", false)
            Card(
                Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (blocked) palette.danger.copy(alpha = 0.10f) else palette.success.copy(alpha = 0.10f),
                ),
            ) {
                Column(Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("${firstValue(b, "locationCode")} / ${firstValue(b, "code")}", fontWeight = FontWeight.Bold, fontSize = 18.sp, color = MaterialTheme.colorScheme.onSurface)
                        if (blocked) {
                            Spacer(Modifier.width(8.dp))
                            InfoPill("🚫 Hareket Engelli", containerColor = palette.danger, contentColor = Color.White)
                        }
                    }
                    Text(rawValue(b, "description").ifBlank { "—" }, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
                    Text("Bölge: ${rawValue(b, "zoneCode").ifBlank { "—" }} · Tip: ${rawValue(b, "binTypeCode").ifBlank { "—" }}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = { labelStatus = ""; documentOutput = false; showLabelSheet = true },
                enabled = !printing,
                modifier = Modifier.fillMaxWidth().height(48.dp),
            ) {
                WmsActionLabel(WmsGlyph.PRINTER, "Bin Etiketi Bas")
            }
            Spacer(Modifier.height(8.dp))
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.weight(1f)) {
            if (contents.isNotEmpty()) {
                item {
                    Text("Bin İçeriği (${contents.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.padding(vertical = 4.dp))
                }
                items(contents) { c ->
                    Card(
                        Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(containerColor = palette.warning.copy(alpha = 0.10f)),
                    ) {
                        Row(
                            Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(c.optString("itemNo"), fontWeight = FontWeight.Bold, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurface)
                                val desc = c.optString("itemDescription")
                                if (desc.isNotBlank()) Text(desc, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                val activeLpNos = c.optString("activeLpNos")
                                if (activeLpNos.isNotBlank()) {
                                    Text(
                                        "LP: $activeLpNos · LP içindeki miktar: ${fmtItemQty(c.optDouble("activeLpQuantity"))}",
                                        style = MaterialTheme.typography.bodySmall,
                                        fontWeight = FontWeight.SemiBold,
                                        color = MaterialTheme.colorScheme.primary,
                                    )
                                }
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text(fmtItemQty(c.optDouble("quantity")), fontWeight = FontWeight.Bold, fontSize = 16.sp, color = MaterialTheme.colorScheme.primary)
                                Text(c.optString("unitOfMeasureCode").ifBlank { "—" }, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
                item { Spacer(Modifier.height(8.dp)) }
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("LP'ler (${lps.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
                    if (lps.isNotEmpty()) TextButton(
                        onClick = {
                            selectedLpNos = if (selectedLpNos.size == lps.size) emptySet()
                                else lps.map { it.optString("no") }.toSet()
                        },
                        enabled = !loading,
                    ) { Text(if (selectedLpNos.size == lps.size) "Seçimi Kaldır" else "Tümünü Seç") }
                }
                if (selectedLpNos.isNotEmpty()) Button(
                    onClick = { printSelectedLpLabels() },
                    enabled = !loading,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Seçilen LP Etiketlerini Bas (${selectedLpNos.size})") }
            }
            items(lps) { lp ->
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        val lpNo = lp.optString("no")
                        Checkbox(
                            checked = lpNo in selectedLpNos,
                            onCheckedChange = { checked ->
                                selectedLpNos = if (checked) selectedLpNos + lpNo else selectedLpNos - lpNo
                            },
                            enabled = !loading,
                        )
                        Column {
                            Text("$lpNo · ${lpStatusLabel(lp.optString("status"))}", fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurface)
                            Text("${lp.optString("templateCode")}${lp.optString("sscc").takeIf { it.isNotBlank() }?.let { " · SSCC $it" } ?: ""}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            if (lp.has("lineCount") || lp.has("totalQuantity")) {
                                Text(
                                    "LP içeriği: ${fmtItemQty(lp.optDouble("totalQuantity"))} adet · ${lp.optInt("lineCount")} satır",
                                    style = MaterialTheme.typography.bodySmall,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                            }
                        }
                    }
                }
            }
            if (lps.isEmpty() && !loading) item { EmptyState("Bu bin'de LP yok.") }
            if (whseEntries.isNotEmpty()) {
                item {
                    Text("Ambar Kayıtları (${whseEntries.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.padding(top = 10.dp, bottom = 4.dp))
                }
                items(whseEntries) { e ->
                    val qty = e.optDouble("quantity")
                    Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text("${e.optString("itemNo")} · ${bcEntryTypeLabelTr(e.optString("entryType"))}", fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurface)
                                Text("${e.optString("registeringDate").take(10)}" + e.optString("lotNo").takeIf { it.isNotBlank() }?.let { " · Lot $it" }.orEmpty() + e.optString("lpNo").takeIf { it.isNotBlank() }?.let { " · LP $it" }.orEmpty(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Text(fmtItemQty(qty), fontWeight = FontWeight.Bold, color = if (qty < 0) bcwmsStatus().danger else bcwmsStatus().success)
                        }
                    }
                }
            }
        }
    }
    val labelBin = bin
    if (showLabelSheet && labelBin != null) BinLabelPrintSheet(
        title = "Raf etiketi yazdır",
        summary = "${rawValue(labelBin, "locationCode")} / ${rawValue(labelBin, "code")}",
        targetCount = 1,
        areaOnly = false,
        copies = labelCopies, onCopies = { labelCopies = it },
        documentOutput = documentOutput, onDocumentOutput = { documentOutput = it },
        printing = printing, status = labelStatus,
        onDismiss = { if (!printing) showLabelSheet = false },
        onPrint = {
            if (documentOutput) {
                runCatching { printBinDocument(context, labelBin) }
                    .onFailure { labelStatus = "HATA: Belge açılamadı: ${it.message}" }
            } else printBinLabel()
        },
    )
}

/**
 * Kitoko (19 Eki 2026): DKÇ/EMU "Etiket Çıkar → Raf Etiketi". Tek / çoklu raf,
 * bir alanın (veya bölümünün) bütün rafları ya da yalnız alanın kendi etiketi;
 * raflar için A4 belge de alınabilir.
 */
@Composable
private fun BinLabelInquiry() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var documentOutput by rememberSaveable { mutableStateOf(false) }
    var labelMode by rememberSaveable { mutableStateOf(BinLabelMode.Single) }
    var showLabelPrintOptions by remember { mutableStateOf(false) }
    var location by remember { mutableStateOf("") }
    var binCode by remember { mutableStateOf("") }
    var bin by remember { mutableStateOf<JSONObject?>(null) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    // 16 Eyl 2026 (DKÇ): the operator could not guess the location/bin codes,
    // so both are offered as lookups from BC (locations API, bins API). Typing
    // and scanning still work; the lists are a convenience on top.
    var locations by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var binChoices by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var pickerBinRows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var selectedLabelBins by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var showLocationPicker by remember { mutableStateOf(false) }
    var manualLocation by remember { mutableStateOf(false) }
    var showBinPicker by remember { mutableStateOf(false) }
    var pickerLoading by remember { mutableStateOf(false) }
    var locationsLoading by remember { mutableStateOf(false) }
    var labelCopies by rememberSaveable { mutableStateOf("1") }
    var printing by remember { mutableStateOf(false) }
    // DKÇ (17 Eyl 2026): lokasyon → alan → o alandaki bütün rafların etiketi.
    var zones by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var zone by rememberSaveable { mutableStateOf("") }
    var zoneBins by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var showZonePicker by remember { mutableStateOf(false) }
    var zonesLoading by remember { mutableStateOf(false) }
    var zoneBinsLoading by remember { mutableStateOf(false) }
    val zoneLoading = zonesLoading || zoneBinsLoading
    var section by remember(location, zone) { mutableStateOf("") }
    var showSectionPicker by remember { mutableStateOf(false) }
    val sectionChoices = remember(zoneBins) { binSectionChoices(zoneBins) }
    val visibleZoneBins = remember(zoneBins, section) { filterBinSection(zoneBins, section) }

    fun clearSelectedBin() {
        binCode = ""; bin = null
    }

    fun chooseSection(value: String) {
        section = value
        clearSelectedBin()
        status = if (value.isBlank()) "TAMAM: Alanın tüm rafları gösteriliyor."
            else "TAMAM: $value bölümü · ${filterBinSection(zoneBins, value).size} raf."
    }

    // DKÇ (17 Eyl 2026): "lokasyonlar bulunamadı". The BCWMS locations API
    // only exists from BC 1.14.2.5; with an older extension the list failed.
    // A 404 now falls back to the standard BC API (code, displayName).
    suspend fun loadLocations() {
        locationsLoading = true
        val page = try {
            BcApi.getAllPagesWithStandardFallback(context, "locations?\$top=200&\$orderby=code")
        } finally {
            locationsLoading = false
        }
        if (page.complete) {
            locations = inquiryLocationChoices(page.rows)
            if (location.isBlank() && locations.size == 1) location = locations.first().first
            if (locations.isEmpty()) status = "BOŞ: BC'de seçilebilir lokasyon yok. Lokasyon kodunu elle girin."
        } else {
            val code = page.error?.httpCode?.takeIf { it > 0 }?.let { " (HTTP $it)" }.orEmpty()
            status = "HATA: Lokasyon listesi alınamadı$code. Lokasyon kodunu elle girin veya Seç ile yeniden deneyin."
        }
    }

    LaunchedEffect(Unit) { loadLocations() }

    suspend fun loadZones() {
        val loc = location.trim()
        if (loc.isBlank()) { zones = emptyList(); return }
        zonesLoading = true
        try {
            val safeLoc = loc.replace("'", "''")
            val page = BcApi.getAllPages(context, "zones?\$filter=locationCode eq '$safeLoc'&\$orderby=code&\$top=200")
            val choices = if (page.complete) inquiryZoneChoices(page.rows) else {
                val fallback = BcApi.getAllPages(context, "bins?\$filter=locationCode eq '$safeLoc'&\$select=zoneCode")
                if (fallback.complete) inquiryZoneChoices(fallback.rows.map { JSONObject().put("code", it.optString("zoneCode")) })
                else emptyList()
            }
            if (location.trim() == loc) zones = choices
        } finally {
            zonesLoading = false
        }
    }

    suspend fun loadZoneBins() {
        val loc = location.trim(); val z = zone.trim()
        zoneBins = emptyList()
        if (loc.isBlank() || z.isBlank()) return
        zoneBinsLoading = true
        try {
            val page = BcApi.getAllPages(context,
                "bins?\$filter=locationCode eq '${loc.replace("'", "''")}' and zoneCode eq '${z.replace("'", "''")}'&\$orderby=code")
            if (location.trim() != loc || zone.trim() != z) return
            if (!page.complete) { status = "HATA: Alanın rafları alınamadı. Alanı yeniden seçin."; return }
            val description = zones.firstOrNull { it.first.equals(z, ignoreCase = true) }?.second.orEmpty()
            zoneBins = sortedBinCodes(page.rows).map { row -> JSONObject(row.toString()).put("zoneDescription", description) }
            status = if (zoneBins.isEmpty()) "BOŞ: '$z' alanında raf yok."
                else "TAMAM: '$z' alanında ${zoneBins.size} raf. Etiketleri topluca alabilirsiniz."
        } finally {
            zoneBinsLoading = false
        }
    }

    /** DKÇ (17 Eyl 2026): sadece alanın kendi QR etiketi, raf girmeden. */
    fun printZoneOwnLabel() {
        if (printing) return
        val loc = location.trim(); val z = zone.trim()
        if (loc.isBlank() || z.isBlank()) return
        val total = parseLabelCopies(labelCopies) ?: run {
            status = "HATA: Etiket adedi 1 ile $LABEL_COPIES_MAX arasında olmalı."
            return
        }
        printing = true
        status = "🖨 $z alan etiketi yazdırılıyor..."
        scope.launch {
            try {
                status = printZoneLabelCopies(context, loc, z, total)
            } finally {
                printing = false
            }
        }
    }

    /** Raflara toplu etiket: seçili alanın (bölümün) gözden geçirilen rafları. */
    fun printBinRows(rows: List<JSONObject>) {
        if (printing || rows.isEmpty()) return
        // Freeze the reviewed selection before resolving the printer or sending jobs.
        val printRows = rows.toList()
        val total = parseLabelCopies(labelCopies) ?: run {
            status = "HATA: Etiket adedi 1 ile $LABEL_COPIES_MAX arasında olmalı."
            return
        }
        printing = true
        status = "🖨 ${printRows.size} raf etiketi yazdırılıyor..."
        scope.launch {
            try {
                status = printBinLabelCopies(context, printRows, total) { status = it }
            } finally {
                printing = false
            }
        }
    }

    LaunchedEffect(location) { zone = ""; zoneBins = emptyList(); selectedLabelBins = emptyList(); clearSelectedBin(); loadZones() }
    LaunchedEffect(location, zone, labelMode) {
        clearSelectedBin()
        labelCopies = "1"
        if (labelMode == BinLabelMode.Bulk) loadZoneBins()
    }

    // In the label flow, selecting, typing or scanning a bin prepares it automatically.
    // The effect cancels an older lookup when the code or location changes.
    LaunchedEffect(labelMode, location, binCode) {
        if (labelMode != BinLabelMode.Single) return@LaunchedEffect
        val selectedLocation = location.trim()
        val selectedCode = binCode.trim()
        bin = null
        if (selectedLocation.isBlank() || selectedCode.isBlank()) { loading = false; return@LaunchedEffect }
        delay(350)
        loading = true
        status = ""
        try {
            val response = BcApi.get(context,
                "bins?\$filter=locationCode eq '${selectedLocation.replace("'", "''")}' and code eq '${selectedCode.replace("'", "''")}'&\$top=1")
            if (location.trim() == selectedLocation && binCode.trim() == selectedCode) {
                bin = if (response.ok) BcApi.parseValueArray(response.body).firstOrNull() else null
                bin?.let { found ->
                    if (selectedLabelBins.none { rawValue(it, "code").equals(rawValue(found, "code"), true) }) {
                        selectedLabelBins = selectedLabelBins + found
                    }
                }
                status = if (!response.ok) "HATA: Raf alınamadı. Kodu kontrol edip tekrar deneyin."
                    else if (bin == null) "BOŞ: Bu depoda '$selectedCode' rafı bulunamadı." else ""
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            status = "HATA: Raf doğrulanamadı. ${error.message.orEmpty()}"
        } finally {
            loading = false
        }
    }

    fun openBinPicker() {
        val loc = location.trim()
        if (loc.isBlank()) { status = "Önce lokasyon seçin."; return }
        if (zone.isNotBlank()) {
            pickerBinRows = sortedBinCodes(visibleZoneBins)
            binChoices = pickerBinRows.map { it.optString("code") to it.optString("description") }
            if (binChoices.isEmpty()) status = "BOŞ: Seçili bölümde raf yok." else showBinPicker = true
            return
        }
        scope.launch {
            pickerLoading = true
            val page = BcApi.getAllPages(context, "bins?\$filter=locationCode eq '${loc.replace("'", "''")}'&\$orderby=code")
            pickerLoading = false
            if (!page.complete) { status = "HATA: Raf listesi alınamadı."; return@launch }
            pickerBinRows = sortedBinCodes(page.rows)
            binChoices = pickerBinRows.map { it.optString("code") to listOfNotNull(it.optString("zoneCode").takeIf { z -> z.isNotBlank() }?.let { z -> "Bölge $z" }, it.optString("description").takeIf { d -> d.isNotBlank() }).joinToString(" · ") }
            if (binChoices.isEmpty()) status = "BOŞ: '$loc' lokasyonunda raf yok." else showBinPicker = true
        }
    }


    val busy = printing || showLabelPrintOptions
    val targetRows = if (labelMode == BinLabelMode.Single) selectedLabelBins else visibleZoneBins
    val ready = location.isNotBlank() && !loading && !pickerLoading && !zoneLoading && when (labelMode) {
        BinLabelMode.Single -> selectedLabelBins.isNotEmpty()
        BinLabelMode.Bulk -> zone.isNotBlank() && visibleZoneBins.isNotEmpty()
        BinLabelMode.Zone -> zone.isNotBlank()
    }
    val targetSummary = when (labelMode) {
        BinLabelMode.Single -> "$location · ${selectedLabelBins.size} raf: ${selectedLabelBins.joinToString(", ") { rawValue(it, "code") }}"
        BinLabelMode.Bulk -> "$location / $zone" + section.takeIf(String::isNotBlank)?.let { " / $it" }.orEmpty() + " · ${visibleZoneBins.size} raf"
        BinLabelMode.Zone -> "$location / $zone · Alan etiketi"
    }
    LazyColumn(Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            BinLabelModePicker(labelMode, !busy && !loading && !pickerLoading) { mode ->
                if (mode != labelMode) {
                    labelMode = mode
                    selectedLabelBins = emptyList()
                    clearSelectedBin()
                    status = ""
                    if (mode == BinLabelMode.Single) { zone = ""; section = "" }
                }
            }
        }
        item {
            LabelWorkflowStep("1", "Depoyu seçin", "Etiketin kullanılacağı lokasyon") {
                SelectorRow(
                    label = "Depo / lokasyon", value = location,
                    hint = locations.firstOrNull { it.first == location }?.second.orEmpty(),
                    placeholder = if (locationsLoading) "Depolar yükleniyor…" else "Depo seç",
                    enabled = !busy && !locationsLoading && !pickerLoading,
                    onClick = {
                        if (locations.isNotEmpty()) showLocationPicker = true
                        else scope.launch { loadLocations(); if (locations.isNotEmpty()) showLocationPicker = true else manualLocation = true }
                    },
                )
                if (manualLocation) OutlinedTextField(
                    value = location, onValueChange = { location = it; status = "" },
                    label = { Text("Lokasyon kodu") }, singleLine = true,
                    enabled = !busy, modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        if (location.isNotBlank()) item {
            LabelWorkflowStep("2", if (labelMode == BinLabelMode.Single) "Rafı seçin veya okutun" else "Alanı seçin",
                when (labelMode) {
                    BinLabelMode.Single -> "İstediğiniz rafları seçin veya art arda okutun."
                    BinLabelMode.Bulk -> "Alandaki tüm raflar veya bir bölüm için etiket alın."
                    BinLabelMode.Zone -> "Yalnızca alanın kendi etiketini yazdırın."
                }) {
                if (labelMode == BinLabelMode.Single) {
                    OutlinedButton(onClick = { openBinPicker() },
                        enabled = !busy && !pickerLoading, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                        shape = RoundedCornerShape(12.dp)) {
                        WmsActionLabel(WmsGlyph.BIN_SEARCH, if (pickerLoading) "Raflar yükleniyor…" else "Rafları seç")
                    }
                    ScanField(
                        label = "Raf kodu yazın veya okutun", value = binCode,
                        onValueChange = { binCode = it; bin = null; status = "" },
                        enabled = !busy && !pickerLoading, okButton = false, autoFocus = false,
                        modifier = Modifier.fillMaxWidth(),
                        onScanned = { if (!busy) { binCode = BarcodeIntentResolver.resolve(it).value; bin = null; status = "" } },
                    )
                    if (loading) {
                        LinearProgressIndicator(Modifier.fillMaxWidth())
                        Text("Raf kontrol ediliyor…", style = MaterialTheme.typography.bodySmall)
                    }
                    if (selectedLabelBins.isNotEmpty()) {
                        Surface(color = MaterialTheme.colorScheme.primaryContainer,
                            shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(12.dp)) {
                                Text("Seçilen raflar (${selectedLabelBins.size})", fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer)
                                selectedLabelBins.forEach { selected ->
                                    val code = rawValue(selected, "code")
                                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                        Text(code, Modifier.weight(1f), fontWeight = FontWeight.Medium)
                                        TextButton(onClick = {
                                            selectedLabelBins = selectedLabelBins.filterNot { rawValue(it, "code").equals(code, true) }
                                            if (binCode.equals(code, true)) { binCode = ""; bin = null }
                                        }, enabled = !busy) { Text("Kaldır") }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    SelectorRow(label = "Alan", value = zone,
                        hint = zones.firstOrNull { it.first == zone }?.second.orEmpty(),
                        placeholder = if (zoneLoading) "Alanlar yükleniyor…" else "Alan seç",
                        enabled = !busy && !zoneLoading,
                        onClick = {
                            if (zones.isNotEmpty()) showZonePicker = true
                            else scope.launch {
                                loadZones()
                                if (zones.isNotEmpty()) showZonePicker = true
                                else status = "BOŞ: Bu depoda seçilebilir alan bulunamadı."
                            }
                        },
                    )
                    if (labelMode == BinLabelMode.Bulk && zone.isNotBlank()) {
                        if (zoneLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
                        if (sectionChoices.size > 1) SelectorRow(
                            label = "Bölüm filtresi · isteğe bağlı", value = section,
                            hint = "", placeholder = "Tüm bölümler", enabled = !busy && !zoneLoading,
                            onClick = { showSectionPicker = true },
                            onClear = if (section.isNotBlank()) ({ chooseSection("") }) else null,
                        )
                        if (visibleZoneBins.isNotEmpty()) {
                            Text("${visibleZoneBins.size} raf seçildi", fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                            Text(visibleZoneBins.take(5).joinToString(" · ") { it.optString("code") } +
                                if (visibleZoneBins.size > 5) " · +${visibleZoneBins.size - 5}" else "",
                                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            TextButton(onClick = { openBinPicker() }, enabled = !busy && !zoneLoading) { Text("Rafları incele") }
                        }
                    }
                }
            }
        }
        if (ready) item {
            LabelWorkflowStep("3", "Yazdırmaya hazır", targetSummary) {
                if (labelMode == BinLabelMode.Single && selectedLabelBins.size == 1) selectedLabelBins.firstOrNull()?.let { selected ->
                    val description = rawValue(selected, "description")
                    if (description.isNotBlank()) Text(description, style = MaterialTheme.typography.bodySmall)
                }
                Button(
                    onClick = { documentOutput = false; status = ""; showLabelPrintOptions = true },
                    enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    WmsActionLabel(WmsGlyph.PRINTER, when (labelMode) {
                        BinLabelMode.Single -> if (selectedLabelBins.size == 1) "Raf etiketini yazdır"
                            else "${selectedLabelBins.size} rafın etiketini yazdır"
                        BinLabelMode.Bulk -> "${visibleZoneBins.size} rafın etiketini yazdır"
                        BinLabelMode.Zone -> "Alan etiketini yazdır"
                    })
                }
                Text("Yazıcı ve adet bir sonraki adımda seçilir.", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (status.isNotBlank() && !status.startsWith("TAMAM:") && !showLabelPrintOptions) item { StatusText(status) }
    }
    if (showLocationPicker) InquiryPickerDialog("Depo / lokasyon seç", locations,
        onDismiss = { showLocationPicker = false },
        onPick = { clearSelectedBin(); zone = ""; zoneBins = emptyList(); location = it; manualLocation = false; status = ""; showLocationPicker = false })
    if (showZonePicker) InquiryPickerDialog("Alan seç · $location", zones,
        onDismiss = { showZonePicker = false },
        onPick = { zoneBins = emptyList(); section = ""; zone = it; status = ""; showZonePicker = false })
    if (showSectionPicker) InquiryPickerDialog("Bölüm seç · $zone",
        listOf("" to "Tüm bölümler · ${zoneBins.size} raf") + sectionChoices,
        onDismiss = { showSectionPicker = false },
        onPick = { chooseSection(it); showSectionPicker = false })
    if (showBinPicker && labelMode == BinLabelMode.Single) InquiryMultiBinPickerDialog(
        "Rafları seç · $location", pickerBinRows, selectedLabelBins.map { rawValue(it, "code") }.toSet(),
        onDismiss = { showBinPicker = false },
        onToggle = { row ->
            val code = rawValue(row, "code")
            selectedLabelBins = if (selectedLabelBins.any { rawValue(it, "code").equals(code, true) })
                selectedLabelBins.filterNot { rawValue(it, "code").equals(code, true) }
            else selectedLabelBins + row
            if (binCode.equals(code, true)) { binCode = ""; bin = null }
        },
    )
    if (showBinPicker && labelMode != BinLabelMode.Single) InquiryPickerDialog(
        if (labelMode == BinLabelMode.Bulk) "Yazdırılacak raflar · ${visibleZoneBins.size}" else "Raf seç · $location",
        binChoices, onDismiss = { showBinPicker = false },
        onPick = { if (labelMode == BinLabelMode.Single) { binCode = it; bin = null; status = "" }; showBinPicker = false },
    )
    if (showLabelPrintOptions) BinLabelPrintSheet(
        title = when (labelMode) {
            BinLabelMode.Single -> "Raf etiketi yazdır"
            BinLabelMode.Bulk -> "Toplu raf etiketi"
            BinLabelMode.Zone -> "Alan etiketi yazdır"
        }, summary = targetSummary,
        targetCount = if (labelMode == BinLabelMode.Zone) 1 else targetRows.size,
        areaOnly = labelMode == BinLabelMode.Zone,
        copies = labelCopies, onCopies = { labelCopies = it },
        documentOutput = documentOutput, onDocumentOutput = { documentOutput = it },
        printing = printing, status = status,
        onDismiss = { if (!printing) showLabelPrintOptions = false },
        onPrint = {
            if (documentOutput && labelMode != BinLabelMode.Zone) {
                runCatching { printBinDocuments(context, targetRows.toList(), "Raf-$location") }
                    .onFailure { status = "HATA: Belge açılamadı: ${it.message}" }
            } else when (labelMode) {
                BinLabelMode.Single -> printBinRows(selectedLabelBins)
                BinLabelMode.Bulk -> printBinRows(visibleZoneBins)
                BinLabelMode.Zone -> printZoneOwnLabel()
            }
        },
    )
}

/** Format an item quantity with up to 2 decimals, stripping trailing zeros. */
internal fun fmtItemQty(q: Double): String {
    if (q.isNaN()) return "0"
    return if (q == q.toLong().toDouble()) q.toLong().toString() else "%.2f".format(q).trimEnd('0').trimEnd('.')
}

/** Compact stock tile used by ItemInquiry — label on top, qty bold, uom small. */
@Composable
private fun StockTile(label: String, qty: Double, uom: String, accent: Color, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(10.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(fmtItemQty(qty), fontWeight = FontWeight.Bold, fontSize = 16.sp, color = accent)
            Text(uom.ifBlank { "—" }, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * Ambar Hareketleri (Warehouse Entries) — terminalden doğrulama ekranı.
 * Ad-Hoc / register sonrası "taşındı mı?" sorusunun cevabı: bin/ürün/lot
 * filtresiyle son kayıtlar, +/- renkli miktarlarla listelenir.
 */
@Composable
fun WhseEntriesModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var binFilter by remember { mutableStateOf("") }
    var itemFilter by remember { mutableStateOf("") }
    var lotFilter by remember { mutableStateOf("") }
    // Filtre bölümü varsayılan KAPALI: ekran açılır açılmaz liste görünsün.
    var filtersOpen by remember { mutableStateOf(false) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Hareketler yükleniyor..."
            fun eq(field: String, v: String): String? =
                v.trim().takeIf { it.isNotBlank() }?.let { "$field eq '${it.replace("'", "''")}'" }
            val filter = buildODataFilter(eq("binCode", binFilter), eq("itemNo", itemFilter), eq("lotNo", lotFilter))
            val r = BcApi.get(context, "warehouseEntries?\$top=50&\$orderby=entryNo desc$filter")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Hareketler alınamadı (HTTP ${r.httpCode})" +
                    (if (r.httpCode == 400 || r.httpCode == 404) " — warehouseEntries için BC publish gerekli olabilir" else "")
                else if (rows.isEmpty()) "BOŞ: Filtreye uyan hareket yok"
                else "TAMAM: ${rows.size} kayıt (en yeni üstte)"
        }
    }
    LaunchedEffect(Unit) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Ambar Hareketleri", fontWeight = FontWeight.Bold, fontSize = 17.sp)
            Spacer(Modifier.weight(1f))
            OutlinedButton(
                onClick = { load() },
                enabled = !loading,
                shape = RoundedCornerShape(50),
                contentPadding = PaddingValues(horizontal = 14.dp),
            ) { WmsRefreshLabel(loading, compact = true) }
        }
        Spacer(Modifier.height(8.dp))
        // Filtreler: ScanField'ler kendi OK + kamera butonlarını taşıdığı için
        // yan yana iki tanesi ekrana sığmıyordu (etiketler dikey harflere
        // bölünüyordu). Her biri TAM GENİŞLİK, alt alta; hepsi katlanabilir
        // bölümde — filtre kullanılmadığında liste tüm ekranı kullanır.
        val hasFilter = binFilter.isNotBlank() || itemFilter.isNotBlank() || lotFilter.isNotBlank()
        Row(
            Modifier.fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .clickable { filtersOpen = !filtersOpen }
                .padding(vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                if (hasFilter) "Filtreler · açık" else "Filtrele",
                fontSize = 13.sp,
                fontWeight = if (hasFilter) FontWeight.SemiBold else FontWeight.Normal,
                color = if (hasFilter) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (hasFilter) {
                Spacer(Modifier.width(8.dp))
                // Aktif filtreleri özetle — bölüm kapalıyken de görünsün.
                Text(
                    listOfNotNull(
                        binFilter.takeIf { it.isNotBlank() }?.let { "Bin: $it" },
                        itemFilter.takeIf { it.isNotBlank() }?.let { "Ürün: $it" },
                        lotFilter.takeIf { it.isNotBlank() }?.let { "Lot: $it" },
                    ).joinToString(" · "),
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    modifier = Modifier.weight(1f),
                )
            } else Spacer(Modifier.weight(1f))
            if (hasFilter) {
                TextButton(onClick = { binFilter = ""; itemFilter = ""; lotFilter = ""; load() }) {
                    Text("Temizle", fontSize = 12.sp)
                }
            }
            Text(if (filtersOpen) "▲" else "▼", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (filtersOpen) {
            Spacer(Modifier.height(6.dp))
            ScanField("Bin", binFilter, { binFilter = it }, modifier = Modifier.fillMaxWidth(),
                onScanned = { binFilter = BarcodeIntentResolver.resolve(it).value; load() })
            Spacer(Modifier.height(6.dp))
            ScanField("Ürün", itemFilter, { itemFilter = it }, modifier = Modifier.fillMaxWidth(),
                onScanned = {
                    val res = BarcodeIntentResolver.resolve(it)
                    itemFilter = (res.itemNo ?: res.value); load()
                })
            Spacer(Modifier.height(6.dp))
            ScanField("Lot", lotFilter, { lotFilter = it }, modifier = Modifier.fillMaxWidth(),
                onScanned = { lotFilter = BarcodeIntentResolver.resolve(it).value; load() })
            Spacer(Modifier.height(8.dp))
            Button(
                onClick = { load(); filtersOpen = false },
                enabled = !loading,
                modifier = Modifier.fillMaxWidth().height(46.dp),
            ) { Text("Ara") }
        }
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { e ->
                val qty = e.optDouble("quantity", 0.0)
                val positive = qty >= 0
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(10.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                "${e.optString("itemNo")} · ${firstValue(e, "entryType")}",
                                fontWeight = FontWeight.SemiBold, fontSize = 13.sp,
                            )
                            Text(
                                (if (positive) "+" else "") + fmtItemQty(qty),
                                fontWeight = FontWeight.Bold, fontSize = 15.sp,
                                color = if (positive) Color(0xFF2E7D32) else Color(0xFFB71C1C),
                            )
                        }
                        Text(
                            buildList {
                                add("📍 ${rawValue(e, "binCode").ifBlank { "—" }}")
                                rawValue(e, "zoneCode").takeIf { it.isNotBlank() }?.let { add(it) }
                                rawValue(e, "lotNo").takeIf { it.isNotBlank() }?.let { add("Lot $it") }
                                rawValue(e, "lpNo").takeIf { it.isNotBlank() }?.let { add("🧺 $it") }
                                add("#${e.optInt("entryNo")}")
                                rawValue(e, "registeringDate").takeIf { it.isNotBlank() }?.let { add(it) }
                            }.joinToString(" · "),
                            fontSize = 11.sp, color = Color.Gray,
                        )
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Kayıt yok. Filtreyi değiştirin ya da 🔄 ile yenileyin.") }
        }
    }
}

/** One tappable line: small label, chosen value in bold, chevron; optional clear. */
@Composable
internal fun SelectorRow(
    label: String,
    value: String,
    hint: String,
    placeholder: String,
    enabled: Boolean,
    onClick: () -> Unit,
    onClear: (() -> Unit)? = null,
) {
    Surface(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = if (enabled) 0.6f else 0.3f),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    value.ifBlank { placeholder },
                    fontWeight = if (value.isBlank()) FontWeight.Normal else FontWeight.Bold,
                    fontSize = 16.sp,
                    color = if (value.isBlank()) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                )
                if (value.isNotBlank() && hint.isNotBlank()) Text(hint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            }
            if (onClear != null) {
                TextButton(onClick = onClear, enabled = enabled) { Text("Temizle", fontSize = 12.sp) }
            } else {
                Text("›", fontSize = 22.sp, color = MaterialTheme.colorScheme.primary)
            }
        }
    }
}

/**
 * Searchable code list for the inquiry screens: type part of the code or
 * name to filter, tap a row to pick it.
 */
@Composable
internal fun InquiryPickerDialog(
    title: String,
    items: List<Pair<String, String>>,
    onDismiss: () -> Unit,
    onPick: (String) -> Unit,
) {
    var query by remember { mutableStateOf("") }
    val visible = remember(query, items) {
        val q = query.trim()
        if (q.isBlank()) items else items.filter { it.first.contains(q, ignoreCase = true) || it.second.contains(q, ignoreCase = true) }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(Modifier.fillMaxWidth().heightIn(max = 420.dp)) {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    singleLine = true,
                    label = { Text("Kod, bölge veya açıklama ara") },
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(8.dp))
                if (visible.isEmpty()) Text("Eşleşen kayıt yok. Aramayı değiştirin.")
                Text("${visible.size} kayıt", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                LazyColumn(Modifier.fillMaxWidth().weight(1f, fill = false)) {
                    items(visible, key = { it.first }) { entry ->
                        Column(
                            Modifier.fillMaxWidth().clickable { onPick(entry.first) }.padding(vertical = 10.dp, horizontal = 4.dp),
                        ) {
                            Text(entry.first, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
                            if (entry.second.isNotBlank()) Text(entry.second, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        HorizontalDivider()
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("Kapat") } },
    )
}

@Composable
internal fun InquiryMultiBinPickerDialog(
    title: String,
    rows: List<JSONObject>,
    selectedCodes: Set<String>,
    onDismiss: () -> Unit,
    onToggle: (JSONObject) -> Unit,
) {
    var query by remember { mutableStateOf("") }
    val visible = remember(query, rows) {
        val q = query.trim()
        if (q.isBlank()) rows else rows.filter {
            rawValue(it, "code").contains(q, ignoreCase = true) ||
                rawValue(it, "description").contains(q, ignoreCase = true)
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(Modifier.fillMaxWidth().heightIn(max = 420.dp)) {
                OutlinedTextField(query, { query = it }, label = { Text("Raf kodu veya açıklama ara") },
                    singleLine = true, modifier = Modifier.fillMaxWidth())
                Text("${selectedCodes.size} raf seçildi", color = MaterialTheme.colorScheme.primary,
                    style = MaterialTheme.typography.bodySmall)
                LazyColumn(Modifier.fillMaxWidth().weight(1f, fill = false)) {
                    items(visible, key = { rawValue(it, "code") }) { row ->
                        val code = rawValue(row, "code")
                        Row(Modifier.fillMaxWidth().clickable { onToggle(row) }.padding(vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(checked = selectedCodes.any { it.equals(code, true) },
                                onCheckedChange = { onToggle(row) })
                            Column {
                                Text(code, fontWeight = FontWeight.Bold)
                                rawValue(row, "description").takeIf { it.isNotBlank() }?.let {
                                    Text(it, style = MaterialTheme.typography.bodySmall)
                                }
                            }
                        }
                        HorizontalDivider()
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Tamam") } },
    )
}
