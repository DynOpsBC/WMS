package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.ui.StatusText
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/** One received line on the goods-receipt label sheet; [copies] 0 means "no label". */
internal data class ReceiptLabelRow(
    val itemNo: String,
    val description: String,
    val lotNo: String,
    val supplierLotNo: String,
    val quantity: Double,
    val unit: String,
    val copies: Int = 1,
    /** Ana birim karşılığı (KG ile alınan ADET ürün); birimler aynıysa boş. */
    val baseQuantity: Double = 0.0,
    val baseUnit: String = "",
)

internal const val RECEIPT_LABEL_COPIES_MAX = 50
internal const val RECEIPT_LABELS_PER_JOB = 10

/** The lines being posted (receiptLines rows), one label row each, one copy by default. */
internal fun receiptLabelRows(postLines: List<JSONObject>): List<ReceiptLabelRow> = postLines
    .filter { it.optString("itemNo").isNotBlank() && it.optDouble("qtyToReceive", 0.0) > 0.0 }
    .map {
        ReceiptLabelRow(
            itemNo = it.optString("itemNo").trim(),
            description = it.optString("description").trim(),
            lotNo = it.optString("lotNo").trim(),
            supplierLotNo = it.optString("supplierLotNo").trim(),
            quantity = it.optDouble("qtyToReceive", 0.0),
            unit = it.optString("unitOfMeasureCode").trim(),
            baseQuantity = receiptBaseQuantity(it, it.optDouble("qtyToReceive", 0.0)) ?: 0.0,
            baseUnit = if (receiptBaseQuantity(it, 1.0) != null) it.optString("baseUnitOfMeasure").trim() else "",
        )
    }

/**
 * DKC (20 Kas 2026): satır birimi ana birimden farklıysa (KG ile alınan, ana
 * birimi ADET olan ürün) miktarın ana birim karşılığı; aynıysa ya da çevrim
 * bilinmiyorsa null.
 */
internal fun receiptBaseQuantity(line: JSONObject, quantity: Double): Double? {
    val unit = line.optString("unitOfMeasureCode").trim()
    val base = line.optString("baseUnitOfMeasure").trim()
    val factor = line.optDouble("qtyPerUnitOfMeasure", 0.0)
    if (base.isEmpty() || base == "null" || unit.equals(base, ignoreCase = true)) return null
    if (!factor.isFinite() || factor <= 0.0 || factor == 1.0 && unit.isEmpty()) return null
    return quantity * factor
}

/**
 * Adet karşılığı ekranda/etikette: KG ↔ ADET çevrimi (ör. 211,8644) BC'nin 5
 * ondalığına sığmadığı için 3.000.000 ADET 2.999.999,9993 olarak saklanır; adet
 * tam sayıya 0,01'den yakınsa tam sayı gösterilir.
 */
internal fun displayBaseQty(value: Double): Double {
    val whole = Math.rint(value)
    return if (Math.abs(value - whole) < 0.01) whole else value
}

/** Grid hücresi: "70.500 ADET"; çevrim yoksa boş. */
internal fun receiptBaseQtyText(line: JSONObject, quantity: Double): String =
    receiptBaseQuantity(line, quantity)?.let { receiptLabelQtyText(displayBaseQty(it), line.optString("baseUnitOfMeasure")) }.orEmpty()

/** Etiket miktarı: ana birim önde, alış birimi parantezde; 30 karakteri aşarsa yalnız ana birim. */
internal fun receiptLabelQuantityText(row: ReceiptLabelRow): String {
    if (row.baseUnit.isBlank()) return receiptLabelQtyText(row.quantity, row.unit)
    val base = receiptLabelQtyText(displayBaseQty(row.baseQuantity), row.baseUnit)
    val both = "$base (${receiptLabelQtyText(row.quantity, row.unit)})"
    return if (both.length <= 30) both else base.take(30)
}

