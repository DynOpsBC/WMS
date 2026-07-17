package com.dynops.bcwms.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.json.JSONObject

/**
 * Konfigüre edilebilir kolonlu satır tablosu (Warehouse Insight grid pariteti).
 * Başlık satırı + veri satırları; kolonlar [ColumnPrefs] düzenine göre görünür/
 * gizli, sıralı ve genişlikli. Yatay kaydırma başlık ve satırlarda ortaktır.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LineGrid(
    defs: List<GridColumn>,
    columns: List<ColumnState>,
    rows: List<JSONObject>,
    onRowClick: (JSONObject) -> Unit,
    modifier: Modifier = Modifier,
    isSelected: (JSONObject) -> Boolean = { false },
    isDone: (JSONObject) -> Boolean = { false },
    isPartial: (JSONObject) -> Boolean = { false },
) {
    val byKey = remember(defs) { defs.associateBy { it.key } }
    val visible = columns.filter { it.visible }.mapNotNull { c -> byKey[c.key]?.let { it to c.width } }
    val hScroll = rememberScrollState()
    val success = bcwmsStatus().success
    val warning = bcwmsStatus().warning

    Column(modifier) {
        // Başlık satırı
        Row(
            Modifier.fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .horizontalScroll(hScroll)
        ) {
            visible.forEach { (def, w) ->
                Text(
                    def.label,
                    Modifier.width(w.dp).padding(horizontal = 6.dp, vertical = 8.dp),
                    fontWeight = FontWeight.Bold, fontSize = 12.sp, maxLines = 1,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
        }
        HorizontalDivider()
        LazyColumn(Modifier.fillMaxWidth()) {
            items(rows) { row ->
                val sel = isSelected(row); val done = isDone(row); val partial = !done && isPartial(row)
                val bg = when {
                    sel -> MaterialTheme.colorScheme.primary.copy(alpha = 0.20f)
                    done -> success.copy(alpha = 0.13f)
                    // Kısmi işlenmiş satır (kalan var): sarı — "bitti" sanılmasın.
                    partial -> warning.copy(alpha = 0.15f)
                    else -> Color.Transparent
                }
                Row(
                    Modifier.fillMaxWidth().background(bg)
                        .clickable { onRowClick(row) }
                        .horizontalScroll(hScroll)
                ) {
                    visible.forEach { (def, w) ->
                        Text(
                            def.value(row).ifBlank { "—" },
                            Modifier.width(w.dp).padding(horizontal = 6.dp, vertical = 11.dp),
                            fontSize = 13.sp, maxLines = 1,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
                HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant)
            }
            if (rows.isEmpty()) item { Text("Satır yok.", Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}

/**
 * "Kolonları Seç" — WI "Choose Columns" ekranının karşılığı. Kolon listesi
 * (tıkla-seç), yukarı/aşağı ile sırala, seçili kolon için Görünür anahtarı ve
 * Genişlik kaydırıcısı. OK kaydeder.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChooseColumnsSheet(
    defs: List<GridColumn>,
    initial: List<ColumnState>,
    onDismiss: () -> Unit,
    onSave: (List<ColumnState>) -> Unit,
) {
    val labelOf = remember(defs) { defs.associate { it.key to it.label } }
    var cols by remember { mutableStateOf(initial) }
    var sel by remember { mutableStateOf(0) }

    fun move(delta: Int) {
        val to = sel + delta
        if (to < 0 || to >= cols.size) return
        val m = cols.toMutableList()
        val tmp = m[sel]; m[sel] = m[to]; m[to] = tmp
        cols = m; sel = to
    }
    fun update(i: Int, transform: (ColumnState) -> ColumnState) {
        cols = cols.toMutableList().also { it[i] = transform(it[i]) }
    }

    SheetScaffold(onDismiss = onDismiss, contentPadding = PaddingValues(16.dp)) {
        Text("Kolonları Seç", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text("Sırala (▲▼), göster/gizle ve genişlik ayarla.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(10.dp))
        Row(Modifier.height(280.dp)) {
            LazyColumn(
                Modifier.weight(1f).fillMaxHeight()
                    .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(8.dp))
            ) {
                itemsIndexed(cols) { i, c ->
                    val selected = i == sel
                    Row(
                        Modifier.fillMaxWidth()
                            .background(if (selected) bcwmsStatus().warning else Color.Transparent)
                            .clickable { sel = i }
                            .padding(horizontal = 12.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            labelOf[c.key] ?: c.key,
                            Modifier.weight(1f),
                            fontSize = 15.sp,
                            fontWeight = if (c.visible) FontWeight.SemiBold else FontWeight.Normal,
                            color = if (selected) Color.White else if (c.visible) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (!c.visible) Text("gizli", fontSize = 11.sp, color = if (selected) Color.White else MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
            Spacer(Modifier.width(10.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.align(Alignment.CenterVertically)) {
                FilledTonalButton(onClick = { move(-1) }, enabled = sel > 0, contentPadding = PaddingValues(12.dp)) { Text("▲", fontSize = 18.sp) }
                FilledTonalButton(onClick = { move(1) }, enabled = sel < cols.size - 1, contentPadding = PaddingValues(12.dp)) { Text("▼", fontSize = 18.sp) }
            }
        }
        Spacer(Modifier.height(12.dp))
        // Seçili kolonun ayarları
        val c = cols.getOrNull(sel)
        if (c != null) {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                Column(Modifier.padding(12.dp)) {
                    Text(labelOf[c.key] ?: c.key, fontWeight = FontWeight.Bold)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Görünür:", Modifier.weight(1f))
                        Switch(checked = c.visible, onCheckedChange = { v -> update(sel) { it.copy(visible = v) } })
                    }
                    Text("Genişlik: ${c.width}", fontSize = 13.sp)
                    Slider(
                        value = c.width.toFloat(),
                        onValueChange = { v -> update(sel) { it.copy(width = v.toInt()) } },
                        valueRange = 40f..260f,
                    )
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f).height(50.dp)) { Text("İPTAL") }
            Button(onClick = { onSave(cols) }, modifier = Modifier.weight(1f).height(50.dp)) { Text("OK", fontWeight = FontWeight.Bold) }
        }
        Spacer(Modifier.height(16.dp))
    }
}
