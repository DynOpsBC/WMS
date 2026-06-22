package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.launch
import org.json.JSONObject

/** Item Inquiry — item card + LP lines that contain the item (on-hand by LP). */
@Composable
fun ItemInquiryModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // PDF Item Inquiry §1: hardcoded "1004" preset removed — start empty so
    // the screen does not falsely claim an item exists before the operator
    // scans/types one.
    var query by remember { mutableStateOf("") }
    var item by remember { mutableStateOf<JSONObject?>(null) }
    var lpLines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("Item No tarayın/girin.") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        if (query.trim().isBlank()) return
        scope.launch {
            loading = true; status = "Sorgulanıyor..."
            item = null; lpLines = emptyList()
            val q = query.trim()
            val r = BcApi.getWithStandardFallback(context, "items?\$filter=no eq '$q'&\$top=1", "items?\$filter=number eq '$q'&\$top=1")
            if (r.ok) {
                val list = BcApi.parseValueArray(r.body)
                item = list.firstOrNull()
            }
            // on-hand by LP: lines for this item across license plates
            val l = BcApi.get(context, "licensePlateLines?\$filter=itemNo eq '$q'&\$top=50")
            if (l.ok) lpLines = BcApi.parseValueArray(l.body)
            loading = false
            status = if (item == null) "EMPTY: '$q' için item bulunamadı." else "PASS: item bulundu · ${lpLines.size} LP satırı."
        }
    }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        ScanField("Item No", query, { query = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            query = BarcodeIntentResolver.resolve(it).itemNo ?: it
        })
        Spacer(Modifier.height(8.dp))
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔎 Sorgula") }
        Spacer(Modifier.height(8.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        item?.let { it ->
            val blocked = it.optBoolean("blocked", false)
            val inventory = it.optDouble("inventory", Double.NaN)
            val qtyOnPo = it.optDouble("quantityOnPurchOrder", 0.0)
            val qtyOnSo = it.optDouble("quantityOnSalesOrder", 0.0)
            val qtyOnProd = it.optDouble("quantityOnProdOrder", 0.0)
            val reserved = it.optDouble("reservedQtyOnInventory", 0.0)
            val uom = firstValue(it, "baseUnitOfMeasure", "baseUoM")
            val available = (if (inventory.isNaN()) 0.0 else inventory) - reserved
            val totalOnLp = lpLines.sumOf { l -> l.optDouble("quantity") }
            Card(
                Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (blocked) Color(0xFFFFEBEE) else Color(0xFFE3F2FD),
                ),
            ) {
                Column(Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(firstValue(it, "no", "number"), fontWeight = FontWeight.Bold, fontSize = 18.sp)
                        if (blocked) {
                            Spacer(Modifier.width(8.dp))
                            AssistChip(onClick = {}, label = { Text("🚫 Bloke", fontSize = 11.sp) }, colors = AssistChipDefaults.assistChipColors(containerColor = Color(0xFFEF5350), labelColor = Color.White))
                        }
                    }
                    Text(firstValue(it, "description", "displayName"), fontSize = 14.sp)
                    Spacer(Modifier.height(8.dp))
                    // Stock block — PDF Item Inquiry §1 critical fix.
                    if (!inventory.isNaN()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            StockTile("Stok", inventory, uom, Color(0xFF2E7D32))
                            StockTile("Müsait", available, uom, Color(0xFF1565C0))
                            StockTile("Rezerve", reserved, uom, Color(0xFFEF6C00))
                        }
                        Spacer(Modifier.height(6.dp))
                        Text("Gelen ${fmtItemQty(qtyOnPo)} · Giden ${fmtItemQty(qtyOnSo)} · Üretim ${fmtItemQty(qtyOnProd)}", fontSize = 11.sp, color = Color.Gray)
                    }
                    Spacer(Modifier.height(8.dp))
                    Text("Base UoM: $uom", fontSize = 12.sp, color = Color.Gray)
                    Text("Kategori: ${firstValue(it, "itemCategoryCode")} · LP Template: ${firstValue(it, "defaultLpTemplateCode")}", fontSize = 12.sp, color = Color.Gray)
                    Text("LP'lerdeki toplam: ${fmtItemQty(totalOnLp)} $uom", fontSize = 12.sp, color = Color.Gray)
                }
            }
            Spacer(Modifier.height(8.dp))
            Text("License Plate'lerde (${lpLines.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(lpLines) { ln ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(10.dp)) {
                        Text("${ln.optString("lpNo")} × ${ln.optDouble("quantity")}", fontWeight = FontWeight.Medium)
                        val extra = listOfNotNull(
                            ln.optString("lotNo").takeIf { it.isNotBlank() }?.let { "Lot $it" },
                            ln.optString("serialNo").takeIf { it.isNotBlank() }?.let { "Sr $it" }
                        ).joinToString(" · ")
                        if (extra.isNotBlank()) Text(extra, fontSize = 11.sp, color = Color.Gray)
                    }
                }
            }
            if (item != null && lpLines.isEmpty() && !loading) item { EmptyState("Bu item hiçbir LP'de bulunmuyor.") }
        }
    }
}

