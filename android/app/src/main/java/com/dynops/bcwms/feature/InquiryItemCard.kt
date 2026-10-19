package com.dynops.bcwms.feature

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.ui.*
import java.text.NumberFormat
import java.util.Locale

private fun inquiryQuantity(value: Double): String =
    if (!value.isFinite()) "—" else NumberFormat.getNumberInstance(Locale.forLanguageTag("tr-TR")).apply {
        maximumFractionDigits = 2
    }.format(value)

/** Keep stock visible; reveal warehouse detail and printing only when needed. */
@Composable
internal fun InquiryItemCard(
    entry: InquiryItemEntry,
    expanded: Boolean,
    labelsOnly: Boolean,
    busy: Boolean,
    onToggle: () -> Unit,
    onRemove: () -> Unit,
    onPrint: () -> Unit,
) {
    val item = entry.item
    val no = item?.let { firstValue(it, "no", "number") } ?: entry.queryKey
    val description = item?.let { firstValue(it, "description", "displayName") }.orEmpty()
    val inventory = item?.optDouble("inventory", Double.NaN) ?: Double.NaN
    val reserved = item?.optDouble("reservedQtyOnInventory", 0.0) ?: 0.0
    val blocked = item?.optBoolean("blocked", false) == true
    val uom = entry.uom
    val palette = bcwmsStatus()
    var showDetails by remember(entry.queryKey) { mutableStateOf(false) }
    val lpCount = entry.lpLines.map { it.optString("lpNo") }.filter { it.isNotBlank() }.distinct().size

    val primary = MaterialTheme.colorScheme.primary
    val stockAccent = when {
        !inventory.isFinite() -> MaterialTheme.colorScheme.onSurfaceVariant
        inventory > 0 -> Color(0xFF15805D)
        else -> Color(0xFFB46A16)
    }
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = if (expanded) 3.dp else 1.dp),
        border = BorderStroke(1.dp, if (expanded) primary.copy(alpha = 0.28f)
            else MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.7f)),
    ) {
        Row(
            Modifier.fillMaxWidth()
                .background(Brush.horizontalGradient(listOf(
                    primary.copy(alpha = if (expanded) 0.10f else 0.035f),
                    primary.copy(alpha = if (expanded) 0.025f else 0.01f),
                )))
                .padding(start = 12.dp, top = 10.dp, bottom = 10.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(color = primary.copy(alpha = if (expanded) 0.13f else 0.07f), shape = RoundedCornerShape(12.dp)) {
                Box(Modifier.size(38.dp), contentAlignment = Alignment.Center) {
                    WmsIcon(WmsGlyph.STOCK, primary, Modifier.size(21.dp))
                }
            }
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f).clickable(onClickLabel = if (expanded) "Ürünü daralt" else "Ürünü aç", onClick = onToggle)) {
                Text(no, fontSize = 15.sp, lineHeight = 19.sp, fontWeight = FontWeight.Bold)
                if (description.isNotBlank() && !description.equals(no, ignoreCase = true)) {
                    Text(description, fontSize = 12.sp, lineHeight = 16.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = if (expanded) 3 else 2, overflow = TextOverflow.Ellipsis)
                }
                if (blocked) Text("Bloke ürün", style = MaterialTheme.typography.labelMedium, color = palette.danger)
            }
            IconButton(onClick = onRemove, enabled = !busy,
                modifier = Modifier.size(48.dp).semantics { contentDescription = "$no ürününü listeden çıkar" }) {
                WmsIcon(WmsGlyph.CLOSE, MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f), Modifier.size(16.dp))
            }
        }
        Column(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (expanded && !labelsOnly) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    InquiryStockValue("Toplam stok", inventory, uom, stockAccent, Modifier.weight(1f))
                    InquiryStockValue("Kullanılabilir", inventory - reserved, uom, primary, Modifier.weight(1f))
                    InquiryStockValue("Rezerve", reserved, uom, Color(0xFFB46A16), Modifier.weight(1f))
                }
            } else {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Surface(color = stockAccent.copy(alpha = 0.08f), shape = RoundedCornerShape(9.dp), modifier = Modifier.weight(1f)) {
                        Row(Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Stok", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text("${inquiryQuantity(inventory)} $uom".trim(), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = stockAccent)
                        }
                    }
                    Spacer(Modifier.width(6.dp))
                    TextButton(onClick = onToggle, contentPadding = PaddingValues(horizontal = 8.dp)) {
                        Text(if (expanded) "Daralt" else "Detay", fontSize = 12.sp)
                        WmsIcon(WmsGlyph.CHEVRON, primary, Modifier.size(16.dp).rotate(if (expanded) -90f else 90f))
                    }
                }
            }
            if (expanded) {
                if (!labelsOnly) {
                    queriedLpSummary(entry.queriedLpNo, entry.lpLines)?.let { lp ->
                        Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = RoundedCornerShape(10.dp)) {
                            Column(Modifier.fillMaxWidth().padding(12.dp)) {
                                Text("Okutulan LP: ${lp.lpNo}", fontWeight = FontWeight.SemiBold)
                                Text("${inquiryQuantity(lp.quantity)} $uom", style = MaterialTheme.typography.bodyMedium)
                                if (lp.lotNos.isNotEmpty()) Text("Lot: ${lp.lotNos.joinToString(" · ")}", style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                    Surface(
                        onClick = { showDetails = !showDetails },
                        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.7f),
                        shape = RoundedCornerShape(10.dp),
                    ) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
                            WmsIcon(WmsGlyph.ENTRIES, MaterialTheme.colorScheme.onSurfaceVariant, Modifier.size(17.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(if (showDetails) "Stok ayrıntılarını gizle" else "Stok ayrıntıları",
                                fontSize = 12.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                            Text("$lpCount LP", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.width(8.dp))
                            WmsIcon(WmsGlyph.CHEVRON, MaterialTheme.colorScheme.onSurfaceVariant,
                                Modifier.size(14.dp).rotate(if (showDetails) -90f else 90f))
                        }
                    }
                    if (showDetails) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Sipariş miktarları", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                            InquiryDetailRow("Gelecek (satın alma)", "${inquiryQuantity(item?.optDouble("quantityOnPurchOrder", 0.0) ?: 0.0)} $uom")
                            InquiryDetailRow("Sevk edilecek (satış)", "${inquiryQuantity(item?.optDouble("quantityOnSalesOrder", 0.0) ?: 0.0)} $uom")
                            InquiryDetailRow("Üretim emrinde", "${inquiryQuantity(item?.optDouble("quantityOnProdOrder", 0.0) ?: 0.0)} $uom")
                            val category = item?.let { firstValue(it, "itemCategoryCode") }.orEmpty()
                            if (category.isNotBlank() && category != "-") InquiryDetailRow("Kategori", category)
                            HorizontalDivider()
                            Text("LP bilgileri ($lpCount)", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                            if (entry.lpLines.isEmpty()) {
                                Text("Bu ürün için LP kaydı bulunamadı.", style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            } else {
                                InquiryDetailRow("LP'lerdeki toplam", "${inquiryQuantity(entry.lpLines.sumOf { it.optDouble("quantity", 0.0) })} $uom")
                                entry.lpLines.forEach { line ->
                                    Column {
                                        InquiryDetailRow(line.optString("lpNo"), "${inquiryQuantity(line.optDouble("quantity", 0.0))} $uom")
                                        val extra = listOfNotNull(
                                            line.optString("lotNo").takeIf(String::isNotBlank)?.let { "Lot: $it" },
                                            line.optString("serialNo").takeIf(String::isNotBlank)?.let { "Seri: $it" },
                                        ).joinToString(" · ")
                                        if (extra.isNotBlank()) Text(extra, style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                            }
                            if (entry.ledger.isNotEmpty()) {
                                HorizontalDivider()
                                Text("Son hareketler", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                entry.ledger.take(10).forEach { movement ->
                                    Column {
                                        InquiryDetailRow("${bcEntryTypeLabelTr(movement.optString("entryType"))} · ${movement.optString("documentNo")}", inquiryQuantity(movement.optDouble("quantity")))
                                        Text(listOf(movement.optString("postingDate").take(10), firstValue(movement, "locationCode"),
                                            movement.optString("lotNo").takeIf(String::isNotBlank)?.let { "Lot: $it" }.orEmpty())
                                            .filter { it.isNotBlank() && it != "-" }.joinToString(" · "),
                                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                            }
                        }
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (!labelsOnly) {
                        IconButton(onClick = onToggle,
                            modifier = Modifier.size(44.dp).semantics { contentDescription = "Ürünü daralt" }) {
                            WmsIcon(WmsGlyph.CHEVRON, MaterialTheme.colorScheme.onSurfaceVariant, Modifier.size(20.dp).rotate(-90f))
                        }
                    }
                    Button(onClick = onPrint, enabled = !busy && item != null,
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.weight(1f).heightIn(min = 44.dp)) {
                        WmsActionLabel(WmsGlyph.PRINTER, "Etiket yazdır")
                    }
                }
            }
        }
    }
}

@Composable
private fun InquiryStockValue(label: String, quantity: Double, uom: String, accent: Color, modifier: Modifier) {
    val amount = inquiryQuantity(quantity)
    Surface(color = accent.copy(alpha = 0.075f), shape = RoundedCornerShape(12.dp), modifier = modifier) {
        Column(Modifier.padding(horizontal = 9.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(label, fontSize = 11.sp, lineHeight = 14.sp, maxLines = 1,
                color = MaterialTheme.colorScheme.onSurfaceVariant, letterSpacing = 0.sp)
            Text(amount, fontSize = if (amount.length > 9) 12.sp else if (amount.length > 7) 15.sp else 22.sp,
                lineHeight = 26.sp, maxLines = 1, fontWeight = FontWeight.Bold, color = accent)
            Text(uom.ifBlank { "—" }, fontSize = 10.sp, lineHeight = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun InquiryDetailRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium, textAlign = androidx.compose.ui.text.style.TextAlign.End)
    }
}
