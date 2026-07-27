package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import com.dynops.bcwms.ui.EmptyState
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Printers module — register printers, copy agent token, set the default
 * printer for this device (per-usage). The selection is stored in SharedPreferences
 * under `bcwms.printer.<usage>` and consumed by LP/Pick/Ship print buttons.
 */

private const val PREF_NAMESPACE = "bcwms.printer."

fun getDefaultPrinter(context: Context, usage: String = "LpLabel"): String {
    return context.getSharedPreferences("bcwms_prefs", Context.MODE_PRIVATE)
        .getString(PREF_NAMESPACE + usage, "") ?: ""
}

fun setDefaultPrinter(context: Context, code: String, usage: String = "LpLabel") {
    context.getSharedPreferences("bcwms_prefs", Context.MODE_PRIVATE)
        .edit().putString(PREF_NAMESPACE + usage, code).apply()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrintersModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var defaultCode by remember { mutableStateOf(getDefaultPrinter(context)) }
    var tokenDialog by remember { mutableStateOf<Pair<String, String>?>(null) }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val r = BcApi.get(context, "printers?\$top=100&\$orderby=code")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: Printer listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "BOŞ: kayıtlı printer yok (HTTP ${r.httpCode})"
                else "TAMAM: ${rows.size} yazıcı (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(Unit) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Text("🖨 Yazıcılar", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text(
            "Kendi sunucunuzdaki yazdırma köprüsü — agent kayıtları + bu cihaz için varsayılan yazıcı.",
            fontSize = 12.sp, color = Color.Gray
        )
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
        }
        Spacer(Modifier.height(6.dp))
        if (status.isNotBlank()) Text(status, fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (rows.isEmpty() && !loading) item { EmptyState("Kayıtlı yazıcı yok. BC'de DOPSWHS Printers sayfasından ekleyin.") }
            items(rows) { row ->
                val code = row.optString("code")
                val desc = row.optString("description")
                val format = row.optString("format")
                val handle = row.optString("printerHandle").ifBlank { row.optString("hostname") }
                val active = row.optBoolean("active", true)
                val isDefault = defaultCode == code
                Card(shape = RoundedCornerShape(12.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(code, fontWeight = FontWeight.Bold)
                            Spacer(Modifier.width(8.dp))
                            if (isDefault) AssistChip(onClick = {}, label = { Text("Varsayılan", fontSize = 11.sp) })
                            if (!active) {
                                Spacer(Modifier.width(4.dp))
                                AssistChip(onClick = {}, label = { Text("Pasif", fontSize = 11.sp) })
                            }
                        }
                        Text("$desc · $format · ${handle.ifBlank { "-" }}", fontSize = 12.sp, color = Color.Gray)
                        Spacer(Modifier.height(8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            OutlinedButton(onClick = {
                                setDefaultPrinter(context, code)
                                defaultCode = code
                            }) { Text(if (isDefault) "✓ Varsayılan" else "Varsayılan yap", fontSize = 12.sp) }
                            OutlinedButton(onClick = {
                                scope.launch {
                                    val r = BcApi.boundAction(context, "printers", code, "generateToken", "{}")
                                    val token = if (r.ok) BcApi.scalarValue(r.body) else "HATA: ${r.body.take(140)}"
                                    tokenDialog = code to token
                                    load()
                                }
                            }) { Text("🔑 Token", fontSize = 12.sp) }
                            OutlinedButton(onClick = {
                                scope.launch {
                                    val r = BcApi.boundAction(context, "printers", code, "testPrint", "{}")
                                    status = if (r.ok) "Test yazdırma işi ${code} kuyruğa alındı." else "HATA: ${r.body.take(140)}"
                                }
                            }) { Text("🧪 Test", fontSize = 12.sp) }
                        }
                    }
                }
            }
        }
    }

    tokenDialog?.let { (code, token) ->
        AlertDialog(
            onDismissRequest = { tokenDialog = null },
            confirmButton = {
                TextButton(onClick = { tokenDialog = null }) { Text("Kapat") }
            },
            title = { Text("Agent Tokenı — $code") },
            text = {
                Column {
                    Text("Token yalnızca şimdi gösterilir. Kopyalayıp local agent config.json'a yazın.", fontSize = 12.sp)
                    Spacer(Modifier.height(8.dp))
                    Surface(color = Color(0xFFF5F5F5), shape = RoundedCornerShape(8.dp)) {
                        Text(token, Modifier.padding(8.dp), fontSize = 12.sp)
                    }
                }
            }
        )
    }
}