/** Turkish quantity text for the label: 25.060 KG, 12,5 KG, 1.234,567 ADET. */
internal fun receiptLabelQtyText(quantity: Double, unit: String): String {
    val scaled = BigDecimal.valueOf(quantity).setScale(3, RoundingMode.HALF_UP).stripTrailingZeros()
    val plain = scaled.toPlainString()
    val intPart = plain.substringBefore('.')
    val fraction = plain.substringAfter('.', "")
    val negative = intPart.startsWith("-")
    val digits = intPart.removePrefix("-")
    val grouped = digits.reversed().chunked(3).joinToString(".").reversed()
    val number = (if (negative) "-" else "") + grouped + if (fraction.isNotEmpty()) ",$fraction" else ""
    return listOf(number, unit.trim()).filter { it.isNotEmpty() }.joinToString(" ")
}

/**
 * Splits the requested labels into print jobs of at most [perJob] labels, keeping the line order.
 * A line with more copies than fit in one job continues in the next job.
 */
internal fun receiptLabelBatches(rows: List<ReceiptLabelRow>, perJob: Int = RECEIPT_LABELS_PER_JOB): List<List<ReceiptLabelRow>> {
    val batches = mutableListOf<List<ReceiptLabelRow>>()
    var current = mutableListOf<ReceiptLabelRow>()
    var room = perJob
    for (row in rows) {
        var left = row.copies.coerceIn(0, RECEIPT_LABEL_COPIES_MAX)
        while (left > 0) {
            val take = minOf(left, room)
            current.add(row.copy(copies = take))
            left -= take
            room -= take
            if (room == 0) {
                batches.add(current)
                current = mutableListOf()
                room = perJob
            }
        }
    }
    if (current.isNotEmpty()) batches.add(current)
    return batches
}

internal fun receiptLabelRowsJson(batch: List<ReceiptLabelRow>, receiptNo: String, dateText: String): String =
    JSONArray().apply {
        batch.forEach { row ->
            put(JSONObject().apply {
                put("itemNo", row.itemNo)
                put("lotNo", row.lotNo)
                put("supplierLotNo", row.supplierLotNo)
                put("quantityText", receiptLabelQuantityText(row))
                put("receiptNo", receiptNo)
                put("dateText", dateText)
                put("copies", row.copies)
            })
        }
    }.toString()

/** BC older than 1.14.2.29 has no printReceiptLabels action. */
internal fun receiptLabelMissingBackend(httpCode: Int, body: String): Boolean =
    (httpCode == 404 || httpCode == 400) &&
        (body.contains("printReceiptLabels", ignoreCase = true) || body.contains("BadRequest_MethodNotAllowed", ignoreCase = true) ||
            body.contains("No HTTP resource", ignoreCase = true) || body.contains("Microsoft.NAV.printReceiptLabels", ignoreCase = true))

