package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
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
    var query by remember { mutableStateOf("1004") }
    var item by remember { mutableStateOf<JSONObject?>(null) }
    var lpLines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("Item No tarayın/girin.") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
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
    LaunchedEffect(Unit) { load() }

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
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp), colors = CardDefaults.cardColors(containerColor = Color(0xFFE3F2FD))) {
                Column(Modifier.padding(16.dp)) {
                    Text(firstValue(it, "no", "number"), fontWeight = FontWeight.Bold, fontSize = 18.sp)
                    Text(firstValue(it, "description", "displayName"), fontSize = 14.sp)
                    Spacer(Modifier.height(4.dp))
                    Text("Base UoM: ${firstValue(it, "baseUnitOfMeasure", "baseUoM")}", fontSize = 12.sp, color = Color.Gray)
                    Text("Kategori: ${firstValue(it, "itemCategoryCode")} · LP Template: ${firstValue(it, "defaultLpTemplateCode")}", fontSize = 12.sp, color = Color.Gray)
                    val totalOnLp = lpLines.sumOf { l -> l.optDouble("quantity") }
                    Text("LP'lerdeki toplam: $totalOnLp", fontSize = 13.sp, fontWeight = FontWeight.Medium)
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

/** Bin Inquiry — bin card + LPs located in the bin. */
@Composable
fun BinInquiryModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var location by remember { mutableStateOf("SILVER") }
    var binCode by remember { mutableStateOf("S-1-01") }
    var bin by remember { mutableStateOf<JSONObject?>(null) }
    var lps by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("Lokasyon + Bin girin.") }
    var loading by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            bin = null; lps = emptyList()
            val loc = location.trim(); val code = binCode.trim()
            val b = BcApi.get(context, "bins?\$filter=locationCode eq '$loc' and code eq '$code'&\$top=1")
            if (b.ok) bin = BcApi.parseValueArray(b.body).firstOrNull()
            val l = BcApi.get(context, "licensePlates?\$filter=locationCode eq '$loc' and binCode eq '$code'&\$top=50")
            if (l.ok) lps = BcApi.parseValueArray(l.body)
            loading = false
            status = if (bin == null && lps.isEmpty()) "EMPTY: '$loc/$code' için içerik yok." else "PASS: ${lps.size} LP bu bin'de."
        }
    }
    LaunchedEffect(Unit) { load() }

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
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp), colors = CardDefaults.cardColors(containerColor = Color(0xFFE8F5E9))) {
                Column(Modifier.padding(16.dp)) {
                    Text("${firstValue(b, "locationCode")} / ${firstValue(b, "code")}", fontWeight = FontWeight.Bold, fontSize = 18.sp)
                    Text(firstValue(b, "description"), fontSize = 13.sp)
                    Text("Zone: ${firstValue(b, "zoneCode")} · Type: ${firstValue(b, "binTypeCode")}", fontSize = 12.sp, color = Color.Gray)
                }
            }
            Spacer(Modifier.height(8.dp))
        }
        Text("License Plate'ler (${lps.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
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
