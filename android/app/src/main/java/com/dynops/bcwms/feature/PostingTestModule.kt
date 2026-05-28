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
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Posting Test — triggers the BC posting smoke harness (all WMS post/register actions) from the app
 * and shows per-domain PASS/FAIL. Calls postingTests('1-MOVE')/Microsoft.NAV.runAll, then lists rows.
 */
@Composable
fun PostingTestModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var running by remember { mutableStateOf(false) }

    fun load() {
        scope.launch {
            val r = BcApi.get(context, "postingTests?\$orderby=sortOrder&\$select=domain,description,status,detail,postedDocNo")
            if (r.ok) rows = BcApi.parseValueArray(r.body)
        }
    }
    fun runAll() {
        scope.launch {
            running = true; status = "Tüm posting testleri çalışıyor (BC'de gerçek belge post ediliyor)..."
            val r = BcApi.boundAction(context, "postingTests", "1-MOVE", "runAll", "{}")
            running = false
            status = if (r.ok) "PASS: Posting testleri tamamlandı." else "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            load()
        }
    }
    LaunchedEffect(Unit) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Text("BC Posting Test Harness", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Text("Her WMS post/register aksiyonu için BC'de gerçek belge oluşturup post eder.", fontSize = 11.sp, color = Color.Gray)
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { runAll() }, enabled = !running) { Text(if (running) "Çalışıyor..." else "▶ Tüm Postingleri Test Et") }
            Spacer(Modifier.width(8.dp))
            OutlinedButton(onClick = { load() }, enabled = !running) { Text("🔄") }
        }
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        val passed = rows.count { it.optString("status") == "Passed" }
        if (rows.isNotEmpty()) Text("Geçen: $passed / ${rows.size}", fontWeight = FontWeight.Medium, fontSize = 13.sp)
        Spacer(Modifier.height(6.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { d ->
                val st = d.optString("status")
                val mark = when (st) { "Passed" -> "✅"; "Failed" -> "❌"; "Running" -> "⏳"; else -> "·" }
                val color = when (st) { "Passed" -> Color(0xFF2E7D32); "Failed" -> Color(0xFFC62828); else -> Color.Gray }
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("$mark ${d.optString("description")}", fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                            Text(st, color = color, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }
                        val doc = firstValue(d, "postedDocNo")
                        if (doc != "-") Text("Belge: $doc", fontSize = 12.sp, color = Color(0xFF2E7D32))
                        val detail = d.optString("detail")
                        if (detail.isNotBlank()) Text(detail, fontSize = 11.sp, color = Color.Gray)
                    }
                }
            }
            if (rows.isEmpty()) item { EmptyState("Henüz posting testi çalıştırılmadı. ▶ ile başlatın.") }
        }
    }
}
