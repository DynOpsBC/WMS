package com.dynops.bcwms.feature

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.dynops.bcwms.BcApi
import org.json.JSONObject
import java.util.UUID

@Composable
internal fun rememberPrinterPreference(key: String, default: String = ""): String {
    val context = LocalContext.current
    val prefs = remember(context) { context.getSharedPreferences("bcwms_prefs", Context.MODE_PRIVATE) }
    var value by remember(prefs, key) { mutableStateOf(prefs.getString(key, default).orEmpty()) }
    DisposableEffect(prefs, key) {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, changed ->
            if (changed == key) value = prefs.getString(key, default).orEmpty()
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        value = prefs.getString(key, default).orEmpty()
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    return value
}

internal fun printerSelectionAllowed(row: JSONObject, usage: String): Boolean =
    row.optBoolean("active", true) && row.optString("format").trim().equals(
        if (usage == PRINTER_USAGE_LABEL) "ZPL" else "PDF", ignoreCase = true,
    )

internal fun printerMatchesSearch(row: JSONObject, query: String): Boolean =
    listOf("code", "description", "stationId", "printerHandle", "locationCode").any {
        row.optString(it).contains(query.trim(), ignoreCase = true)
    }

@Composable
internal fun DevicePrinterSettings() {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("bcwms_prefs", Context.MODE_PRIVATE) }
    val initialName = remember {
        prefs.getString("bcwms.device.printName", null) ?: "${Build.MODEL} · ${UUID.randomUUID().toString().take(4).uppercase()}".also {
            prefs.edit().putString("bcwms.device.printName", it).apply()
        }
    }
    val name = rememberPrinterPreference("bcwms.device.printName", initialName)
    var editing by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf(name) }
    Text("Bu cihazın yazıcıları", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
    TextButton(onClick = { draft = name; editing = true }) { Text("$name · Adı değiştir") }
    Text("Seçimler yalnızca bu terminalde kaydedilir. Başka cihazların yazıcısı değişmez.", style = MaterialTheme.typography.bodySmall)
    Spacer(Modifier.height(8.dp))
    PrinterDestinationCard(PRINTER_USAGE_LABEL)
    Spacer(Modifier.height(8.dp))
    PrinterDestinationCard(PRINTER_USAGE_DOCUMENT)
    Spacer(Modifier.height(8.dp))
    Text("Terminal → seçilen yazıcı → yazıcıya bağlı bilgisayar. A3 PDF çıktısında hedef, Android yazdırma ekranında ayrıca seçilir.", style = MaterialTheme.typography.bodySmall)
    if (editing) AlertDialog(
        onDismissRequest = { editing = false },
        title = { Text("Cihaz adı") },
        text = { OutlinedTextField(value = draft, onValueChange = { draft = it.take(50) }, label = { Text("Örn. Depo 1 · El terminali 2") }, singleLine = true) },
        confirmButton = { TextButton(enabled = draft.isNotBlank(), onClick = {
            prefs.edit().putString("bcwms.device.printName", draft.trim()).apply(); editing = false
        }) { Text("Kaydet") } },
        dismissButton = { TextButton(onClick = { editing = false }) { Text("Vazgeç") } },
    )
}

@Composable
internal fun DevicePrintersDialog(onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Yazdırma hedefleri") }, text = {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) { DevicePrinterSettings() }
    }, confirmButton = { TextButton(onClick = onDismiss) { Text("Tamam") } })
}

