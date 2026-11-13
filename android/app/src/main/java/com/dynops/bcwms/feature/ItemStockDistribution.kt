package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import kotlinx.coroutines.CancellationException

internal data class ItemStockDistributionState(
    val loading: Boolean = true,
    val failed: Boolean = false,
    val locations: List<ItemStockLocation> = emptyList(),
    val retry: () -> Unit = {},
)

@Composable
internal fun rememberItemStockDistribution(
    itemNo: String?,
    refreshKey: Any?,
    loadStock: (suspend () -> BcApi.PagedItemsResult)? = null,
): ItemStockDistributionState {
    val context = LocalContext.current
    var attempt by remember(itemNo, refreshKey) { mutableIntStateOf(0) }
    var state by remember(itemNo, refreshKey) { mutableStateOf(ItemStockDistributionState()) }
    LaunchedEffect(itemNo, refreshKey, attempt) {
        state = ItemStockDistributionState()
        if (itemNo.isNullOrBlank()) return@LaunchedEffect
        try {
            val page = loadStock?.invoke() ?: BcApi.getAllPages(context, itemStockPath(itemNo))
            check(page.complete)
            state = ItemStockDistributionState(loading = false, locations = itemStockLocations(page.rows))
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            state = ItemStockDistributionState(loading = false, failed = true)
        }
    }
    return state.copy(retry = { attempt++ })
}

/** Part of the inquiry's single lazy list: every bin is visible without opening anything. */
@OptIn(ExperimentalLayoutApi::class)
internal fun LazyListScope.itemStockDistribution(state: ItemStockDistributionState, baseUom: String) {
    item(key = "stock-heading") {
        Text("Raflardaki stok", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
    }
    when {
        state.loading -> item(key = "stock-loading") {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CircularProgressIndicator(Modifier.size(20.dp))
                Text("Raf stokları yükleniyor…", style = MaterialTheme.typography.bodySmall)
            }
        }
        state.failed -> item(key = "stock-error") {
            Text("Raf stokları alınamadı. Tekrar deneyin.", color = MaterialTheme.colorScheme.error)
            TextButton(onClick = state.retry) { Text("Tekrar dene") }
        }
        state.locations.isEmpty() -> item(key = "stock-empty") {
            Text("Bu ürün için stok bulunan bin / depo gözü yok.", style = MaterialTheme.typography.bodySmall)
        }
        else -> state.locations.forEach { location ->
            item(key = "stock-location:${location.code}") {
                Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(location.code.ifBlank { "Lokasyonsuz" }, Modifier.weight(1f),
                        style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                    location.baseQuantity?.let {
                        Text("${formatStockQuantity(it)} $baseUom", style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
            itemsIndexed(location.bins, key = { _, bin -> "stock-bin:${location.code.length}:${location.code}:${bin.code}" }) { index, bin ->
                val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
                val accents = if (dark) listOf(Color(0xFF80C7FF), Color(0xFF68DBC0), Color(0xFFFFC47C))
                    else listOf(Color(0xFF0065B3), Color(0xFF007D65), Color(0xFF9B5700))
                val accent = accents[index % accents.size]
                Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp),
                    color = accent.copy(alpha = if (dark) 0.16f else 0.09f)) {
                    Row(Modifier.height(IntrinsicSize.Min)) {
                     Box(Modifier.width(5.dp).fillMaxHeight().background(accent))
                     Column(Modifier.weight(1f).padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        bin.rows.forEach { row ->
                            FlowRow(Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Column(Modifier.widthIn(min = 120.dp, max = 200.dp)) {
                                    Text(bin.code.ifBlank { "Depo gözü yok" }, fontWeight = FontWeight.Bold,
                                        fontSize = 22.sp, color = accent)
                                    row.optString("zoneCode").takeIf { it.isNotBlank() && it != bin.code }?.let {
                                        Text(it, style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    row.optString("variantCode").takeIf { it.isNotBlank() }?.let {
                                        Text("Varyant: $it", style = MaterialTheme.typography.labelSmall)
                                    }
                                }
                                val quantity = row.getDouble("quantity")
                                Surface(Modifier.widthIn(max = 180.dp), shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surface) {
                                    Text("${formatStockQuantity(quantity)} ${row.optString("unitOfMeasureCode").ifBlank { "—" }}",
                                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                                        fontWeight = FontWeight.Bold, fontSize = 22.sp,
                                        color = if (quantity < 0) MaterialTheme.colorScheme.error else accent)
                                }
                            }
                        }
                    }
                    }
                }
            }
        }
    }
    if (!state.loading && !state.failed) item(key = "stock-note") {
        var expanded by remember { mutableStateOf(false) }
        TextButton(onClick = { expanded = !expanded }, contentPadding = PaddingValues(horizontal = 0.dp)) {
            Text(if (expanded) "Bilgiyi gizle" else "Stok bilgisi ⓘ", style = MaterialTheme.typography.labelMedium)
        }
        if (expanded) Text("Satırlar kendi biriminde, depo toplamları temel birimdedir. Bin takibi olmayan stoklar dahil değildir.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