/** Bin Inquiry — bin card + real bin contents (item × qty) + LPs in the bin. */
@Composable
fun BinInquiryModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // PDF Bin Inquiry §2: hardcoded SILVER/S-1-01 preset removed.
    var location by remember { mutableStateOf("") }
    var binCode by remember { mutableStateOf("") }
    var bin by remember { mutableStateOf<JSONObject?>(null) }
    var contents by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var lps by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("Lokasyon + Bin girin.") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        if (location.trim().isBlank() || binCode.trim().isBlank()) return
        scope.launch {
            loading = true; status = "Yükleniyor..."
            bin = null; contents = emptyList(); lps = emptyList()
            val loc = location.trim(); val code = binCode.trim()
            val b = BcApi.get(context, "bins?\$filter=locationCode eq '$loc' and code eq '$code'&\$top=1")
            if (b.ok) bin = BcApi.parseValueArray(b.body).firstOrNull()
            // PDF Bin Inquiry §2 critical fix: now also fetch the real item
            // quantities from the new BinContent API page (T7302 Bin Content).
            val c = BcApi.get(context, "binContents?\$filter=locationCode eq '$loc' and binCode eq '$code'&\$top=100")
            if (c.ok) contents = BcApi.parseValueArray(c.body).filter { it.optDouble("quantity", 0.0) != 0.0 }
            val l = BcApi.get(context, "licensePlates?\$filter=locationCode eq '$loc' and binCode eq '$code'&\$top=50")
            if (l.ok) lps = BcApi.parseValueArray(l.body)
            loading = false
            status = if (bin == null && contents.isEmpty() && lps.isEmpty()) "EMPTY: '$loc/$code' için içerik yok."
                else "PASS: ${contents.size} item · ${lps.size} LP bu bin'de."
        }
    }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        ScanField("Lokasyon", location, { location = it }, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        ScanField("Bin", binCode, { binCode = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            binCode = BarcodeIntentResolver.resolve(it).value
        })
        Spacer(Modifier.height(8.dp))
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔎 Sorgula") }
        Spacer(Modifier.height(8.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        bin?.let { b ->
            val blocked = b.optBoolean("blockMovement", false)
            Card(
                Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = if (blocked) Color(0xFFFFEBEE) else Color(0xFFE8F5E9)),
            ) {
                Column(Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("${firstValue(b, "locationCode")} / ${firstValue(b, "code")}", fontWeight = FontWeight.Bold, fontSize = 18.sp)
                        if (blocked) {
                            Spacer(Modifier.width(8.dp))
                            AssistChip(onClick = {}, label = { Text("🚫 Block Movement", fontSize = 11.sp) }, colors = AssistChipDefaults.assistChipColors(containerColor = Color(0xFFEF5350), labelColor = Color.White))
                        }
                    }
                    Text(firstValue(b, "description").ifBlank { "—" }, fontSize = 13.sp)
                    Text("Zone: ${firstValue(b, "zoneCode").ifBlank { "—" }} · Type: ${firstValue(b, "binTypeCode").ifBlank { "—" }}", fontSize = 12.sp, color = Color.Gray)
                }
            }
            Spacer(Modifier.height(8.dp))
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.weight(1f)) {
            if (contents.isNotEmpty()) {
                item {
                    Text("Bin İçeriği (${contents.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp, modifier = Modifier.padding(vertical = 4.dp))
                }
                items(contents) { c ->
                    Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF8E1))) {
                        Row(
                            Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(c.optString("itemNo"), fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                val desc = c.optString("itemDescription")
                                if (desc.isNotBlank()) Text(desc, fontSize = 11.sp, color = Color.Gray)
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text(fmtItemQty(c.optDouble("quantity")), fontWeight = FontWeight.Bold, fontSize = 16.sp, color = Color(0xFF1565C0))
                                Text(c.optString("unitOfMeasureCode").ifBlank { "—" }, fontSize = 10.sp, color = Color.Gray)
                            }
                        }
                    }
                }
                item { Spacer(Modifier.height(8.dp)) }
            }
            item {
                Text("License Plate'ler (${lps.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp, modifier = Modifier.padding(vertical = 4.dp))
            }
            items(lps) { lp ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(10.dp)) {
                        Text("${lp.optString("no")} · ${lp.optString("status")}", fontWeight = FontWeight.Medium)
                        Text("${lp.optString("templateCode")}${lp.optString("sscc").takeIf { it.isNotBlank() }?.let { " · SSCC $it" } ?: ""}", fontSize = 11.sp, color = Color.Gray)
                    }
                }
            }
            if (lps.isEmpty() && !loading) item { EmptyState("Bu bin'de License Plate yok.") }
        }
    }
}

/** Format an item quantity with up to 2 decimals, stripping trailing zeros. */
internal fun fmtItemQty(q: Double): String {
    if (q.isNaN()) return "0"
    return if (q == q.toLong().toDouble()) q.toLong().toString() else "%.2f".format(q).trimEnd('0').trimEnd('.')
}

/** Compact stock tile used by ItemInquiry — label on top, qty bold, uom small. */
@Composable
private fun StockTile(label: String, qty: Double, uom: String, accent: Color) {
    Card(
        shape = RoundedCornerShape(8.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
    ) {
        Column(Modifier.padding(horizontal = 10.dp, vertical = 6.dp)) {
            Text(label, fontSize = 10.sp, color = Color.Gray)
            Text(fmtItemQty(qty), fontWeight = FontWeight.Bold, fontSize = 16.sp, color = accent)
            Text(uom.ifBlank { "—" }, fontSize = 10.sp, color = Color.Gray)
        }
    }
}
