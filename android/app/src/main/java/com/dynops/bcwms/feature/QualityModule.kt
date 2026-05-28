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

/**
 * Quality (Kalite) — manage quality inspection orders from the handheld.
 * Lists open quality orders; the inspector PASSES (release) or FAILS (→ quarantine bin) each.
 * BC: qualityOrders / pass / fail / createOrder (warehouse/v2.0).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QualityModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var showOnlyOpen by remember { mutableStateOf(true) }
    var inspectOrder by remember { mutableStateOf<JSONObject?>(null) }

    fun load() {
        scope.launch {
            loading = true; status = "Kalite emirleri yükleniyor..."
            val r = BcApi.get(context, "qualityOrders?\$top=50&\$orderby=no&\$select=no,sourceType,sourceNo,itemNo,itemDescription,quantity,sampleSize,status,inspector,resultNotes,quarantineBin")
            loading = false
            val all = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            rows = if (showOnlyOpen) all.filter { it.optString("status") == "Open" } else all
            status = if (!r.ok) "HATA: Kalite emirleri alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "EMPTY: ${if (showOnlyOpen) "Açık kalite emri yok" else "Kalite emri yok"} (HTTP ${r.httpCode})"
                else "PASS: ${rows.size} kalite emri (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(showOnlyOpen) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
            Spacer(Modifier.width(12.dp))
            FilterChip(selected = showOnlyOpen, onClick = { showOnlyOpen = true }, label = { Text("Açık") })
            Spacer(Modifier.width(6.dp))
            FilterChip(selected = !showOnlyOpen, onClick = { showOnlyOpen = false }, label = { Text("Tümü") })
        }
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { d ->
                val st = d.optString("status")
                val (bg, fg) = when (st) {
                    "Passed" -> Color(0xFFE8F5E9) to Color(0xFF2E7D32)
                    "Failed" -> Color(0xFFFFEBEE) to Color(0xFFC62828)
                    else -> Color(0xFFFFF8E1) to Color(0xFFEF6C00)
                }
                Card(
                    onClick = { if (st == "Open") inspectOrder = d },
                    modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)
                ) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(d.optString("no"), fontWeight = FontWeight.Bold)
                            Surface(color = bg, shape = RoundedCornerShape(6.dp)) {
                                Text(st, Modifier.padding(horizontal = 8.dp, vertical = 2.dp), color = fg, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                        Text("${d.optString("itemNo")} — ${firstValue(d, "itemDescription")}", fontSize = 13.sp)
                        Text("Adet: ${d.optDouble("quantity")} · Numune: ${d.optDouble("sampleSize")} · Kaynak: ${firstValue(d, "sourceNo")}", fontSize = 12.sp, color = Color.Gray)
                        if (st != "Open") {
                            val notes = d.optString("resultNotes")
                            Text("Denetçi: ${firstValue(d, "inspector")}${if (notes.isNotBlank()) " · $notes" else ""}", fontSize = 11.sp, color = fg)
                        } else {
                            Text("Denetlemek için dokunun →", fontSize = 11.sp, color = Color(0xFFEF6C00))
                        }
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Kalite emri yok.") }
        }
    }

    val io = inspectOrder
    if (io != null) {
        InspectSheet(order = io, onDismiss = { inspectOrder = null }, onResult = { passed, reason, notes, quarantine ->
            inspectOrder = null
            scope.launch {
                loading = true; status = "Sonuç kaydediliyor..."
                val no = io.optString("no")
                val r = if (passed)
                    BcApi.boundAction(context, "qualityOrders", no, "pass",
                        JSONObject().apply { put("inspector", "MOBIL"); put("notes", notes) }.toString())
                else
                    BcApi.boundAction(context, "qualityOrders", no, "fail",
                        JSONObject().apply { put("inspector", "MOBIL"); put("reasonCode", reason); put("notes", notes); put("quarantineBin", quarantine) }.toString())
                loading = false
                status = if (r.ok) "PASS: $no → ${if (passed) "KABUL" else "RED"} (HTTP ${r.httpCode})" else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
                load()
            }
        })
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun InspectSheet(order: JSONObject, onDismiss: () -> Unit, onResult: (passed: Boolean, reason: String, notes: String, quarantine: String) -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var notes by remember { mutableStateOf("") }
    var quarantine by remember { mutableStateOf("QUARANTINE") }
    val reasons = listOf("DAMAGED", "WRONGITEM", "EXPIRED", "CONTAMINATED", "SPEC-FAIL")
    var reason by remember { mutableStateOf(reasons.first()) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().padding(20.dp)) {
            Text("Kalite Denetimi — ${order.optString("no")}", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Text("${order.optString("itemNo")} · Numune: ${order.optDouble("sampleSize")} / ${order.optDouble("quantity")}", fontSize = 12.sp, color = Color.Gray)
            Spacer(Modifier.height(12.dp))
            ScanField("Numune barkod (opsiyonel)", "", {}, modifier = Modifier.fillMaxWidth(), onScanned = { notes = "Tarandı: ${BarcodeIntentResolver.resolve(it).value}" })
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(notes, { notes = it }, label = { Text("Notlar") }, modifier = Modifier.fillMaxWidth(), maxLines = 3)
            Spacer(Modifier.height(12.dp))
            Text("RED sebebi (fail için)", fontSize = 12.sp, color = Color.Gray)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                reasons.forEach { FilterChip(selected = it == reason, onClick = { reason = it }, label = { Text(it, fontSize = 11.sp) }) }
            }
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(quarantine, { quarantine = it }, label = { Text("Karantina Bin (red için)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = { onResult(true, "", notes, "") },
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32))
                ) { Text("✅ KABUL", fontWeight = FontWeight.Bold) }
                Button(
                    onClick = { onResult(false, reason, notes, quarantine.trim()) },
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFC62828))
                ) { Text("❌ RED", fontWeight = FontWeight.Bold) }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}
