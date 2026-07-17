package com.dynops.bcwms.feature

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.*
import org.json.JSONArray
import org.json.JSONObject

/**
 * Scratchpad — çevrimdışı veri toplama (WI "Scratchpad" pariteti).
 *
 * Bağlantı yokken/serbest sayım/keşif için depocu tara-topla yapar; kayıtlar
 * CİHAZDA saklanır (SharedPreferences). Sonra panoya kopyalanıp BC'ye girilebilir.
 * (Doğrudan BC'ye push + "Decode/Process" tam entegrasyonu sonraki adım.)
 */
@Composable
fun ScratchpadModule() {
    val context = LocalContext.current
    var entries by remember { mutableStateOf(ScratchpadStore.load(context)) }
    var itemNo by remember { mutableStateOf("") }
    var qty by remember { mutableStateOf("1") }
    var note by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }

    fun refresh() { entries = ScratchpadStore.load(context) }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Text("Scratchpad — Çevrimdışı Toplama", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text("Bağlantı olmadan tara-topla; cihazda saklanır. Sonra panoya kopyalayıp BC'ye aktar.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(10.dp))
        ScanField("Item / Barkod", itemNo, { itemNo = it }, modifier = Modifier.fillMaxWidth(), onScanned = {
            itemNo = BarcodeIntentResolver.resolve(it).itemNo ?: it
        })
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(qty, { qty = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Miktar") }, singleLine = true, modifier = Modifier.width(120.dp))
            OutlinedTextField(note, { note = it }, label = { Text("Not (opsiyonel)") }, singleLine = true, modifier = Modifier.weight(1f))
        }
        Spacer(Modifier.height(8.dp))
        Button(
            onClick = {
                if (itemNo.isBlank()) { status = "⚠️ Item/barkod girin"; return@Button }
                ScratchpadStore.add(context, itemNo.trim(), qty.toDoubleOrNull() ?: 0.0, note.trim())
                refresh(); status = "➕ Eklendi: ${itemNo.trim()}"
                itemNo = ""; qty = "1"; note = ""
            },
            enabled = itemNo.isNotBlank(),
            modifier = Modifier.fillMaxWidth().height(50.dp),
        ) { Text("➕ Kaydet (offline)", fontWeight = FontWeight.Bold) }
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        Spacer(Modifier.height(6.dp))
        Text("Toplananlar (${entries.size})", fontWeight = FontWeight.Bold, fontSize = 14.sp)
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(entries) { e ->
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("${e.optString("itemNo")} × ${fmtItemQty(e.optDouble("qty"))}", fontWeight = FontWeight.SemiBold)
                            val n = e.optString("note")
                            if (n.isNotBlank()) Text(n, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        TextButton(onClick = { ScratchpadStore.removeAt(context, e.optLong("ts")); refresh() }) { Text("Sil") }
                    }
                }
            }
            if (entries.isEmpty()) item { EmptyState("Henüz kayıt yok. Tara-topla ile başla.") }
        }
        BottomActionBar {
            OutlinedButton(onClick = {
                val text = ScratchpadStore.asText(entries)
                val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("scratchpad", text))
                status = "📋 ${entries.size} kayıt panoya kopyalandı"
            }, enabled = entries.isNotEmpty(), modifier = Modifier.weight(1f).height(50.dp)) { Text("📋 Panoya Kopyala") }
            OutlinedButton(onClick = { ScratchpadStore.clear(context); refresh(); status = "🗑 Temizlendi" }, enabled = entries.isNotEmpty(), modifier = Modifier.weight(1f).height(50.dp)) { Text("🗑 Tümünü Sil") }
        }
    }
}

/** Scratchpad kayıtlarının cihaz-yerel deposu (SharedPreferences, JSON array). */
object ScratchpadStore {
    private const val PREFS = "dopswhs_scratchpad"
    private const val KEY = "entries"

    fun load(context: Context): List<JSONObject> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "[]") ?: "[]"
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getJSONObject(it) }
        }.getOrDefault(emptyList())
    }

    private fun save(context: Context, list: List<JSONObject>) {
        val arr = JSONArray()
        list.forEach { arr.put(it) }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, arr.toString()).apply()
    }

    fun add(context: Context, itemNo: String, qty: Double, note: String) {
        val list = load(context).toMutableList()
        list.add(0, JSONObject().apply {
            put("itemNo", itemNo); put("qty", qty); put("note", note)
            put("ts", System.currentTimeMillis())
        })
        save(context, list)
    }

    fun removeAt(context: Context, ts: Long) {
        save(context, load(context).filterNot { it.optLong("ts") == ts })
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY).apply()
    }

    fun asText(list: List<JSONObject>): String =
        list.joinToString("\n") { "${it.optString("itemNo")}\t${fmtItemQty(it.optDouble("qty"))}\t${it.optString("note")}" }
}
