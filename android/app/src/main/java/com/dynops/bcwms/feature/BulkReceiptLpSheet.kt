package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.json.JSONArray
import org.json.JSONObject

internal data class BulkReceiptLpRow(
    val groupId: String,
    val quantity: Double,
    val lotNo: String,
    val supplierLotNo: String,
    val expiryDate: String,
)

private data class ManualBulkLpDraft(
    val id: Int,
    val quantity: String,
    val lotNo: String,
    val supplierLotNo: String,
    val expiryDate: String,
)

internal fun bulkLpRowsJson(rows: List<BulkReceiptLpRow>): String = JSONArray().apply {
    rows.forEach { row ->
        put(JSONObject().apply {
            put("groupId", row.groupId)
            put("quantity", row.quantity)
            put("lotNo", row.lotNo.trim())
            put("supplierLotNo", row.supplierLotNo.trim())
            put("expiryDate", row.expiryDate.trim())
        })
    }
}.toString()

internal fun manualBulkLpValidation(
    maxQty: Double,
    rows: List<BulkReceiptLpRow>,
    expiryRequired: Boolean,
): String? {
    if (maxQty <= 0.0) return "Bu satırda kabul edilecek açık miktar yok."
    if (rows.isEmpty()) return "En az bir LP ekleyin."
    if (rows.any { it.quantity <= 0.0 }) return "Her LP için sıfırdan büyük miktar girin."
    if (rows.sumOf { it.quantity } - maxQty > 0.00001) return "LP toplamı açık miktarı aşamaz."
    if (expiryRequired && rows.any { it.expiryDate.isBlank() }) return "Her LP için SKT girin."
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
    expiryEnabled: Boolean,
    expiryRequired: Boolean,
    onDismiss: () -> Unit,
    onSubmit: (expectedQty: Double, rows: List<BulkReceiptLpRow>, printLabels: Boolean) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var printLabels by remember { mutableStateOf(true) }
    var nextLpId by remember { mutableIntStateOf(2) }
    var drafts by remember {
        mutableStateOf(
            listOf(
                ManualBulkLpDraft(
                    id = 1,
                    quantity = "",
                    lotNo = initialLotNo,
                    supplierLotNo = initialSupplierLotNo,
                    expiryDate = initialExpiryDate.take(10),
                )
            )
        )
    }

    fun updateDraft(id: Int, transform: (ManualBulkLpDraft) -> ManualBulkLpDraft) {
        drafts = drafts.map { if (it.id == id) transform(it) else it }
    }

    val rows = drafts.map { draft ->
        BulkReceiptLpRow(
            groupId = draft.id.toString(),
            quantity = draft.quantity.toDoubleOrNull() ?: 0.0,
            lotNo = draft.lotNo,
            supplierLotNo = draft.supplierLotNo,
            expiryDate = draft.expiryDate,
        )
    }
    val enteredTotal = rows.sumOf { it.quantity }
    val validationError = manualBulkLpValidation(maxExpectedQty, rows, expiryRequired)
    val remaining = maxExpectedQty - enteredTotal
    val canSubmit = validationError == null

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier.fillMaxWidth().fillMaxHeight(0.94f)
                .verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)
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
                    "Her paleti ekleyin ve miktarını siz girin. Sistem dağıtım yapmaz; yalnızca toplamı ve zorunlu alanları kontrol eder.",
                    modifier = Modifier.padding(10.dp),
                    fontSize = 13.sp,
                )
            }
            Spacer(Modifier.height(10.dp))

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
                                TextButton(onClick = { drafts = drafts.filterNot { it.id == draft.id } }) {
                                    Text("Kaldır")
                                }
                            }
                        }
                        OutlinedTextField(
                            value = draft.quantity,
                            onValueChange = { value -> updateDraft(draft.id) { it.copy(quantity = numericText(value)) } },
                            label = { Text("Miktar ($uom)") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        if (lotRequired) {
                            Spacer(Modifier.height(6.dp))
                            OutlinedTextField(
                                value = draft.lotNo,
                                onValueChange = { value -> updateDraft(draft.id) { it.copy(lotNo = value) } },
                                label = { Text("İç lot (boşsa BC üretir)") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Spacer(Modifier.height(6.dp))
                            OutlinedTextField(
                                value = draft.supplierLotNo,
                                onValueChange = { value -> updateDraft(draft.id) { it.copy(supplierLotNo = value) } },
                                label = { Text("Tedarikçi lotu (opsiyonel)") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                        if (expiryEnabled) {
                            Spacer(Modifier.height(6.dp))
                            OutlinedTextField(
                                value = draft.expiryDate,
                                onValueChange = { value -> updateDraft(draft.id) { it.copy(expiryDate = value) } },
                                label = { Text(if (expiryRequired) "SKT (YYYY-AA-GG)" else "SKT (opsiyonel)") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                }
            }

            OutlinedButton(
                onClick = {
                    drafts = drafts + ManualBulkLpDraft(
                        id = nextLpId++,
                        quantity = "",
                        lotNo = "",
                        supplierLotNo = "",
                        expiryDate = "",
                    )
                },
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
                        "Açık miktar: ${fmtBulkQty(maxExpectedQty)} · Kalan: ${fmtBulkQty(remaining)} $uom",
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
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = printLabels, onCheckedChange = { printLabels = it })
                Text("LP / Madde Tanımlama etiketlerini yazdır", fontSize = 13.sp)
            }
            Row(Modifier.padding(bottom = 18.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("İptal") }
                Button(
                    onClick = { onSubmit(enteredTotal, rows, printLabels) },
                    enabled = canSubmit,
                    modifier = Modifier.weight(1f),
                ) { Text("${drafts.size} LP Oluştur") }
            }
        }
    }
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
