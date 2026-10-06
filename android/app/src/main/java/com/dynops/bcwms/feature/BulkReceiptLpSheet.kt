package com.dynops.bcwms.feature

import com.dynops.bcwms.ui.toFiniteDoubleOrNull

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
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
import com.dynops.bcwms.ui.expiryDateForDisplay
import com.dynops.bcwms.ui.expiryDateIsTodayOrFuture
import com.dynops.bcwms.ui.formatExpiryDateInput
import com.dynops.bcwms.ui.normalizeExpiryDate
import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlin.math.abs

internal data class BulkReceiptLpRow(
    val groupId: String,
    val quantity: Double,
    val lotNo: String,
    val supplierLotNo: String,
    val expiryDate: String,
)

internal data class BulkReceiptLotGroup(
    val groupId: String,
    val lotNo: String = "",
    val supplierLotNo: String = "",
    val expiryDate: String = "",
)

private data class ManualBulkLpDraft(
    val id: Int,
    val quantity: String,
    val groupId: String = COMMON_RECEIPT_LOT_GROUP,
)

private const val COMMON_RECEIPT_LOT_GROUP = "RECEIPT"

/** Group order also keeps a previously reserved lot in the first group. */
internal fun withGroupedBulkReceiptTracking(
    rows: List<BulkReceiptLpRow>,
    groups: List<BulkReceiptLotGroup>,
): List<BulkReceiptLpRow> {
    require(groups.map { it.groupId }.distinct().size == groups.size)
    require(rows.all { row -> groups.any { it.groupId == row.groupId } })
    return groups.flatMap { group ->
        rows.filter { it.groupId == group.groupId }.map { row ->
            row.copy(lotNo = group.lotNo, supplierLotNo = group.supplierLotNo, expiryDate = group.expiryDate)
        }
    }
}

internal fun bulkLpRowsJson(rows: List<BulkReceiptLpRow>): String = JSONArray().apply {
    rows.forEach { row ->
        put(JSONObject().apply {
            put("groupId", row.groupId)
            put("quantity", row.quantity)
            put("lotNo", row.lotNo.trim())
            put("supplierLotNo", row.supplierLotNo.trim())
            put("expiryDate", normalizedBulkExpiryDate(row.expiryDate).orEmpty())
        })
    }
}.toString()

/**
 * BC quantities use five decimal places in this flow. Equal shares are rounded
 * down and the final pallet receives the remainder, so the rows always add up
 * to the exact receipt quantity.
 */
internal fun equalBulkLpQuantities(totalQty: Double, palletCount: Int): List<Double> {
    if (!totalQty.isFinite() || totalQty <= 0.0 || palletCount <= 0 || palletCount > 200) return emptyList()
    val total = BigDecimal.valueOf(totalQty)
    val count = BigDecimal.valueOf(palletCount.toLong())
    val commonShare = total.divide(count, 5, RoundingMode.DOWN)
    val lastShare = total.subtract(commonShare.multiply(BigDecimal.valueOf((palletCount - 1).toLong())))
    return List(palletCount) { index ->
        (if (index == palletCount - 1) lastShare else commonShare).stripTrailingZeros().toDouble()
    }
}

internal fun normalizedBulkExpiryDate(value: String): String? {
    val trimmed = value.trim()
    if (trimmed.isBlank()) return null
    return runCatching {
        LocalDate.parse(trimmed.take(10), DateTimeFormatter.ISO_LOCAL_DATE)
            .format(DateTimeFormatter.ISO_LOCAL_DATE)
    }.getOrNull() ?: normalizeExpiryDate(trimmed)
}

