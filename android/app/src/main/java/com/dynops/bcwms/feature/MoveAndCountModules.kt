package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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

/**
 * Ad-Hoc Move — WI §10.5.
 * Single screen: scan from-bin -> scan item/LP -> scan to-bin -> qty -> Confirm.
 * Posts to movements/Microsoft.NAV.adhoc. NOTE: the deployed sandbox API does not yet
 * expose the `movements` entity set (verified HTTP 404), so Confirm surfaces that state
 * cleanly instead of crashing — re-enable once the AL extension publishes the page.
 */
@Composable
fun AdHocMoveModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var fromBin by remember { mutableStateOf("") }
    var itemOrLp by remember { mutableStateOf("") }
    var toBin by remember { mutableStateOf("") }
    var qty by remember { mutableStateOf("1") }
    var lotNo by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().padding(16.dp).verticalScroll(rememberScrollState())) {
        Text("Ad-Hoc Bin-to-Bin Hareket", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Spacer(Modifier.height(12.dp))
        ScanField("Kaynak Bin", fromBin, { fromBin = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            fromBin = BarcodeIntentResolver.resolve(it).value
        })
        Spacer(Modifier.height(8.dp))
        ScanField("Item / LP", itemOrLp, { itemOrLp = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            val r = BarcodeIntentResolver.resolve(it)
            itemOrLp = r.value
            if (r.lotNo != null) lotNo = r.lotNo
        })
        Spacer(Modifier.height(8.dp))
        ScanField("Hedef Bin", toBin, { toBin = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            toBin = BarcodeIntentResolver.resolve(it).value
        })
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(qty, { qty = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Miktar") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(lotNo, { lotNo = it }, label = { Text("Lot No (opsiyonel)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Button(
            enabled = !busy && fromBin.isNotBlank() && toBin.isNotBlank() && itemOrLp.isNotBlank(),
            modifier = Modifier.fillMaxWidth().height(52.dp),
            onClick = {
                scope.launch {
                    busy = true; status = "Hareket gönderiliyor..."
                    val resolved = BarcodeIntentResolver.resolve(itemOrLp)
                    val isLp = resolved.kind == com.dynops.bcwms.scanner.BarcodeKind.Lp
                    val body = JSONObject().apply {
                        put("fromBin", fromBin.trim()); put("toBin", toBin.trim())
                        put("quantity", qty.toDoubleOrNull() ?: 0.0)
                        if (isLp) put("lpNo", itemOrLp.trim()) else put("itemNo", itemOrLp.trim())
                        if (lotNo.isNotBlank()) put("lotNo", lotNo.trim())
                    }.toString()
                    val r = BcApi.post(context, "movements/Microsoft.NAV.adhoc", body)
                    busy = false
                    status = when {
                        r.ok -> "PASS: Hareket kaydedildi (HTTP ${r.httpCode})"
                        r.httpCode == 404 -> "EMPTY: movements API'si sandbox'ta henüz yayında değil (HTTP 404). AL eklentisi yayınlandığında aktif olur."
                        else -> "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                    }
                }
            }
        ) { Text(if (busy) "Gönderiliyor..." else "✅ Hareketi Onayla", fontWeight = FontWeight.Bold) }
        Spacer(Modifier.height(12.dp))
        StatusText(status)
    }
}

/**
 * Inventory Count — WI §10.6.
 * Count sheet list -> document -> scan + counted qty -> Post.
 * NOTE: the deployed sandbox API does not yet expose `countSheets` (HTTP 404). The screen
 * lists sheets when available and shows a clean empty state otherwise.
 */
@Composable
fun CountModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var available by remember { mutableStateOf(true) }

    fun load() {
        scope.launch {
            loading = true; status = "Sayım sayfaları yükleniyor..."
            val r = BcApi.get(context, "countSheets?\$top=30")
            loading = false
            if (r.httpCode == 404) {
                available = false
                status = "EMPTY: countSheets API'si sandbox'ta henüz yayında değil (HTTP 404)."
                rows = emptyList()
            } else if (r.ok) {
                rows = BcApi.parseValueArray(r.body)
                status = if (rows.isEmpty()) "EMPTY: Sayım sayfası yok (HTTP ${r.httpCode})" else "PASS: ${rows.size} sayfa (HTTP ${r.httpCode})"
            } else {
                status = "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            }
        }
    }
    LaunchedEffect(Unit) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        if (!available) {
            EmptyState("Sayım modülü hazır (scan + counted qty + Post akışı). BC tarafında countSheets sayfası yayınlandığında otomatik aktif olur.")
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { d ->
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text(firstValue(d, "no", "batchName"), fontWeight = FontWeight.Bold)
                        Text("Lokasyon: ${firstValue(d, "locationCode")}", fontSize = 12.sp, color = Color.Gray)
                    }
                }
            }
        }
    }
}

/** A simple "coming soon" placeholder for Phase 2 modules. */
@Composable
fun ComingSoonScreen(title: String, note: String) {
    Column(Modifier.fillMaxSize().padding(24.dp)) {
        Text(title, fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Spacer(Modifier.height(12.dp))
        Card(colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF3E0))) {
            Column(Modifier.padding(16.dp)) {
                Text("Yakında (Faz 2)", fontWeight = FontWeight.Bold, color = Color(0xFFEF6C00))
                Spacer(Modifier.height(6.dp))
                Text(note, fontSize = 13.sp)
            }
        }
    }
}