/** A configured destination is not a live USB/network connection claim. */
@Composable
internal fun PrinterDestinationCard(usage: String = PRINTER_USAGE_LABEL, inquiryFallback: Boolean = false) {
    val context = LocalContext.current
    val selected = rememberPrinterPreference("bcwms.printer.$usage")
    val document = rememberPrinterPreference("bcwms.printer.$PRINTER_USAGE_DOCUMENT")
    val effective = if (inquiryFallback) inquiryLabelPrinter(selected, document) else selected
    var open by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var generation by remember { mutableIntStateOf(0) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var complete by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    LaunchedEffect(generation) {
        loading = true; complete = false; error = ""
        try {
            val page = BcApi.getAllPages(context, "printers?\$top=100&\$orderby=code")
            complete = page.complete
            rows = if (page.complete) page.rows else emptyList()
            if (!page.complete) error = "Yazıcı listesi doğrulanamadı. Yenileyin."
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            error = "Yazıcı listesi alınamadı. Yenileyin."
        } finally { loading = false }
    }
    val row = rows.firstOrNull { it.optString("code") == effective }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(if (usage == PRINTER_USAGE_LABEL) "Etiket yazıcısı" else "Belge yazıcısı", style = MaterialTheme.typography.labelLarge)
            Text(effective.ifBlank { "Bu cihazda seçilmedi" }, fontWeight = FontWeight.Bold)
            if (row != null) {
                Text(row.optString("description").ifBlank { row.optString("printerHandle") }, style = MaterialTheme.typography.bodySmall)
                Text("Bilgisayar / istasyon: ${row.optString("stationId").ifBlank { "Bildirilmemiş" }}", style = MaterialTheme.typography.bodySmall)
                Text("Konum: ${row.optString("locationCode").ifBlank { "Bildirilmemiş" }}", style = MaterialTheme.typography.bodySmall)
                Text(if (row.optBoolean("active", true)) "BC kaydı aktif" else "Yazıcı kaydı pasif", style = MaterialTheme.typography.bodySmall)
                val reportedStatus = when (row.optString("agentStatus").lowercase()) {
                    "online" -> "Çevrimiçi"
                    "offline" -> "Çevrimdışı"
                    "printing" -> "Yazdırıyor"
                    "error" -> "Hata"
                    else -> "Bilinmiyor"
                }
                Text("Son bildirilen durum: $reportedStatus", style = MaterialTheme.typography.bodySmall)
                val lastSeen = runCatching {
                    java.time.Instant.parse(row.optString("lastSeenAt")).atZone(java.time.ZoneId.systemDefault())
                        .takeIf { it.year > 2000 }?.format(java.time.format.DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm"))
                }.getOrNull()
                Text("Son haberleşme: ${lastSeen ?: "Bildirilmemiş"}", style = MaterialTheme.typography.bodySmall)
            }
            if (inquiryFallback && selected.isBlank()) Text(
                if (document.isNotBlank()) "Etiket seçilmediği için bu baskı belge yazıcısına gider."
                else "Hedef BC ayarlarından belirlenir; burada doğrulanamıyor. Yazıcı seçebilirsiniz.",
                style = MaterialTheme.typography.bodySmall,
            )
            if (loading) Text("Yazıcı bilgisi kontrol ediliyor…", style = MaterialTheme.typography.bodySmall)
            else if (error.isNotBlank()) Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            else if (complete && effective.isNotBlank() && row == null) Text("Seçili yazıcı listede yok. Yeniden seçin.", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = { query = ""; open = true; generation++ }) { Text(if (selected.isBlank()) "Yazıcı seç" else "Değiştir") }
        }
    }
    if (open) AlertDialog(onDismissRequest = { open = false }, title = {
        Text(if (usage == PRINTER_USAGE_LABEL) "Bu cihaz için etiket yazıcısı" else "Bu cihaz için belge yazıcısı")
    }, text = {
        Column(Modifier.fillMaxWidth()) {
            OutlinedTextField(query, { query = it }, singleLine = true, label = { Text("Yazıcı, bilgisayar veya konum ara") })
            Text("Seçtiğiniz yazıcı bu cihazın sonraki baskılarında kullanılır.", style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = { generation++ }, enabled = !loading) { Text(if (loading) "Yükleniyor…" else "Listeyi yenile") }
            if (error.isNotBlank()) Text(error, color = MaterialTheme.colorScheme.error)
            val visible = rows.filter { printerSelectionAllowed(it, usage) && printerMatchesSearch(it, query) }
            if (complete && visible.isEmpty()) Text("Uygun yazıcı bulunamadı. Aramayı veya Windows yazıcı ajanındaki eşitlemeyi kontrol edin.")
            LazyColumn(Modifier.heightIn(max = 280.dp)) {
                items(visible, key = { it.optString("code") }) { printer ->
                    TextButton(enabled = !loading, onClick = {
                        setDefaultPrinter(context, printer.optString("code"), usage); open = false
                    }) {
                        Column(Modifier.fillMaxWidth()) {
                            Text((if (selected == printer.optString("code")) "✓ " else "") + printer.optString("code"), fontWeight = FontWeight.Bold)
                            Text(printer.optString("description"), style = MaterialTheme.typography.bodySmall)
                            Text("${printer.optString("stationId").ifBlank { "İstasyon bildirilmemiş" }} · ${printer.optString("locationCode").ifBlank { "Konum bildirilmemiş" }}", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    HorizontalDivider()
                }
            }
        }
    }, confirmButton = { TextButton(onClick = { open = false }) { Text("Kapat") } })
}
