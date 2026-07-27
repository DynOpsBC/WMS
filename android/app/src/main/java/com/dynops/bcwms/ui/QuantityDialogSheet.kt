package com.dynops.bcwms.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

data class QuantityResult(
    val quantity: Double,
    val uom: String,
    val lotNo: String,
    val serialNo: String,
)

/**
 * Modal bottom sheet for capturing a quantity with optional UoM / lot / serial.
 * Includes a stepper, a big "+1" button, and Confirm / Cancel.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuantityDialogSheet(
    title: String,
    itemNo: String,
    initialQty: Double = 1.0,
    initialUom: String = "",
    initialLot: String = "",
    initialSerial: String = "",
    showLotSerial: Boolean = true,
    showSerial: Boolean = showLotSerial,
    onConfirm: (QuantityResult) -> Unit,
    onDismiss: () -> Unit,
) {
    var qtyText by remember { mutableStateOf(formatQty(initialQty)) }
    var uom by remember { mutableStateOf(initialUom) }
    var lot by remember { mutableStateOf(initialLot) }
    var serial by remember { mutableStateOf(initialSerial) }

    fun qty(): Double = qtyText.toDoubleOrNull() ?: 0.0
    fun setQty(v: Double) { qtyText = formatQty(v.coerceAtLeast(0.0)) }

    SheetScaffold(onDismiss = onDismiss) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Text("Ürün: $itemNo", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(16.dp))

            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedIconButton(onClick = { setQty(qty() - 1) }) { Text("−", fontSize = 22.sp) }
                OutlinedTextField(
                    value = qtyText,
                    onValueChange = { qtyText = it.filter { c -> c.isDigit() || c == '.' } },
                    label = { Text("Miktar") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                OutlinedIconButton(onClick = { setQty(qty() + 1) }) { Text("+", fontSize = 22.sp) }
            }
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = { setQty(qty() + 1) },
                modifier = Modifier.fillMaxWidth().height(52.dp)
            ) { Text("+1", fontSize = 20.sp, fontWeight = FontWeight.Bold) }

            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = uom, onValueChange = { uom = it },
                label = { Text("Ölçü Birimi (UOM)") }, singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            if (showLotSerial) {
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = lot, onValueChange = { lot = it },
                    label = { Text("Lot No (opsiyonel)") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            if (showSerial) {
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = serial, onValueChange = { serial = it },
                    label = { Text("Seri No (opsiyonel)") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("İptal") }
                Button(
                    onClick = { onConfirm(QuantityResult(qty(), uom.trim(), lot.trim(), serial.trim())) },
                    enabled = qty() > 0,
                    modifier = Modifier.weight(1f)
                ) { Text("Onayla") }
            }
            Spacer(Modifier.height(24.dp))
    }
}

private fun formatQty(v: Double): String =
    if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()
