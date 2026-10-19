package com.dynops.bcwms.feature

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.ui.expiryDateIsTodayOrFuture
import com.dynops.bcwms.ui.toFiniteDoubleOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import kotlin.math.abs

/**
 * BADE (14 Eki 2026): karma palet. Birden çok ürün aynı fiziksel paletlerde gelir
 * (ör. AB.02316 + AB.02317, 4 palet). Her ürün kendi lotuyla tek mal kabul
 * satırında kalır; paletler boş LP taslağı olarak hazırlanır ve ürünler Mal
 * Kabulü Kaydet ile LP'lere yazılır (BC receipts.createMixedLPDistribution).
 */
internal data class MixedReceiptLineEntry(
    val lineNo: Int,
    val itemNo: String,
    val description: String,
    val uom: String,
    val outstanding: Double,
    val expectedQty: Double,
    val lotRequired: Boolean = false,
    val expiryEnabled: Boolean = false,
    val expiryRequired: Boolean = false,
    val lotNo: String = "",
    val supplierLotNo: String = "",
    val expiryDate: String = "",
)

internal const val MIXED_PALLET_MAX = 200

internal fun mixedReceiptLineEntry(line: JSONObject): MixedReceiptLineEntry {
    val outstanding = (line.optDouble("quantity", 0.0) - line.optDouble("qtyReceived", 0.0)).coerceAtLeast(0.0)
    return MixedReceiptLineEntry(
        lineNo = line.optInt("lineNo"),
        itemNo = line.optString("itemNo"),
        description = line.optString("description"),
        uom = line.optString("unitOfMeasureCode"),
        outstanding = outstanding,
        expectedQty = outstanding,
        lotRequired = line.optBoolean("lotRequired"),
        expiryEnabled = line.optBoolean("expirationDateEnabled"),
        expiryRequired = line.optBoolean("expirationDateRequired"),
        lotNo = line.optString("lotNo"),
        supplierLotNo = line.optString("supplierLotNo"),
        expiryDate = bcDateOrBlank(line.optString("expiryDate")),
    )
}

/**
 * Karma palete seçilebilecek satırlar: açık miktarı olan, henüz palete dağıtılmamış,
 * seri takipsiz ve miktarıyla başka bir LP'ye bağlı olmayan ürünler (BC bunları reddeder).
 */
internal fun mixedPalletCandidates(lines: List<JSONObject>): List<JSONObject> = lines.filter { line ->
    (line.optDouble("quantity", 0.0) - line.optDouble("qtyReceived", 0.0)) > 0.0 &&
        line.optInt("bulkLpCount", 0) == 0 &&
        !line.optBoolean("serialRequired") &&
        !(line.optString("licensePlateNo").isNotBlank() && line.optDouble("qtyToReceive", 0.0) > 0.0)
}

/**
 * Bir ürünün kabul miktarının paletlere payı. Tam sayılı toplam her zaman tam sayı
 * paylara bölünür, artan ilk paletlere birer birer gider; karma palette bir ürünün
 * bazı paletlerde 0 olması geçerlidir (3 / 4 = 1, 1, 1, 0). Ondalıklı toplam Palet
 * LP'deki gibi 5 basamakla bölünür.
 */
internal fun mixedLineShares(totalQty: Double, palletCount: Int): List<Double> {
    if (!totalQty.isFinite() || totalQty <= 0.0 || palletCount !in 1..MIXED_PALLET_MAX) return emptyList()
    val total = java.math.BigDecimal.valueOf(totalQty)
    if (total.stripTrailingZeros().scale() > 0) return equalBulkLpQuantities(totalQty, palletCount)
    val (share, remainder) = total.divideAndRemainder(java.math.BigDecimal.valueOf(palletCount.toLong()))
    return List(palletCount) { index ->
        (if (index < remainder.toInt()) share.add(java.math.BigDecimal.ONE) else share).toDouble()
    }
}

/** Her ürünün kabul miktarı paletlere ayrı ayrı eşit bölünür. */
internal fun mixedEqualSplit(expected: Map<Int, Double>, palletCount: Int): List<Map<Int, Double>> {
    if (palletCount !in 1..MIXED_PALLET_MAX || expected.isEmpty()) return emptyList()
    val perLine = expected.mapValues { (_, qty) -> mixedLineShares(qty, palletCount) }
    if (perLine.values.any { it.size != palletCount }) return emptyList()
    return List(palletCount) { index -> perLine.mapValues { (_, shares) -> shares[index] } }
}

