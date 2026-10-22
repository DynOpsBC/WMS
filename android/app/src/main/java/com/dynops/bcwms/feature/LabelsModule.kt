package com.dynops.bcwms.feature

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.ui.StatusText
import com.dynops.bcwms.ui.WmsRefreshLabel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Existing thermal label actions retain the configured BC label design.
 * Kitoko (19 Eki 2026): DKÇ/EMU "Etiket Çıkar" ekranı; raf ve ürün sekmeleri
 * Bin/Ürün Sorgu modüllerinin labelsOnly akışını açar.
 */
@Composable
fun LabelsModule() {
    var tab by remember { mutableStateOf(0) }
    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab) {
            Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Raf Etiketi") })
            Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Ürün Etiketi") })
            // Kitoko (22 Eki 2026): LP okut → içerik + LP / lot etiketi.
            Tab(selected = tab == 2, onClick = { tab = 2 }, text = { Text("LP Etiketi") })
        }
        Box(Modifier.weight(1f)) {
            when (tab) {
                0 -> BinInquiryModule(labelsOnly = true)
                1 -> ItemInquiryModule(labelsOnly = true)
                else -> LpLabelTab()
            }
        }
    }
}

/**
 * Kitoko (22 Eki 2026): Etiket Çıkar → LP Etiketi. LP QR'ı (LP No) ya da SSCC
 * okutulur veya yazılır; ya da listeden seçilir (aktif LP'ler, LP no / ürün / lot /
 * raf ile arama, en yeni üstte). LP kartı içerikle açılır, LP / lot etiketi buradan basılır.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LpLabelTab() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }
    var ref by remember { mutableStateOf<LpScanRef?>(null) }
    var openedByScan by remember { mutableStateOf(false) }
    var activeOnly by remember { mutableStateOf(true) }
    var rows by remember { mutableStateOf<List<LpLookupRow>>(emptyList()) }
    var hasMore by remember { mutableStateOf(false) }
    var listStatus by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var reloadTick by remember { mutableStateOf(0) }

    fun openLp(next: LpScanRef, byScan: Boolean) {
        ref = next
        openedByScan = byScan
        if (byScan) query = next.value
    }
    fun submit(raw: String) {
        val value = raw.trim()
        if (value.isEmpty()) return
        val lp = lpScanRef(value)
        if (lp != null) {
            openLp(lp, byScan = true)
            return
        }
        // Özel serili LP no (ör. PAL-0001) listede birebir varsa doğrudan açılır.
        val exact = lpLookupExactMatch(rows, value)
        if (exact != null) openLp(LpScanRef.ByNo(exact), byScan = true)
        else query = lpLookupQueryFromScan(value)
    }
    // Alan odakta değilken de (ör. yazdırdıktan sonra) donanım okutması yeni LP'yi açar.
    LpScanListener(enabled = true) { openLp(it, byScan = true) }

    Column(Modifier.fillMaxSize()) {
        com.dynops.bcwms.scanner.ScanField(
            "LP okut ya da ara (LP no, ürün, lot, raf)", query, { query = it },
            modifier = Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 12.dp),
            onScanned = { submit(it) },
            onClear = if (query.isNotEmpty()) ({ query = "" }) else null,
        )
        val current = ref
        if (current != null) {
            LpContentCard(
                ref = current,
                onClose = { ref = null; if (openedByScan) query = "" },
                closeLabel = if (openedByScan) "× Kapat" else "‹ LP Listesi",
                modifier = Modifier.weight(1f),
            )
            return@Column
        }

        // Liste: yazdıkça (kısa gecikmeyle) ilk sayfa yeniden okunur; "Daha fazla" sonraki sayfa.
        LaunchedEffect(query, activeOnly, reloadTick) {
            delay(if (query.isBlank()) 0L else 350L)
            loading = true
            listStatus = "LP'ler yükleniyor..."
            when (val result = loadLpLookupPage(context, query, activeOnly, skip = 0)) {
                is LpLookupLoad.Ready -> {
                    rows = result.rows
                    hasMore = result.hasMore
                    listStatus = when {
                        result.rows.isEmpty() && query.isNotBlank() -> "BOŞ: '${query.trim()}' ile eşleşen LP yok" + if (activeOnly) " (yalnız aktif LP'ler; \"Tümü\"nü deneyin)." else "."
                        result.rows.isEmpty() -> if (activeOnly) "BOŞ: Aktif LP yok." else "BOŞ: LP kaydı yok."
                        else -> result.note
                    }
                }
                is LpLookupLoad.Failed -> {
                    rows = emptyList()
                    hasMore = false
                    listStatus = result.status
                }
            }
            loading = false
        }
        fun loadMore() {
            if (loading) return
            val q = query
            val active = activeOnly
            val skip = rows.size
            scope.launch {
                loading = true
                val result = loadLpLookupPage(context, q, active, skip)
                if (q == query && active == activeOnly) when (result) {
                    is LpLookupLoad.Ready -> {
                        rows = (rows + result.rows).distinctBy { it.no }
                        hasMore = result.hasMore
                        if (result.note.isNotBlank()) listStatus = result.note
                    }
                    is LpLookupLoad.Failed -> listStatus = result.status
                }
                loading = false
            }
        }

        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FilterChip(selected = activeOnly, onClick = { activeOnly = true }, label = { Text("Aktif LP'ler") })
            FilterChip(selected = !activeOnly, onClick = { activeOnly = false }, label = { Text("Tümü") })
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { reloadTick++ }, enabled = !loading) { WmsRefreshLabel(loading) }
        }
        if (listStatus.isNotBlank()) Box(Modifier.padding(horizontal = 12.dp)) { StatusText(listStatus) }
        LazyColumn(
            Modifier.weight(1f).fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            items(rows, key = { it.no }) { row -> LpLookupCard(row) { openLp(LpScanRef.ByNo(row.no), byScan = false) } }
            if (hasMore) item {
                OutlinedButton(onClick = { loadMore() }, enabled = !loading, modifier = Modifier.fillMaxWidth().height(48.dp)) {
                    Text(if (loading) "Yükleniyor..." else "Daha fazla LP")
                }
            }
            if (rows.isEmpty() && !loading) item {
                Text(
                    "LP etiketindeki QR'ı okutun ya da listeden LP seçin: içerik (ürün, lot, SKT, miktar) açılır; LP etiketi ve lot etiketi buradan basılır.",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(vertical = 8.dp),
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LpLookupCard(row: LpLookupRow, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(row.no, fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.weight(1f))
                if (row.totals.isNotBlank()) Text(
                    row.totals, fontWeight = FontWeight.Bold, fontSize = 14.sp,
                    color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(end = 8.dp),
                )
                LpStatusBadge(row.status)
            }
            Text(
                listOf(row.locationCode, row.binCode.ifBlank { "göz atanmadı" }).filter { it.isNotBlank() }.joinToString(" / "),
                fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (row.firstItemNo.isNotBlank()) Text(
                listOf(row.firstItemNo, row.firstItemDescription).filter { it.isNotBlank() }.joinToString(" · ") +
                    if (row.otherItemCount > 0) " (+${row.otherItemCount} ürün)" else "",
                fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            lpLookupLotsLabel(row.lots).takeIf { it.isNotBlank() }?.let {
                Text("Lot: $it", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
