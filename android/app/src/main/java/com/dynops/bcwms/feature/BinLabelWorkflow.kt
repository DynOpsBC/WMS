package com.dynops.bcwms.feature

import androidx.compose.foundation.BorderStroke
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
import com.dynops.bcwms.ui.*

internal enum class BinLabelMode(val title: String, val glyph: WmsGlyph) {
    Single("Tek raf", WmsGlyph.BIN_SEARCH),
    Bulk("Toplu raf", WmsGlyph.STOCK),
    Zone("Alan etiketi", WmsGlyph.LABEL),
}

@Composable
internal fun BinLabelModePicker(mode: BinLabelMode, enabled: Boolean, onChange: (BinLabelMode) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        BinLabelMode.entries.forEach { option ->
            val selected = mode == option
            Surface(
                onClick = { onChange(option) }, enabled = enabled,
                modifier = Modifier.weight(1f), shape = RoundedCornerShape(14.dp),
                color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surface,
                contentColor = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                border = if (selected) null else BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
            ) {
                Column(Modifier.padding(vertical = 12.dp, horizontal = 4.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    WmsIcon(option.glyph, LocalContentColor.current, Modifier.size(22.dp))
                    Text(option.title, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                }
            }
        }
    }
}

@Composable
internal fun LabelWorkflowStep(number: String, title: String, hint: String, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.7f)),
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = RoundedCornerShape(9.dp)) {
                    Box(Modifier.size(30.dp), contentAlignment = Alignment.Center) {
                        Text(number, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                    }
                }
                Column(Modifier.weight(1f)) {
                    Text(title, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                    if (hint.isNotBlank()) Text(hint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            content()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BinLabelPrintSheet(
    title: String,
    summary: String,
    targetCount: Int,
    areaOnly: Boolean,
    copies: String,
    onCopies: (String) -> Unit,
    documentOutput: Boolean,
    onDocumentOutput: (Boolean) -> Unit,
    printing: Boolean,
    status: String,
    onPrint: () -> Unit,
    onDismiss: () -> Unit,
    printerContent: @Composable () -> Unit = { PrinterDestinationCard(inquiryFallback = true) },
) {
    var submitted by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true,
        confirmValueChange = { it != SheetValue.Hidden || !printing })
    ModalBottomSheet(onDismissRequest = { if (!printing) onDismiss() }, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Surface(color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.55f), shape = RoundedCornerShape(12.dp)) {
                Text(summary, modifier = Modifier.fillMaxWidth().padding(12.dp), fontWeight = FontWeight.SemiBold)
            }
            if (!areaOnly) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = !documentOutput, enabled = !printing && !submitted, onClick = { onDocumentOutput(false) }, label = { Text("Etiket yazıcısı") })
                    FilterChip(selected = documentOutput, enabled = !printing && !submitted, onClick = { onDocumentOutput(true) }, label = { Text("A4 belge") })
                }
            }
            val count = parseLabelCopies(copies)
            if (!documentOutput || areaOnly) {
                if (!printing && !submitted) printerContent()
                LabelCopiesField(copies, onCopies, enabled = !printing && !submitted,
                    label = if (targetCount > 1) "Raf başına" else "Etiket adedi")
                Text(if (count == null) "Etiket adedini kontrol edin."
                    else if (targetCount > 1) "$targetCount raf × $count adet = ${targetCount * count} etiket"
                    else "Toplam $count etiket", fontWeight = FontWeight.SemiBold)
            } else {
                Text("$targetCount raf için $targetCount sayfalık belge hazırlanacak.", style = MaterialTheme.typography.bodyMedium)
            }
            if (submitted && status.isNotBlank()) StatusText(status)
            Button(onClick = { submitted = true; onPrint() },
                enabled = !printing && !submitted && ((documentOutput && !areaOnly) || count != null),
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp), shape = RoundedCornerShape(12.dp)) {
                WmsActionLabel(WmsGlyph.PRINTER, when {
                    printing -> "Gönderiliyor…"
                    documentOutput && !areaOnly -> "A4 belgeyi aç"
                    else -> "${targetCount * (count ?: 0)} etiket yazdır"
                })
            }
            TextButton(onClick = onDismiss, enabled = !printing, modifier = Modifier.fillMaxWidth()) { Text("Kapat") }
        }
    }
}
