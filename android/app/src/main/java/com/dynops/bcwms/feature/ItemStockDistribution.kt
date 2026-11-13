package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
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
internal fun LazyListScope.itemStockDistribution(state: ItemStockDistributionState, baseUom: String) {
    item(key = "stock-heading") {
        Text("Nerede, ne kadar?", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
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
            items(location.bins, key = { "stock-bin:${location.code.length}:${location.code}:${it.code}" }) { bin ->
                Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp),
                    color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f)) {
                    Column(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        bin.rows.forEach { row ->
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Column(Modifier.weight(1f)) {
                                    Text(bin.code.ifBlank { "Binsiz / depo gözü yok" }, fontWeight = FontWeight.Bold)
                                    Text("${location.code.ifBlank { "Lokasyonsuz" }} · Alan: ${row.optString("zoneCode").ifBlank { "—" }}",
                                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    row.optString("variantCode").takeIf { it.isNotBlank() }?.let {
                                        Text("Varyant: $it", style = MaterialTheme.typography.labelSmall)
                                    }
                                }
                                val quantity = row.getDouble("quantity")
                                Text("${formatStockQuantity(quantity)} ${row.optString("unitOfMeasureCode").ifBlank { "—" }}",
                                    fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium,
                                    color = if (quantity < 0) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
                            }
                        }
                    }
                }
            }
        }
    }
    if (!state.loading && !state.failed) item(key = "stock-note") {
        Text("Satırlar kendi biriminde, depo toplamları temel birimdedir. Bin takibi olmayan stoklar dahil değildir.",
            style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