internal fun manualBulkLpValidation(
    maxQty: Double,
    rows: List<BulkReceiptLpRow>,
    expiryRequired: Boolean,
    expectedQty: Double? = null,
    today: LocalDate = LocalDate.now(),
): String? {
    if (!maxQty.isFinite() || maxQty <= 0.0) return "Bu satırda kabul edilecek açık miktar yok."
    if (expectedQty != null && (!expectedQty.isFinite() || expectedQty <= 0.0))
        return "Toplam kabul miktarı sıfırdan büyük olmalıdır."
    if (expectedQty != null && expectedQty - maxQty > 0.00001)
        return "Toplam kabul miktarı açık miktarı aşamaz."
    if (rows.isEmpty()) return "En az bir LP ekleyin."
    if (rows.size > 200) return "Tek işlemde en fazla 200 LP oluşturulabilir."
    if (rows.any { !it.quantity.isFinite() || it.quantity <= 0.0 }) return "Her LP için sıfırdan büyük miktar girin."
    val rowTotal = rows.sumOf { it.quantity }
    if (rowTotal - maxQty > 0.00001) return "LP toplamı açık miktarı aşamaz."
    if (expectedQty != null && abs(rowTotal - expectedQty) > 0.00001)
        return "LP toplamı kabul miktarına eşit olmalıdır."
    if (expiryRequired && rows.any { it.expiryDate.isBlank() }) return "Bu mal kabul için SKT girin."
    val enteredExpiryDates = rows.filter { it.expiryDate.isNotBlank() }
    if (enteredExpiryDates.any { normalizedBulkExpiryDate(it.expiryDate) == null })
        return "Geçerli bir SKT girin."
    if (enteredExpiryDates.any {
            !expiryDateIsTodayOrFuture(normalizedBulkExpiryDate(it.expiryDate), today)
        }) return "Geçmiş SKT'li ürün mal kabul edilemez."
    if (rows.any { it.lotNo.trim().length > 50 || it.supplierLotNo.trim().length > 50 })
        return "Lot numaraları en fazla 50 karakter olabilir."
    val groups = rows.groupBy { it.groupId }
    if (groups.values.any { group -> group.map {
            Triple(it.lotNo.trim().uppercase(), it.supplierLotNo.trim().uppercase(), normalizedBulkExpiryDate(it.expiryDate))
        }.distinct().size > 1 }) return "Aynı lot grubundaki LP'lerin lot bilgileri aynı olmalıdır."
    val internalLots = rows.filter { it.lotNo.isNotBlank() }.groupBy { it.lotNo.trim().uppercase() }
    if (internalLots.values.any { lot -> lot.map { it.supplierLotNo.trim().uppercase() }.filter { it.isNotEmpty() }.distinct().size > 1 })
        return "Aynı iç lot farklı tedarikçi lotlarıyla eşleştirilemez."
    if (internalLots.values.any { lot -> lot.map { normalizedBulkExpiryDate(it.expiryDate) }.distinct().size > 1 })
        return "Aynı iç lot için farklı SKT girilemez."
    return null
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BulkReceiptLpSheet(
    itemNo: String,
    uom: String,
    maxExpectedQty: Double,
    initialLotNo: String,
    initialSupplierLotNo: String,
    initialExpiryDate: String,
    lotRequired: Boolean,
    allowLotGroups: Boolean,
    expiryEnabled: Boolean,
    expiryRequired: Boolean,
    onDismiss: () -> Unit,
    onSubmit: (expectedQty: Double, rows: List<BulkReceiptLpRow>) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var nextLpId by remember { mutableIntStateOf(2) }
    var receiptQtyText by remember(maxExpectedQty) { mutableStateOf(fmtBulkQty(maxExpectedQty)) }
    var palletCountText by remember { mutableStateOf("1") }
    var nextLotGroupId by remember { mutableIntStateOf(2) }
    var lotGroups by remember(initialLotNo, initialSupplierLotNo, initialExpiryDate) {
        mutableStateOf(listOf(BulkReceiptLotGroup(
            COMMON_RECEIPT_LOT_GROUP, initialLotNo, initialSupplierLotNo, expiryDateForDisplay(initialExpiryDate),
        )))
    }
    fun updateLotGroup(id: String, transform: (BulkReceiptLotGroup) -> BulkReceiptLotGroup) {
        lotGroups = lotGroups.map { if (it.groupId == id) transform(it) else it }
    }
    var drafts by remember {
        mutableStateOf(
            listOf(
                ManualBulkLpDraft(
                    id = 1,
                    quantity = "",
                )
            )
        )
    }

    fun updateDraft(id: Int, transform: (ManualBulkLpDraft) -> ManualBulkLpDraft) {
        drafts = drafts.map { if (it.id == id) transform(it) else it }
    }

    val rows = withGroupedBulkReceiptTracking(
        rows = drafts.map { draft ->
            BulkReceiptLpRow(draft.groupId, draft.quantity.toFiniteDoubleOrNull() ?: 0.0, "", "", "")
        },
        groups = lotGroups,
    )
    val expectedQty = receiptQtyText.toFiniteDoubleOrNull() ?: 0.0
    val palletCount = palletCountText.toIntOrNull() ?: 0
    val enteredTotal = rows.sumOf { it.quantity }
    val unusedGroup = lotGroups.indexOfFirst { group -> drafts.none { it.groupId == group.groupId } }
    val validationError = if (unusedGroup >= 0) "Lot grubu ${unusedGroup + 1} için en az bir LP seçin."
    else manualBulkLpValidation(
        maxQty = maxExpectedQty,
        rows = rows,
        expiryRequired = expiryRequired,
        expectedQty = expectedQty,
    )
    val remaining = expectedQty - enteredTotal
    val canSubmit = validationError == null

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier.fillMaxWidth().fillMaxHeight(0.94f)
                .verticalScroll(rememberScrollState()).imePadding().padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            Text("Palet LP'lerini Oluştur", fontSize = 21.sp, fontWeight = FontWeight.Bold)
            Text("$itemNo · Açık: ${fmtBulkQty(maxExpectedQty)} $uom", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            Surface(
                color = MaterialTheme.colorScheme.secondaryContainer,
                shape = RoundedCornerShape(10.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    "Kabul miktarını ve palet sayısını girip Eşit Böl'e dokunun. Burada yalnız boş LP taslakları hazırlanır; ürün, lot ve miktar Mal Kabulü Kaydet başarılı olunca LP'lere yazılır.",
                    modifier = Modifier.padding(10.dp),
                    fontSize = 13.sp,
                )
            }
            Spacer(Modifier.height(10.dp))

            Text("Otomatik dağıtım", fontWeight = FontWeight.Bold)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = receiptQtyText,
                    onValueChange = { receiptQtyText = numericText(it) },
                    label = { Text("Kabul miktarı ($uom)") },
                    supportingText = { Text("En çok ${fmtBulkQty(maxExpectedQty)}") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.weight(1.45f),
                )
                OutlinedTextField(
                    value = palletCountText,
                    onValueChange = { palletCountText = it.filter(Char::isDigit).take(3) },
                    label = { Text("Palet sayısı") },
                    supportingText = { Text("En çok 200") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
            }
            Button(
                onClick = {
                    val quantities = equalBulkLpQuantities(expectedQty, palletCount)
                    val previous = drafts
                    drafts = quantities.mapIndexed { index, quantity ->
                        val existing = previous.getOrNull(index)
                        ManualBulkLpDraft(
                            id = existing?.id ?: nextLpId++,
                            quantity = fmtBulkQty(quantity),
                            groupId = existing?.groupId ?: lotGroups.last().groupId,
                        )
                    }
                },
                enabled = expectedQty > 0.0 && expectedQty <= maxExpectedQty + 0.00001 &&
                    palletCount in 1..200 && equalBulkLpQuantities(expectedQty, palletCount).all { it > 0.0 },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Eşit Böl ve $palletCount LP Hazırla") }
            Spacer(Modifier.height(12.dp))

            if (lotRequired || expiryEnabled) {
                Text("Lot Grupları", fontWeight = FontWeight.Bold)
                Text(
                    "Aynı lotu paylaşan LP'lerde aynı grubu seçin. Bütün gruplar tek mal kabul belgesinde kaydedilir.",
                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                lotGroups.forEachIndexed { index, group ->
                    Card(Modifier.fillMaxWidth().padding(top = 8.dp)) {
                        Column(Modifier.padding(12.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("Lot Grubu ${index + 1}", fontWeight = FontWeight.Bold)
                                Spacer(Modifier.weight(1f))
                                if (index > 0) TextButton(onClick = {
                                    drafts = drafts.map { if (it.groupId == group.groupId) it.copy(groupId = lotGroups.first().groupId) else it }
                                    lotGroups = lotGroups.filterNot { it.groupId == group.groupId }
                                }) { Text("Grubu Kaldır") }
                            }
                            if (lotRequired) {
                                OutlinedTextField(
                                    value = group.lotNo,
                                    onValueChange = { value -> updateLotGroup(group.groupId) { it.copy(lotNo = value) } },
                                    label = { Text("İç lot (boşsa sistem üretir)") },
                                    singleLine = true, modifier = Modifier.fillMaxWidth().testTag("receipt-lot-${group.groupId}"),
                                )
                                Spacer(Modifier.height(6.dp))
                                OutlinedTextField(
                                    value = group.supplierLotNo,
                                    onValueChange = { value -> updateLotGroup(group.groupId) { it.copy(supplierLotNo = value) } },
                                    label = { Text("Tedarikçi lotu (isteğe bağlı)") },
                                    singleLine = true, modifier = Modifier.fillMaxWidth().testTag("receipt-supplier-${group.groupId}"),
                                )
                            }
                            if (expiryEnabled) {
                                Spacer(Modifier.height(6.dp))
                                BulkExpiryDateField(group.expiryDate, expiryRequired) { value ->
                                    updateLotGroup(group.groupId) { it.copy(expiryDate = value) }
                                }
                            }
                            val groupRows = rows.filter { it.groupId == group.groupId }
                            Text("${groupRows.size} LP · ${fmtBulkQty(groupRows.sumOf { it.quantity })} $uom", modifier = Modifier.padding(top = 6.dp))
                        }
                    }
                }
                if (lotRequired && allowLotGroups) {
                    OutlinedButton(
                        onClick = { lotGroups = lotGroups + BulkReceiptLotGroup("LOT-${nextLotGroupId++}") },
                        enabled = lotGroups.size < 200, modifier = Modifier.fillMaxWidth(),
                    ) { Text("+ Lot Grubu Ekle") }
                } else if (lotRequired && !allowLotGroups) {
                    Text("Farklı lot grupları için Business Central eklentisini güncelleyin.", fontSize = 12.sp)
                }
                Spacer(Modifier.height(12.dp))
            }

            drafts.forEachIndexed { index, draft ->
                Card(
                    modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Column(Modifier.padding(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("LP ${index + 1}", fontWeight = FontWeight.Bold)
                            Spacer(Modifier.weight(1f))
                            if (drafts.size > 1) {
                                TextButton(onClick = {
                                    val remainingDrafts = drafts.filterNot { it.id == draft.id }
                                    drafts = remainingDrafts
                                    palletCountText = remainingDrafts.size.toString()
                                }) {
                                    Text("Kaldır")
                                }
                            }
                        }
                        if (lotGroups.size > 1) {
                            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                lotGroups.forEachIndexed { groupIndex, group ->
                                    FilterChip(
                                        selected = draft.groupId == group.groupId,
                                        onClick = { updateDraft(draft.id) { it.copy(groupId = group.groupId) } },
                                        label = { Text("Lot Grubu ${groupIndex + 1}") },
                                    )
                                }
                            }
                        }
                        OutlinedTextField(
                            value = draft.quantity,
                            onValueChange = { value -> updateDraft(draft.id) { it.copy(quantity = numericText(value)) } },
                            label = { Text("Miktar ($uom)") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth().testTag("receipt-lp-${draft.id}-quantity"),
                        )
                    }
                }
            }

            OutlinedButton(
                onClick = {
                    val expandedDrafts = drafts + ManualBulkLpDraft(
                        id = nextLpId++,
                        quantity = "",
                        groupId = lotGroups.last().groupId,
                    )
                    drafts = expandedDrafts
                    palletCountText = expandedDrafts.size.toString()
                },
                enabled = drafts.size < 200,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("+ LP Ekle") }

            Spacer(Modifier.height(8.dp))
            Surface(
                color = if (validationError == null) MaterialTheme.colorScheme.primaryContainer
                else MaterialTheme.colorScheme.surfaceVariant,
                shape = RoundedCornerShape(10.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(Modifier.padding(10.dp)) {
                    Text("${drafts.size} LP · Girilen toplam: ${fmtBulkQty(enteredTotal)} $uom", fontWeight = FontWeight.Bold)
                    Text(
                        "Kabul miktarı: ${fmtBulkQty(expectedQty)} · Dağıtılacak fark: ${fmtBulkQty(remaining)} $uom",
                        fontSize = 12.sp,
                        color = if (remaining < -0.00001) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (validationError != null) {
                        Text(
                            validationError,
                            color = MaterialTheme.colorScheme.error,
                            fontSize = 13.sp,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                }
            }
            Text(
                "LP etiketleri mal kabul başarıyla kaydedildikten sonra yazdırılır.",
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = 8.dp),
            )
            Row(Modifier.padding(bottom = 18.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("İptal") }
                Button(
                    onClick = { onSubmit(expectedQty, rows) },
                    enabled = canSubmit,
                    modifier = Modifier.weight(1f),
                ) { Text("${drafts.size} LP Taslağı Hazırla") }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BulkExpiryDateField(
    value: String,
    required: Boolean,
    onValueChange: (String) -> Unit,
) {
    var showDatePicker by remember { mutableStateOf(false) }
    val normalized = normalizedBulkExpiryDate(value)
    val valid = value.isBlank() || normalized != null
    val notPast = expiryDateIsTodayOrFuture(normalized)

    OutlinedTextField(
        value = value,
        onValueChange = { onValueChange(formatExpiryDateInput(it)) },
        label = { Text(if (required) "SKT (zorunlu)" else "SKT (opsiyonel)") },
        supportingText = { Text("GG.AA.YYYY") },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        trailingIcon = {
            TextButton(onClick = { showDatePicker = true }) { Text("Takvim") }
        },
        isError = (required && value.isBlank()) || !valid || !notPast,
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    when {
        required && value.isBlank() -> BulkDateError("Bu LP için SKT zorunludur.")
        !valid -> BulkDateError("Geçerli bir tarih girin (ör. 31.12.2027).")
        !notPast -> BulkDateError("Geçmiş SKT'li ürün mal kabul edilemez.")
    }

    if (showDatePicker) {
        val today = LocalDate.now()
        val selected = normalized?.let {
            runCatching { LocalDate.parse(it, DateTimeFormatter.ISO_LOCAL_DATE) }.getOrNull()
        } ?: today
        val pickerState = rememberDatePickerState(
            initialSelectedDateMillis = selected.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long): Boolean =
                    !Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate().isBefore(today)

                override fun isSelectableYear(year: Int): Boolean = year >= today.year
            },
        )
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        pickerState.selectedDateMillis?.let { millis ->
                            val iso = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                                .format(DateTimeFormatter.ISO_LOCAL_DATE)
                            onValueChange(expiryDateForDisplay(iso))
                        }
                        showDatePicker = false
                    },
                    enabled = pickerState.selectedDateMillis != null,
                ) { Text("Seç") }
            },
            dismissButton = { TextButton(onClick = { showDatePicker = false }) { Text("Vazgeç") } },
        ) {
            DatePicker(state = pickerState)
        }
    }
}

@Composable
private fun BulkDateError(message: String) {
    Text(message, color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
}

private fun numericText(value: String): String = value.filter { it.isDigit() || it == '.' || it == ',' }.replace(',', '.')
private fun fmtBulkQty(value: Double): String = if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()

@Composable
internal fun BulkReceiptLinePicker(
    lines: List<JSONObject>,
    onDismiss: () -> Unit,
    onSelect: (JSONObject) -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Palet oluşturulacak satırı seç") },
        text = {
            Column(
                Modifier.fillMaxWidth().heightIn(max = 430.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                lines.forEach { line ->
                    OutlinedButton(
                        onClick = { onSelect(line) },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(Modifier.fillMaxWidth()) {
                            Text("${line.optString("itemNo")} · ${line.optString("description")}", fontWeight = FontWeight.Bold)
                            val outstanding = (line.optDouble("quantity") - line.optDouble("qtyReceived")).coerceAtLeast(0.0)
                            Text("Kalan: ${fmtBulkQty(outstanding)} ${line.optString("unitOfMeasureCode")}", fontSize = 12.sp)
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("Kapat") } },
    )
}

internal fun receiptLpPlan(line: JSONObject?): List<JSONObject> = runCatching {
    val rows = JSONArray(line?.optString("receiptLpAllocations").orEmpty().ifBlank { "[]" })
    List(rows.length()) { rows.getJSONObject(it) }
}.getOrDefault(emptyList())

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReceiptLpPlanSheet(itemNo: String, uom: String, rows: List<JSONObject>, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp)) {
            Text("Hazırlanan Lot ve LP Dağılımı", fontSize = 21.sp, fontWeight = FontWeight.Bold)
            Text("$itemNo · ${rows.size} LP · ${fmtBulkQty(rows.sumOf { it.optDouble("quantity", 0.0) })} $uom")
            Text("Bütün LP'ler Mal Kabulü Kaydet ile aynı belge içinde kaydedilecek.", modifier = Modifier.padding(vertical = 10.dp))
            rows.forEach { row ->
                Card(Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text("${row.optString("lpNo")} · ${fmtBulkQty(row.optDouble("quantity"))} $uom", fontWeight = FontWeight.Bold)
                        if (row.optString("lotNo").isNotBlank()) Text("İç lot: ${row.optString("lotNo")}")
                        if (row.optString("supplierLotNo").isNotBlank()) Text("Tedarikçi lotu: ${row.optString("supplierLotNo")}")
                        if (row.optString("expiryDate").isNotBlank()) Text("SKT: ${expiryDateForDisplay(row.optString("expiryDate"))}")
                    }
                }
            }
            Button(onClick = onDismiss, modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp)) { Text("Kapat") }
        }
    }
}
