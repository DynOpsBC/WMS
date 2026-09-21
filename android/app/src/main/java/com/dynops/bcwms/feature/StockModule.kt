package com.dynops.bcwms.feature

import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.launch
import org.json.JSONObject

private enum class StockFilterMode(val label: String) {
    ALL("Tümü"),
    CRITICAL("Kritik"),
    SPARE("Yedek Parça"),
    BLOCKED("Bloke"),
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun StockModule(onNavigateToInquiry: ((String) -> Unit)? = null) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    var allRows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Stok verileri yükleniyor...") }
    var searchFilter by remember { mutableStateOf("") }
    var activeFilter by rememberSaveable { mutableStateOf(StockFilterMode.ALL) }
    var pullOffset by remember { mutableFloatStateOf(0f) }
    val pullThreshold = 80f

    suspend fun loadStock() {
        loading = true
        status = "Stok listesi alınıyor..."
        val suffix = "\$select=no,description,baseUnitOfMeasure,itemCategoryCode,inventory,reservedQtyOnInventory,quantityOnPurchOrder,quantityOnSalesOrder,quantityOnProdOrder,blocked&\$top=300&\$orderby=inventory desc"
        val r = BcApi.getWithStandardFallback(
            context,
            "items?$suffix",
            "items?\$select=number,displayName,baseUnitOfMeasure,itemCategoryCode,inventory,blocked&\$top=300"
        )
        loading = false
        if (r.ok) {
            allRows = BcApi.parseValueArray(r.body)
            status = "TAMAM: Toplam ${allRows.size} ürün listelendi."
        } else {
            status = "HATA: Stok listesi alınamadı (HTTP ${r.httpCode}): ${BcApi.errorMessage(r.body)}"
        }
    }

    LaunchedEffect(Unit) {
        loadStock()
    }

    fun isCriticalStock(row: JSONObject): Boolean {
        val inventory = row.optDouble("inventory", 0.0)
        val safetyStock = row.optDouble("safetyStockQuantity", 0.0)
        return if (safetyStock > 0) {
            inventory <= safetyStock
        } else {
            // Güvenlik stoğu girilmemişse sıfır veya 5 adedin altı kritik kabul edilir
            inventory <= 5.0
        }
    }

    val palette = bcwmsStatus()

    // Client-side search and filtering
    val filteredRows = remember(allRows, searchFilter, activeFilter) {
        val needle = searchFilter.trim().lowercase()
        allRows.filter { row ->
            val no = firstValue(row, "no", "number").lowercase()
            val desc = firstValue(row, "description", "displayName").lowercase()
            val cat = firstValue(row, "itemCategoryCode").lowercase()
            val matchesSearch = needle.isBlank() || no.contains(needle) || desc.contains(needle) || cat.contains(needle)
            if (!matchesSearch) return@filter false

            when (activeFilter) {
                StockFilterMode.ALL -> true
                StockFilterMode.CRITICAL -> isCriticalStock(row)
                StockFilterMode.SPARE -> isSparePart(row)
                StockFilterMode.BLOCKED -> row.optBoolean("blocked", false)
            }
        }
    }

    val criticalCount = remember(allRows) { allRows.count { isCriticalStock(it) } }
    val spareCount = remember(allRows) { allRows.count { isSparePart(it) } }
    val blockedCount = remember(allRows) { allRows.count { it.optBoolean("blocked", false) } }