internal fun mixedDistributionValidation(
    lines: List<MixedReceiptLineEntry>,
    pallets: List<Map<Int, Double>>,
    today: LocalDate = LocalDate.now(),
): String? {
    if (lines.size < 2) return "Karma palet için en az iki ürün seçin."
    lines.forEach { line ->
        if (!line.expectedQty.isFinite() || line.expectedQty <= 0.0) return "${line.itemNo} için kabul miktarı girin."
        if (line.expectedQty - line.outstanding > 0.00001) return "${line.itemNo} kabul miktarı açık miktarı (${fmtMixedQty(line.outstanding)}) aşamaz."
        if (line.lotNo.trim().length > 50 || line.supplierLotNo.trim().length > 50)
            return "${line.itemNo}: lot numaraları en fazla 50 karakter olabilir."
        if (line.expiryRequired && line.expiryDate.isBlank()) return "${line.itemNo} için SKT girin."
        if (line.expiryDate.isNotBlank()) {
            val normalized = normalizedBulkExpiryDate(line.expiryDate) ?: return "${line.itemNo} için geçerli bir SKT girin."
            if (!expiryDateIsTodayOrFuture(normalized, today)) return "${line.itemNo}: geçmiş SKT'li ürün mal kabul edilemez."
        }
    }
    if (pallets.isEmpty()) return "Palet sayısını girip Eşit Böl'e basın."
    if (pallets.size > MIXED_PALLET_MAX) return "Tek işlemde en fazla $MIXED_PALLET_MAX palet hazırlanabilir."
    pallets.forEachIndexed { index, pallet ->
        if (pallet.values.any { !it.isFinite() || it < 0.0 }) return "${index + 1}. palette geçersiz miktar var."
        if (lines.sumOf { pallet[it.lineNo] ?: 0.0 } <= 0.0) return "${index + 1}. palet boş. Her palete en az bir ürün girin."
    }
    lines.forEach { line ->
        val total = pallets.sumOf { it[line.lineNo] ?: 0.0 }
        if (abs(total - line.expectedQty) > 0.00001)
            return "${line.itemNo}: paletlere dağıtılan ${fmtMixedQty(total)}, kabul miktarı ${fmtMixedQty(line.expectedQty)} ${line.uom}."
    }
    return null
}

/** BC receipts.createMixedLPDistribution gövdesindeki distributionJson. */
internal fun mixedDistributionJson(lines: List<MixedReceiptLineEntry>, pallets: List<Map<Int, Double>>): String =
    JSONObject().apply {
        put("lines", JSONArray().apply {
            lines.forEach { line ->
                put(JSONObject().apply {
                    put("lineNo", line.lineNo)
                    put("expectedQty", line.expectedQty)
                    put("lotNo", if (line.lotRequired) line.lotNo.trim() else "")
                    put("supplierLotNo", if (line.lotRequired) line.supplierLotNo.trim() else "")
                    put("expiryDate", normalizedBulkExpiryDate(line.expiryDate).orEmpty())
                })
            }
        })
        put("pallets", JSONArray().apply {
            pallets.forEach { pallet ->
                put(JSONObject().apply {
                    put("items", JSONArray().apply {
                        lines.forEach { line ->
                            val qty = pallet[line.lineNo] ?: 0.0
                            if (qty > 0.0) put(JSONObject().apply {
                                put("lineNo", line.lineNo)
                                put("quantity", qty)
                            })
                        }
                    })
                })
            }
        })
    }.toString()

/** cancelLPDistribution yanıtındaki geri alınan satır numaraları. */
internal fun cancelledDistributionLineNos(responseValue: String): Set<Int> = runCatching {
    val lineNos = JSONObject(responseValue).optJSONArray("lineNos") ?: JSONArray()
    List(lineNos.length()) { lineNos.optInt(it) }.filter { it > 0 }.toSet()
}.getOrDefault(emptySet())

