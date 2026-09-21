package com.dynops.bcwms.feature

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.ui.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BulkItemLabelsSheet(
    products: List<InquiryLabelProduct>,
    printing: Boolean,
    progress: String,
    result: InquiryLabelBatchResult?,
    onPrint: (List<InquiryLabelJob>) -> Unit,
    onDismiss: () -> Unit,
    printerContent: @Composable () -> Unit = {
        PrinterDestinationCard(inquiryFallback = true, compact = true, enabled = !printing && result == null)
    },
) {
    var selected by remember(products) { mutableStateOf(products.map { it.itemNo }.toSet()) }
    var quantities by remember(products) { mutableStateOf(products.associate { it.itemNo to it.copies }) }
    val selectedProducts = products.filter { it.itemNo in selected }
    val valid = selectedProducts.isNotEmpty() && selectedProducts.all { parseLabelCopies(quantities[it.itemNo].orEmpty()) != null }
    val total = selectedProducts.sumOf { parseLabelCopies(quantities[it.itemNo].orEmpty()) ?: 0 }
    val editable = !printing && result == null
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { it != SheetValue.Hidden || !printing },
    )
    // Wrap short lists; cap long lists so actions remain visible while products scroll.
    val maxHeight = LocalConfiguration.current.screenHeightDp.dp * 0.86f
    ModalBottomSheet(onDismissRequest = { if (!printing) onDismiss() }, sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface) {
        Column(Modifier.fillMaxWidth().heightIn(max = maxHeight).padding(horizontal = 16.dp).padding(bottom = 16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Toplu etiket yazdır", fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    Text("Ürünleri seçip adedi ayarlayın.", fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = onDismiss, enabled = !printing,
                    modifier = Modifier.semantics { contentDescription = "Kapat" }) {
                    WmsIcon(WmsGlyph.CLOSE, MaterialTheme.colorScheme.onSurfaceVariant, Modifier.size(20.dp))
                }
            }
            Spacer(Modifier.height(12.dp))
            printerContent()
            Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Yazdırılacak ürünler", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                TextButton(enabled = editable, onClick = {
                    selected = if (selected.size == products.size) emptySet() else products.map { it.itemNo }.toSet()
                }) { Text(if (selected.size == products.size) "Seçimi kaldır" else "Tümünü seç", fontSize = 12.sp) }
            }
            LazyColumn(Modifier.weight(1f, fill = false), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(products, key = { it.itemNo }) { product ->
                    val checked = product.itemNo in selected
                    val quantity = quantities[product.itemNo].orEmpty()
                    Surface(
                        color = if (checked) MaterialTheme.colorScheme.primary.copy(alpha = 0.025f) else MaterialTheme.colorScheme.surface,
                        border = BorderStroke(1.dp, if (checked) MaterialTheme.colorScheme.primary.copy(alpha = 0.22f)
                            else MaterialTheme.colorScheme.outlineVariant),
                        shape = RoundedCornerShape(12.dp),
                    ) {
                        Column(Modifier.fillMaxWidth().padding(start = 2.dp, end = 8.dp, top = 8.dp, bottom = 8.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Checkbox(checked = checked, enabled = editable,
                                    modifier = Modifier.semantics { contentDescription = "${product.itemNo} ürününü seç" },
                                    onCheckedChange = { selected = if (it) selected + product.itemNo else selected - product.itemNo })
                                Column(Modifier.weight(1f).padding(end = 8.dp)) {
                                    Text(product.itemNo, fontSize = 13.sp, lineHeight = 17.sp, fontWeight = FontWeight.Bold)
                                    if (product.description.isNotBlank() && !product.description.equals(product.itemNo, true)) {
                                        Text(product.description, fontSize = 11.sp, lineHeight = 15.sp,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                    }
                                }
                                CompactLabelCopies(product.itemNo, quantity,
                                    { quantities = quantities + (product.itemNo to it) }, enabled = editable && checked)
                            }
                            if (checked && parseLabelCopies(quantity) == null) {
                                Text("1–99 adet girin.", fontSize = 11.sp, color = MaterialTheme.colorScheme.error,
                                    modifier = Modifier.padding(start = 14.dp, top = 3.dp))
                            }
                            if (checked) result?.let { outcome ->
                                val sent = outcome.sentCopies[product.itemNo] ?: 0
                                val requested = parseLabelCopies(quantity) ?: 0
                                Text(when {
                                    sent == requested -> "$sent etiket kuyruğa alındı"
                                    product.itemNo == outcome.failedItemNo -> "$sent / $requested etiket doğrulandı · Gönderim durdu"
                                    else -> "Gönderilmedi"
                                }, style = MaterialTheme.typography.bodySmall,
                                    color = if (sent == requested) bcwmsStatus().success else MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(start = 14.dp, top = 6.dp))
                            }
                        }
                    }
                }
                if (result != null) item {
                    StatusText(if (result.complete) "TAMAM: ${result.totalSent} etiket kuyruğa alındı."
                        else "HATA: ${result.error}\n${result.totalSent} etiketin kuyruğa alındığı doğrulandı. Tekrar göndermeden önce yazdırma kuyruğunu kontrol edin.")
                }
            }
            HorizontalDivider(Modifier.padding(vertical = 12.dp))
            if (printing) {
                LinearProgressIndicator(Modifier.fillMaxWidth())
                Text(progress, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(vertical = 8.dp))
            }
            if (result == null) {
                Text("${selected.size} ürün · Toplam $total etiket", fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(bottom = 10.dp))
                Button(enabled = editable && valid, onClick = {
                    onPrint(selectedProducts.map { InquiryLabelJob(it.itemNo, requireNotNull(parseLabelCopies(quantities[it.itemNo].orEmpty()))) })
                }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp), shape = RoundedCornerShape(12.dp)) {
                    WmsActionLabel(WmsGlyph.PRINTER, if (printing) "Gönderiliyor…" else "Seçilenleri yazdır · $total etiket")
                }
            } else {
                Button(onClick = onDismiss, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) { Text("Kapat") }
            }
        }
    }
}

@Composable
private fun CompactLabelCopies(itemNo: String, value: String, onChange: (String) -> Unit, enabled: Boolean) {
    val current = parseLabelCopies(value)
    val accent = MaterialTheme.colorScheme.primary
    Surface(
        color = MaterialTheme.colorScheme.surface,
        border = BorderStroke(1.dp, if (enabled && current == null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.outlineVariant),
        shape = RoundedCornerShape(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(enabled = enabled && (current ?: 1) > 1,
                modifier = Modifier.size(48.dp).semantics { contentDescription = "$itemNo etiket adedini azalt" },
                onClick = { onChange(((current ?: 1) - 1).coerceAtLeast(1).toString()) }) {
                Text("−", fontSize = 22.sp, fontWeight = FontWeight.Bold)
            }
            Column(Modifier.width(36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                BasicTextField(value = value, enabled = enabled, singleLine = true,
                    onValueChange = { onChange(it.filter(Char::isDigit).take(2)) },
                    textStyle = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp, fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center, color = if (enabled) accent else MaterialTheme.colorScheme.onSurfaceVariant),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth().heightIn(min = 24.dp).semantics { contentDescription = "$itemNo etiket adedi" })
                Text("adet", fontSize = 10.sp, lineHeight = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(enabled = enabled && (current ?: 0) < LABEL_COPIES_MAX,
                modifier = Modifier.size(48.dp).semantics { contentDescription = "$itemNo etiket adedini artır" },
                onClick = { onChange(((current ?: 0) + 1).coerceAtMost(LABEL_COPIES_MAX).toString()) }) {
                Text("+", fontSize = 22.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}