/**
 * Goods-receipt labels after a terminal receipt (DKÇ, next to the A4 receipt document): the
 * received lines with one label each by default; the operator changes the counts and prints.
 * Nothing is retried automatically: a lost answer may still have printed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReceiptLabelSheet(receiptNo: String, initialRows: List<ReceiptLabelRow>, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember(receiptNo) { mutableStateOf(initialRows) }
    var busy by remember { mutableStateOf(false) }
    var printed by remember(receiptNo) { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    val total = rows.sumOf { it.copies }
    val printer = getDefaultPrinter(context)

    ModalBottomSheet(
        onDismissRequest = { if (!busy) onDismiss() },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = { it != SheetValue.Hidden || !busy }),
    ) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Mal kabul etiketleri", style = MaterialTheme.typography.titleLarge)
            Text(
                "Belge: $receiptNo · Etiket yazıcısı: ${printer.ifBlank { "seçilmedi" }}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text("Her satır için kaç etiket basılacağını seçin. 0 olan satıra etiket basılmaz.", fontSize = 13.sp)
            StatusText(status)
            LazyColumn(Modifier.weight(1f, fill = false), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                itemsIndexed(rows) { index, row ->
                    Card(Modifier.fillMaxWidth()) {
                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(row.itemNo, fontWeight = FontWeight.Bold)
                                if (row.description.isNotBlank() && row.description != row.itemNo) Text(row.description, fontSize = 13.sp, maxLines = 2)
                                Text(
                                    listOf(
                                        receiptLabelQtyText(row.quantity, row.unit),
                                        row.lotNo.takeIf { it.isNotBlank() }?.let { "Lot: $it" },
                                    ).filterNotNull().joinToString(" · "),
                                    fontSize = 12.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            OutlinedButton(
                                onClick = { rows = rows.toMutableList().also { it[index] = row.copy(copies = (row.copies - 1).coerceAtLeast(0)) } },
                                enabled = !busy && row.copies > 0,
                                modifier = Modifier.size(44.dp),
                                contentPadding = PaddingValues(0.dp),
                            ) { Text("−", fontSize = 20.sp) }
                            Text("${row.copies}", fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.width(40.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                            OutlinedButton(
                                onClick = { rows = rows.toMutableList().also { it[index] = row.copy(copies = (row.copies + 1).coerceAtMost(RECEIPT_LABEL_COPIES_MAX)) } },
                                enabled = !busy && row.copies < RECEIPT_LABEL_COPIES_MAX,
                                modifier = Modifier.size(44.dp),
                                contentPadding = PaddingValues(0.dp),
                            ) { Text("+", fontSize = 20.sp) }
                        }
                    }
                }
            }
            Button(
                enabled = !busy && total > 0,
                modifier = Modifier.fillMaxWidth().height(52.dp),
                onClick = {
                    if (printer.isBlank()) {
                        status = "HATA: Etiket yazıcısı seçilmedi. Üstteki yazıcı şeridinden etiket yazıcısını seçin."
                        return@Button
                    }
                    scope.launch {
                        busy = true
                        val date = LocalDate.now().format(DateTimeFormatter.ofPattern("dd.MM.yyyy"))
                        val batches = receiptLabelBatches(rows)
                        var sent = 0
                        var failure = ""
                        for ((i, batch) in batches.withIndex()) {
                            status = "Etiketler gönderiliyor: ${i + 1}/${batches.size}"
                            val body = JSONObject()
                                .put("rowsJson", receiptLabelRowsJson(batch, receiptNo, date))
                                .put("printerId", printer)
                                .toString()
                            val r = BcApi.boundAction(context, "items", batch.first().itemNo, "printReceiptLabels", body)
                            if (!r.ok) {
                                failure = if (receiptLabelMissingBackend(r.httpCode, r.body))
                                    "Business Central güncellemesi gerekli (BCWMS 1.14.2.29)."
                                else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
                                break
                            }
                            sent += batch.sumOf { it.copies }
                        }
                        status = when {
                            failure.isEmpty() -> "TAMAM: $sent etiket $printer yazıcısına gönderildi."
                            sent > 0 -> "UYARI: $total etiketin $sent adedi gönderildi, kalanı gönderilemedi: $failure Çıktıları kontrol etmeden tekrar basmayın."
                            else -> "HATA: Etiket gönderilemedi: $failure"
                        }
                        if (failure.isEmpty()) printed = true
                        busy = false
                    }
                },
            ) { Text(if (printed) "Tekrar Yazdır ($total)" else "Etiketleri Yazdır ($total)", fontWeight = FontWeight.Bold) }
            TextButton(onClick = onDismiss, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(if (printed) "Devam Et" else "Etiketsiz Devam Et") }
        }
    }
}

/**
 * DKC (20 Kas 2026): satırdan alınabilecek en çok miktar. BC fazla teslim alma
 * toleransını (Over-Receipt Code) hesaba katıp maxQtyToReceive gönderir; eski BC'de
 * alan yoksa kalan miktar (sipariş − alınan).
 */
internal fun receiptMaxQty(line: JSONObject): Double =
    if (line.has("maxQtyToReceive")) line.optDouble("maxQtyToReceive", 0.0).coerceAtLeast(0.0)
    else (line.optDouble("quantity", 0.0) - line.optDouble("qtyReceived", 0.0)).coerceAtLeast(0.0)