internal fun fmtMixedQty(value: Double): String =
    if (value == value.toLong().toDouble()) value.toLong().toString()
    else java.math.BigDecimal.valueOf(value).setScale(5, java.math.RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()

private fun mixedNumericText(value: String): String =
    value.filter { it.isDigit() || it == '.' || it == ',' }.replace(',', '.')

@Composable
internal fun MixedReceiptLinePicker(
    lines: List<JSONObject>,
    onDismiss: () -> Unit,
    onConfirm: (List<JSONObject>) -> Unit,
) {
    var selected by remember(lines) { mutableStateOf(setOf<Int>()) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Aynı paletlerdeki ürünleri seç") },
        text = {
            Column(
                Modifier.fillMaxWidth().heightIn(max = 430.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    "Birlikte aynı paletlerde gelen ürünleri işaretleyin. Her ürün kendi lotuyla girer, hepsi tek kayıtta kaydedilir.",
                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                lines.forEach { line ->
                    val lineNo = line.optInt("lineNo")
                    val checked = lineNo in selected
                    fun toggle() { selected = if (checked) selected - lineNo else selected + lineNo }
                    Row(
                        Modifier.fillMaxWidth().clickable { toggle() }.testTag("mixed-pick-$lineNo"),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Checkbox(checked = checked, onCheckedChange = { toggle() })
                        Column(Modifier.weight(1f)) {
                            Text("${line.optString("itemNo")} · ${line.optString("description")}", fontWeight = FontWeight.Bold)
                            val outstanding = (line.optDouble("quantity") - line.optDouble("qtyReceived")).coerceAtLeast(0.0)
                            Text("Kalan: ${fmtMixedQty(outstanding)} ${line.optString("unitOfMeasureCode")}", fontSize = 12.sp)
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(lines.filter { it.optInt("lineNo") in selected }) },
                enabled = selected.size >= 2,
            ) { Text("Devam (${selected.size})") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Vazgeç") } },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MixedReceiptLpSheet(
    lines: List<JSONObject>,
    onDismiss: () -> Unit,
    onSubmit: (distributionJson: String, lineNos: List<Int>, palletCount: Int) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val base = remember(lines) { lines.map { mixedReceiptLineEntry(it) } }
    var expectedText by remember(lines) { mutableStateOf(base.associate { it.lineNo to fmtMixedQty(it.outstanding) }) }
    var lotText by remember(lines) { mutableStateOf(base.associate { it.lineNo to it.lotNo }) }
    var supplierText by remember(lines) { mutableStateOf(base.associate { it.lineNo to it.supplierLotNo }) }
    var expiryText by remember(lines) { mutableStateOf(base.associate { it.lineNo to expiryDateForMixedInput(it.expiryDate) }) }
    var palletCountText by remember(lines) { mutableStateOf("") }
    var pallets by remember(lines) { mutableStateOf<List<Map<Int, String>>>(emptyList()) }

    val entries = base.map { line ->
        line.copy(
            expectedQty = expectedText[line.lineNo]?.toFiniteDoubleOrNull() ?: 0.0,
            lotNo = lotText[line.lineNo].orEmpty(),
            supplierLotNo = supplierText[line.lineNo].orEmpty(),
            expiryDate = expiryText[line.lineNo].orEmpty(),
        )
    }
    val palletQuantities = pallets.map { pallet -> pallet.mapValues { (_, text) -> text.toFiniteDoubleOrNull() ?: 0.0 } }
    val validation = mixedDistributionValidation(entries, palletQuantities)
    val palletCount = palletCountText.toIntOrNull() ?: 0
    val split = mixedEqualSplit(entries.associate { it.lineNo to it.expectedQty }, palletCount)
    val canSplit = split.isNotEmpty() && split.all { pallet -> pallet.values.sum() > 0.0 } &&
        entries.all { it.expectedQty > 0.0 && it.expectedQty - it.outstanding <= 0.00001 }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier.fillMaxWidth().fillMaxHeight(0.94f)
                .verticalScroll(rememberScrollState()).imePadding().padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            Text("Karma Palet LP'leri", fontSize = 21.sp, fontWeight = FontWeight.Bold)
            Text(
                "${entries.size} ürün aynı paletlerde. Her ürünün kabul miktarını ve lotunu girin, palet sayısını yazıp Eşit Böl'e basın. " +
                    "Paletlerdeki miktarları gerekirse düzeltin. Ürünler Kaydet'e basınca LP'lere yazılır.",
                fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(10.dp))

            entries.forEach { line ->
                Card(Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text("${line.itemNo} · ${line.description}", fontWeight = FontWeight.Bold)
                        Text("Açık: ${fmtMixedQty(line.outstanding)} ${line.uom}", fontSize = 12.sp)
                        OutlinedTextField(
                            value = expectedText[line.lineNo].orEmpty(),
                            onValueChange = { value -> expectedText = expectedText + (line.lineNo to mixedNumericText(value)) },
                            label = { Text("Kabul miktarı (${line.uom})") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth().testTag("mixed-expected-${line.lineNo}"),
                        )
                        if (line.lotRequired) {
                            Spacer(Modifier.height(6.dp))
                            OutlinedTextField(
                                value = lotText[line.lineNo].orEmpty(),
                                onValueChange = { value -> lotText = lotText + (line.lineNo to value) },
                                label = { Text("İç lot (boşsa sistem üretir)") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth().testTag("mixed-lot-${line.lineNo}"),
                            )
                            Spacer(Modifier.height(6.dp))
                            OutlinedTextField(
                                value = supplierText[line.lineNo].orEmpty(),
                                onValueChange = { value -> supplierText = supplierText + (line.lineNo to value) },
                                label = { Text("Tedarikçi lotu (isteğe bağlı)") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                        if (line.expiryEnabled) {
                            Spacer(Modifier.height(6.dp))
                            BulkExpiryDateField(expiryText[line.lineNo].orEmpty(), line.expiryRequired) { value ->
                                expiryText = expiryText + (line.lineNo to value)
                            }
                        }
                    }
                }
            }

            Text("Paletler", fontWeight = FontWeight.Bold)
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = palletCountText,
                    onValueChange = { value -> palletCountText = value.filter { it.isDigit() }.take(3) },
                    label = { Text("Palet sayısı") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.weight(1f).testTag("mixed-pallet-count"),
                )
                Button(
                    onClick = { pallets = split.map { pallet -> pallet.mapValues { (_, qty) -> fmtMixedQty(qty) } } },
                    enabled = canSplit,
                    modifier = Modifier.testTag("mixed-split"),
                ) { Text("Eşit Böl") }
            }
            Spacer(Modifier.height(8.dp))

            pallets.forEachIndexed { index, pallet ->
                Card(Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Palet ${index + 1}", fontWeight = FontWeight.Bold)
                            Spacer(Modifier.weight(1f))
                            if (pallets.size > 1) TextButton(onClick = {
                                pallets = pallets.filterIndexed { i, _ -> i != index }
                            }) { Text("Kaldır") }
                        }
                        entries.forEach { line ->
                            OutlinedTextField(
                                value = pallet[line.lineNo].orEmpty(),
                                onValueChange = { value ->
                                    pallets = pallets.mapIndexed { i, p -> if (i == index) p + (line.lineNo to mixedNumericText(value)) else p }
                                },
                                label = { Text("${line.itemNo} (${line.uom})") },
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth().padding(top = 4.dp).testTag("mixed-qty-$index-${line.lineNo}"),
                            )
                        }
                    }
                }
            }
            if (pallets.isNotEmpty()) TextButton(
                onClick = { pallets = pallets + listOf(entries.associate { it.lineNo to "" }) },
                enabled = pallets.size < MIXED_PALLET_MAX,
            ) { Text("+ Palet Ekle") }

            if (pallets.isNotEmpty()) {
                entries.forEach { line ->
                    val total = palletQuantities.sumOf { it[line.lineNo] ?: 0.0 }
                    val ok = abs(total - line.expectedQty) <= 0.00001
                    Text(
                        "${line.itemNo}: paletlerde ${fmtMixedQty(total)} / ${fmtMixedQty(line.expectedQty)} ${line.uom}",
                        fontSize = 13.sp,
                        color = if (ok) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error,
                    )
                }
            }
            if (validation != null && pallets.isNotEmpty()) Text(
                validation,
                color = MaterialTheme.colorScheme.error,
                fontSize = 13.sp,
                modifier = Modifier.padding(vertical = 8.dp),
            )
            Row(Modifier.padding(top = 8.dp, bottom = 18.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("İptal") }
                Button(
                    onClick = { onSubmit(mixedDistributionJson(entries, palletQuantities), entries.map { it.lineNo }, pallets.size) },
                    enabled = validation == null,
                    modifier = Modifier.weight(1f).testTag("mixed-submit"),
                ) { Text("${pallets.size} Karma LP Hazırla") }
            }
        }
    }
}

/** BC'den gelen ISO SKT, alanda GG.AA.YYYY olarak gösterilir (Palet LP ile aynı). */
private fun expiryDateForMixedInput(value: String): String =
    if (value.isBlank()) "" else com.dynops.bcwms.ui.expiryDateForDisplay(value)