    Column(
        Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectVerticalDragGestures(
                    onDragEnd = {
                        if (pullOffset > pullThreshold && !loading) {
                            scope.launch { loadStock() }
                        }
                        pullOffset = 0f
                    },
                    onDragCancel = { pullOffset = 0f },
                    onVerticalDrag = { change, dragAmount ->
                        if (listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset == 0) {
                            if (dragAmount > 0 || pullOffset > 0) {
                                pullOffset = (pullOffset + dragAmount * 0.5f).coerceIn(0f, 150f)
                                change.consume()
                            }
                        }
                    }
                )
            }
            .padding(12.dp)
    ) {
        // Aşağı çekip yenileme göstergesi
        if (pullOffset > 10f) {
            Surface(
                modifier = Modifier.fillMaxWidth().height((pullOffset * 0.55f).coerceIn(32f, 54f).dp),
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.85f),
            ) {
                Row(
                    Modifier.fillMaxSize(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    WmsIcon(
                        glyph = WmsGlyph.REFRESH,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        if (pullOffset >= pullThreshold) "Yenilemek için bırakın" else "Yenilemek için aşağı çekin...",
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSecondaryContainer
                    )
                }
            }
            Spacer(Modifier.height(6.dp))
        }

        // Arama ve Yenileme Butonu
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedTextField(
                value = searchFilter,
                onValueChange = { searchFilter = it },
                label = { Text("Ürün kodu veya adı") },
                shape = RoundedCornerShape(12.dp),
                singleLine = true,
                modifier = Modifier.weight(1f),
                trailingIcon = if (searchFilter.isNotEmpty()) {
                    {
                        IconButton(onClick = { searchFilter = "" }) {
                            WmsIcon(WmsGlyph.CLOSE, MaterialTheme.colorScheme.onSurfaceVariant, Modifier.size(16.dp))
                        }
                    }
                } else null
            )
            Button(
                onClick = { scope.launch { loadStock() } },
                enabled = !loading,
                modifier = Modifier.size(52.dp),
                shape = RoundedCornerShape(12.dp),
                contentPadding = PaddingValues(horizontal = 14.dp)
            ) {
                WmsRefreshLabel(loading, compact = true)
            }
        }

        Spacer(Modifier.height(8.dp))

        // Two equal columns keep labels readable on handheld screens.
        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            maxItemsInEachRow = 2,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val filters = listOf(
                StockFilterMode.ALL to allRows.size,
                StockFilterMode.CRITICAL to criticalCount,
                StockFilterMode.SPARE to spareCount,
            ) + if (blockedCount > 0) listOf(StockFilterMode.BLOCKED to blockedCount) else emptyList()
            filters.forEach { (filter, count) ->
                FilterChip(
                    selected = activeFilter == filter,
                    onClick = { activeFilter = filter },
                    label = {
                        Text(
                            "${filter.label} ($count)",
                            style = MaterialTheme.typography.labelMedium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    },
                    modifier = Modifier.weight(1f).heightIn(min = 40.dp),
                    shape = RoundedCornerShape(10.dp),
                )
            }
        }

        if (loading || status.startsWith("HATA:")) {
            Spacer(Modifier.height(4.dp))
            StatusText(status)
        } else {
            Text(
                "${filteredRows.size} ürün gösteriliyor · Toplam ${allRows.size}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = 8.dp),
            )
        }
        Spacer(Modifier.height(4.dp))

        // Liste
        if (loading && allRows.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else if (filteredRows.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(top = 40.dp), contentAlignment = Alignment.Center) {
                Text(
                    if (searchFilter.isNotBlank()) "'$searchFilter' için ürün bulunamadı."
                    else "Bu filtrede listelenecek ürün yok.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        } else {
            LazyColumn(
                state = listState,
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(filteredRows, key = { firstValue(it, "no", "number") }) { row ->
                    val no = firstValue(row, "no", "number")
                    val desc = firstValue(row, "description", "displayName")
                    val uom = firstValue(row, "baseUnitOfMeasure", "baseUoM").ifBlank { "ADET" }
                    val inventory = row.optDouble("inventory", 0.0)
                    val reserved = row.optDouble("reservedQtyOnInventory", 0.0)
                    val available = inventory - reserved
                    val category = rawValue(row, "itemCategoryCode").takeUnless { it == "-" }.orEmpty()
                    val blocked = row.optBoolean("blocked", false)
                    val critical = isCriticalStock(row)
                    val isSpare = isSparePart(row)

                    Card(
                        modifier = Modifier.fillMaxWidth().then(
                            if (onNavigateToInquiry != null) Modifier.clickable { onNavigateToInquiry(no) }
                            else Modifier
                        ),
                        shape = RoundedCornerShape(14.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                        border = androidx.compose.foundation.BorderStroke(
                            1.dp,
                            if (critical || blocked) palette.danger.copy(alpha = 0.25f)
                            else MaterialTheme.colorScheme.outlineVariant,
                        ),
                    ) {
                        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text(
                                    no,
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onSurface,
                                )
                                if (desc.isNotBlank() && desc != no) {
                                    Text(
                                        desc,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                            if (critical || blocked || isSpare) {
                                FlowRow(
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                    verticalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    if (critical) StockBadge("Kritik stok", danger = true)
                                    if (blocked) StockBadge("Bloke", danger = true)
                                    if (isSpare) StockBadge("Yedek parça")
                                }
                            }
                            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text("Stok", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text(
                                        "${fmtItemQty(inventory)} $uom",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.Bold,
                                        color = if (critical) palette.danger else MaterialTheme.colorScheme.onSurface,
                                    )
                                }
                                Column(Modifier.weight(1f), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text("Müsait", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text(
                                        "${fmtItemQty(available)} $uom",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.Bold,
                                        color = if (available <= 0) palette.danger else MaterialTheme.colorScheme.onSurface,
                                    )
                                }
                            }
                            if (category.isNotBlank() || reserved > 0) {
                                Text(
                                    listOfNotNull(
                                        category.takeIf { it.isNotBlank() }?.let { "Kategori: $it" },
                                        if (reserved > 0) "Rezerve: ${fmtItemQty(reserved)} $uom" else null,
                                    ).joinToString(" · "),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StockBadge(label: String, danger: Boolean = false) {
    val color = if (danger) bcwmsStatus().danger else MaterialTheme.colorScheme.primary
    Surface(color = color.copy(alpha = 0.09f), shape = RoundedCornerShape(6.dp)) {
        Text(
            label,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            color = color,
            maxLines = 1,
        )
    }
}
