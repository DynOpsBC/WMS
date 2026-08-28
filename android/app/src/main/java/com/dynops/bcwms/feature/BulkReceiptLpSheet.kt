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
import kotlin.math.abs

internal data class BulkReceiptLpRow(
    val groupId: String,
    val quantity: Double,
    val lotNo: String,
    val supplierLotNo: String,
    val expiryDate: String,
)

private data class BulkReceiptLotGroup(
    val id: Int,
    val totalQty: String,
    val palletCount: String,
    val perPalletQty: String,
    val putRemainderOnLast: Boolean,
    val lotNo: String,
    val supplierLotNo: String,
    val expiryDate: String,
    val palletQuantities: List<String>,
)

internal fun buildBulkLpQuantities(
    totalQty: Double,
    palletCount: Int,
    perPalletQty: Double,
    putRemainderOnLast: Boolean,
): List<Double>? {
    if (totalQty <= 0.0 || palletCount <= 0 || perPalletQty <= 0.0) return null
    if (!putRemainderOnLast) {
        if (abs(totalQty - palletCount * perPalletQty) > 0.00001) return null
        return List(palletCount) { perPalletQty }
    }
    val last = totalQty - perPalletQty * (palletCount - 1)
    if (last <= 0.0) return null
    return List(palletCount) { index -> if (index == palletCount - 1) last else perPalletQty }
}

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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BulkReceiptLpSheet(
    itemNo: String,
    uom: String,
    initialExpectedQty: Double,
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
    var expectedQty by remember { mutableStateOf(fmtBulkQty(initialExpectedQty)) }
    var printLabels by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf("") }
    var nextGroupId by remember { mutableIntStateOf(2) }
    var groups by remember {
        mutableStateOf(
            listOf(
                BulkReceiptLotGroup(
                    id = 1,
                    totalQty = fmtBulkQty(initialExpectedQty),
                    palletCount = "1",
                    perPalletQty = fmtBulkQty(initialExpectedQty),
                    putRemainderOnLast = true,
                    lotNo = initialLotNo,
                    supplierLotNo = initialSupplierLotNo,
                    expiryDate = initialExpiryDate.take(10),
                    palletQuantities = listOf(fmtBulkQty(initialExpectedQty)),
                )
            )
        )
    }

    fun updateGroup(id: Int, transform: (BulkReceiptLotGroup) -> BulkReceiptLotGroup) {
        groups = groups.map { if (it.id == id) transform(it) else it }
        error = ""
    }

    fun generate(group: BulkReceiptLotGroup, equal: Boolean) {
        val total = group.totalQty.toDoubleOrNull() ?: 0.0
        val count = group.palletCount.toIntOrNull() ?: 0
        val per = if (equal && count > 0) total / count else group.perPalletQty.toDoubleOrNull() ?: 0.0
        val quantities = if (equal && total > 0 && count > 0) {
            val values = MutableList(count) { per }
            values[count - 1] = total - per * (count - 1)
            values
        } else buildBulkLpQuantities(total, count, per, group.putRemainderOnLast)
        if (quantities == null) {
            error = "Lot ${group.id}: toplam, LP sayısı ve LP başı miktar uyuşmuyor. Kalanı son LP'ye aktar seçeneğini açabilirsiniz."
            return
        }
        updateGroup(group.id) {
            it.copy(
                perPalletQty = fmtBulkQty(per),
                palletQuantities = quantities.map(::fmtBulkQty),
            )
        }
    }

    val expected = expectedQty.toDoubleOrNull() ?: 0.0
    val rows = groups.flatMap { group ->
        group.palletQuantities.mapNotNull { text ->
            text.toDoubleOrNull()?.takeIf { it > 0.0 }?.let { qty ->
                BulkReceiptLpRow(
                    groupId = group.id.toString(),
                    quantity = qty,
                    lotNo = group.lotNo,
                    supplierLotNo = group.supplierLotNo,
                    expiryDate = group.expiryDate,
                )
            }
        }
    }
    val distributed = rows.sumOf { it.quantity }
    val groupRowsComplete = groups.all { group ->
        val count = group.palletCount.toIntOrNull() ?: 0
        count > 0 && group.palletQuantities.size == count && group.palletQuantities.all { (it.toDoubleOrNull() ?: 0.0) > 0.0 }
    }
    val requiredFieldsComplete = groups.all {
        (!expiryRequired || it.expiryDate.isNotBlank())
    }
    val canSubmit = expected > 0.0 && rows.isNotEmpty() && groupRowsComplete &&
        requiredFieldsComplete && abs(distributed - expected) <= 0.00001

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier.fillMaxWidth().fillMaxHeight(0.94f)
                .verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            Text("Toplu LP Dağıtımı", fontSize = 21.sp, fontWeight = FontWeight.Bold)
            Text("$itemNo · $uom", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(10.dp))
            OutlinedTextField(
                value = expectedQty,
                onValueChange = { expectedQty = numericText(it); error = "" },
                label = { Text("Toplam kabul miktarı") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(10.dp))

            groups.forEachIndexed { groupIndex, group ->
                Card(
                    modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Column(Modifier.padding(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Lot grubu ${groupIndex + 1}", fontWeight = FontWeight.Bold)
                            Spacer(Modifier.weight(1f))
                            if (groups.size > 1) TextButton(onClick = { groups = groups.filterNot { it.id == group.id } }) { Text("Sil") }
                        }
                        if (lotRequired) {
                            OutlinedTextField(
                                value = group.lotNo,
                                onValueChange = { value -> updateGroup(group.id) { it.copy(lotNo = value) } },
                                label = { Text("İç lot (boşsa sistem üretir)") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Spacer(Modifier.height(6.dp))
                            OutlinedTextField(
                                value = group.supplierLotNo,
                                onValueChange = { value -> updateGroup(group.id) { it.copy(supplierLotNo = value) } },
                                label = { Text("Tedarikçi lotu (opsiyonel)") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                        if (expiryEnabled) {
                            Spacer(Modifier.height(6.dp))
                            OutlinedTextField(
                                value = group.expiryDate,
                                onValueChange = { value -> updateGroup(group.id) { it.copy(expiryDate = value) } },
                                label = { Text(if (expiryRequired) "SKT (YYYY-AA-GG)" else "SKT (opsiyonel)") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                        Spacer(Modifier.height(6.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            OutlinedTextField(
                                value = group.totalQty,
                                onValueChange = { value -> updateGroup(group.id) { it.copy(totalQty = numericText(value), palletQuantities = emptyList()) } },
                                label = { Text("Lot toplamı") },
                                singleLine = true,
                                modifier = Modifier.weight(1f),
                            )
                            OutlinedTextField(
                                value = group.palletCount,
                                onValueChange = { value -> updateGroup(group.id) { it.copy(palletCount = value.filter(Char::isDigit), palletQuantities = emptyList()) } },
                                label = { Text("LP sayısı") },
                                singleLine = true,
                                modifier = Modifier.weight(1f),
                            )
                        }
                        Spacer(Modifier.height(6.dp))
                        OutlinedTextField(
                            value = group.perPalletQty,
                            onValueChange = { value -> updateGroup(group.id) { it.copy(perPalletQty = numericText(value), palletQuantities = emptyList()) } },
                            label = { Text("LP başına miktar") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(
                                checked = group.putRemainderOnLast,
                                onCheckedChange = { checked -> updateGroup(group.id) { it.copy(putRemainderOnLast = checked, palletQuantities = emptyList()) } },
                            )
                            Text("Kalan miktarı son LP'ye aktar", fontSize = 13.sp)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            OutlinedButton(onClick = { generate(group, equal = true) }, modifier = Modifier.weight(1f)) { Text("Eşit dağıt") }
                            Button(onClick = { generate(group, equal = false) }, modifier = Modifier.weight(1f)) { Text("Listeyi oluştur") }
                        }

                        if (group.palletQuantities.isNotEmpty()) {
                            Spacer(Modifier.height(8.dp))
                            Text("LP miktarları", fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                            group.palletQuantities.forEachIndexed { index, value ->
                                OutlinedTextField(
                                    value = value,
                                    onValueChange = { newValue ->
                                        updateGroup(group.id) {
                                            val changed = it.palletQuantities.toMutableList()
                                            changed[index] = numericText(newValue)
                                            it.copy(palletQuantities = changed)
                                        }
                                    },
                                    label = { Text("LP ${index + 1}") },
                                    singleLine = true,
                                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                                )
                            }
                        }
                    }
                }
            }

            OutlinedButton(
                onClick = {
                    groups = groups + BulkReceiptLotGroup(
                        id = nextGroupId++, totalQty = "", palletCount = "1", perPalletQty = "",
                        putRemainderOnLast = true, lotNo = "", supplierLotNo = "", expiryDate = "",
                        palletQuantities = emptyList(),
                    )
                },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Farklı lot ekle") }

            Spacer(Modifier.height(8.dp))
            Surface(
                color = if (abs(distributed - expected) <= 0.00001 && expected > 0) MaterialTheme.colorScheme.primaryContainer
                else MaterialTheme.colorScheme.errorContainer,
                shape = RoundedCornerShape(10.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(Modifier.padding(10.dp)) {
                    Text("Kabul: ${fmtBulkQty(expected)} · LP toplamı: ${fmtBulkQty(distributed)}", fontWeight = FontWeight.Bold)
                    Text("Fark: ${fmtBulkQty(expected - distributed)} · ${rows.size} LP", fontSize = 12.sp)
                }
            }
            if (error.isNotBlank()) Text(error, color = MaterialTheme.colorScheme.error, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = printLabels, onCheckedChange = { printLabels = it })
                Text("Tüm LP / Madde Tanımlama etiketlerini yazdır", fontSize = 13.sp)
            }
            Row(Modifier.padding(bottom = 18.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("İptal") }
                Button(
                    onClick = { onSubmit(expected, rows, printLabels) },
                    enabled = canSubmit,
                    modifier = Modifier.weight(1f),
                ) { Text("LP'leri Oluştur") }
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
        title = { Text("Toplu LP için satır seç") },
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
