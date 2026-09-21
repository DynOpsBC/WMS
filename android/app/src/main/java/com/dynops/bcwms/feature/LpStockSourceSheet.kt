package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.dynops.bcwms.BcApi
import org.json.JSONObject

internal data class LpStockSourceKey(
    val itemNo: String,
    val locationCode: String,
    val lotNo: String,
    val serialNo: String,
    val variantCode: String = "",
)

internal data class LpStockSourceEntry(
    val entryNo: Int,
    val documentNo: String,
    val postingDate: String,
    val available: Double,
    val baseUom: String,
)

internal fun lpStockSourcePath(key: LpStockSourceKey): String {
    fun eq(field: String, value: String) = "$field eq '${value.replace("'", "''")}'"
    val filter = listOf(
        eq("itemNo", key.itemNo), eq("locationCode", key.locationCode),
        eq("lotNo", key.lotNo), eq("serialNo", key.serialNo), eq("variantCode", key.variantCode),
        "quantity gt 0", "remainingQuantity gt 0",
    ).joinToString(" and ")
    return "itemLedgerEntries?\$filter=$filter&\$orderby=postingDate,entryNo"
}

internal fun lpStockSourceEntries(rows: List<JSONObject>, key: LpStockSourceKey): List<LpStockSourceEntry> =
    rows.mapNotNull { row ->
        val matches = listOf(
            "itemNo" to key.itemNo, "locationCode" to key.locationCode,
            "lotNo" to key.lotNo, "serialNo" to key.serialNo, "variantCode" to key.variantCode,
        ).all { (field, expected) -> row.optString(field) == expected }
        val available = row.optDouble("lpAllocatableQuantity", Double.NaN)
        val entryNo = row.optInt("entryNo")
        if (!matches || entryNo <= 0 || row.optDouble("quantity", 0.0) <= 0.0 ||
            !available.isFinite() || available <= 0.0) null
        else LpStockSourceEntry(
            entryNo, row.optString("documentNo"), row.optString("postingDate"),
            available, row.optString("baseUnitOfMeasure"),
        )
    }.distinctBy { it.entryNo }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LpStockSourceSheet(
    source: LpStockSourceKey,
    quantityLabel: String,
    repair: Boolean,
    onDismiss: () -> Unit,
    onChoose: (Int) -> Unit,
) {
    val context = LocalContext.current
    var loading by remember(source) { mutableStateOf(true) }
    var error by remember(source) { mutableStateOf("") }
    var entries by remember(source) { mutableStateOf<List<LpStockSourceEntry>>(emptyList()) }
    var selected by remember(source) { mutableStateOf<Int?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    LaunchedEffect(source, reload) {
        loading = true
        error = ""
        selected = null
        entries = emptyList()
        val page = BcApi.getAllPages(context, lpStockSourcePath(source))
        if (!page.complete) error = "Kaynak girişleri tamamen yüklenemedi. Yeniden deneyin."
        else {
            entries = lpStockSourceEntries(page.rows, source)
            if (entries.isEmpty()) error = "Bu ürün, lot ve lokasyonda LP'ye ayrılabilir kaynak giriş bulunamadı."
        }
        loading = false
    }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 24.dp)) {
            Text(if (repair) "Kaynak Girişi Bağla" else "Kaynak Stok Girişi", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(8.dp))
            Text("${source.itemNo} · $quantityLabel", fontWeight = FontWeight.Bold)
            if (source.lotNo.isNotBlank()) Text("Lot: ${source.lotNo}")
            Text(
                if (repair) "Bu satırın alındığı belgeyi seçin. Bağlantı kurulur; stok miktarı değişmez."
                else "Ürünü aldığınız belgeyi seçin. Miktar birden fazla girişten geliyorsa her giriş için ayrı satır ekleyin.",
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(vertical = 8.dp),
            )
            if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            if (error.isNotBlank()) {
                Text(error, color = MaterialTheme.colorScheme.error)
                TextButton(onClick = { reload++ }) { Text("Yeniden Dene") }
            }
            LazyColumn(Modifier.fillMaxWidth().heightIn(max = 350.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(entries, key = { it.entryNo }) { entry ->
                    val selectable = entry.documentNo.isNotBlank()
                    OutlinedCard(onClick = { selected = entry.entryNo }, enabled = selectable, modifier = Modifier.fillMaxWidth()) {
                        Row(Modifier.padding(10.dp)) {
                            RadioButton(selected = selected == entry.entryNo, onClick = { selected = entry.entryNo }, enabled = selectable)
                            Column(Modifier.weight(1f).padding(start = 4.dp)) {
                                Text(entry.documentNo.ifBlank { "Belge no eksik — bağlanamaz" }, fontWeight = FontWeight.Bold)
                                Text("${entry.postingDate} · Giriş #${entry.entryNo}", style = MaterialTheme.typography.bodySmall)
                                Text("LP'ye ayrılabilir: ${entry.available} ${entry.baseUom}", style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = { selected?.let(onChoose) }, enabled = !loading && error.isBlank() && selected != null,
                modifier = Modifier.fillMaxWidth().height(50.dp),
            ) { Text(if (repair) "Seçilen Girişi Bağla" else "Seçilen Girişten Ekle") }
        }
    }
}
