package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.dynops.bcwms.BcApi
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun printerSelectionAllowed(row: JSONObject, usage: String): Boolean =
    row.optBoolean("active", true) && row.optString("format").trim().equals(
        if (usage == PRINTER_USAGE_LABEL) "ZPL" else "PDF", ignoreCase = true,
    )

internal fun printerMatchesSearch(row: JSONObject, query: String): Boolean =
    listOf("code", "description", "stationId", "printerHandle", "locationCode").any {
        row.optString(it).contains(query.trim(), ignoreCase = true)
    }

/**
 * A configured destination is not a live USB/network connection claim.
 *
 * Kitoko (19 Eki 2026): EMU'dan. BADE ailesinde yazıcı terminale aittir; seçim
 * [selectTerminalPrinter] ile BC terminal kaydına yazılır (PIN oturumu gerekir).
 * Yazıcı yoksa baskı gönderilmez, BC'ye "varsayılan" diye bırakılmaz.
 */
@Composable
internal fun PrinterDestinationCard(
    usage: String = PRINTER_USAGE_LABEL,
    inquiryFallback: Boolean = false,
    compact: Boolean = false,
    enabled: Boolean = true,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val selected = rememberDevicePrinter(usage)
    val document = rememberDevicePrinter(PRINTER_USAGE_DOCUMENT)
    val effective = if (inquiryFallback) inquiryLabelPrinter(selected, document) else selected
    var open by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var generation by remember { mutableIntStateOf(0) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var complete by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
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
    // DKÇ (17 Eyl 2026): "etiket yazıcısı çok detaylı bilgiler yazıyor".
    // Baskıdan önce operatörün tek ihtiyacı hangi yazıcıya gittiğidir; istasyon,
    // konum, BC kaydı, ajan durumu ve son haberleşme yalnız Yazıcılar ekranında
    // kalır. Burada sadece bir uyarı satırı gösterilir, o da bir sorun varsa.
    val warning = when {
        loading || error.isNotBlank() -> ""
        complete && effective.isNotBlank() && row == null -> "Bu yazıcı listede yok, yeniden seçin."
        row != null && !row.optBoolean("active", true) -> "Yazıcı kaydı pasif."
        inquiryFallback && selected.isBlank() && document.isNotBlank() -> "Etiket yazıcısı seçilmedi, belge yazıcısına gider."
        effective.isBlank() -> "Yazıcı seçilmedi. Seç'e dokunun veya Yazıcılar ekranından seçin."
        else -> ""
    }
    if (compact) {
        val defaultDestination = inquiryFallback && selected.isBlank()
        val destinationProblem = error.isNotBlank() || effective.isBlank() ||
            (complete && effective.isNotBlank() && row == null) || (row != null && !row.optBoolean("active", true))
        val compactWarning = when {
            error.isNotBlank() -> error
            loading -> ""
            complete && effective.isNotBlank() && row == null -> "Yazıcıyı yeniden seçin."
            row != null && !row.optBoolean("active", true) -> "Yazıcı pasif."
            defaultDestination && document.isNotBlank() -> "Belge yazıcısı kullanılacak"
            effective.isBlank() -> "Yazıcı seçilmedi, baskı gönderilemez."
            else -> ""
        }
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
            shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(Modifier.padding(start = 12.dp, end = 4.dp, top = 6.dp, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                com.dynops.bcwms.ui.WmsIcon(com.dynops.bcwms.ui.WmsGlyph.PRINTER,
                    MaterialTheme.colorScheme.primary, Modifier.size(22.dp))
                Column(Modifier.weight(1f)) {
                    Text(printerBindingFrom(effective, row).title.ifBlank { "Yazıcı seçin" },
                        style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold,
                        maxLines = 2, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                    if (compactWarning.isNotBlank()) Text(compactWarning,
                        style = MaterialTheme.typography.bodySmall,
                        color = if (destinationProblem) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurfaceVariant)
                }
                TextButton(enabled = enabled, onClick = { query = ""; open = true; generation++ }) {
                    Text(if (selected.isBlank()) "Seç" else "Değiştir")
                }
            }
        }
    } else {
    Card(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    if (usage == PRINTER_USAGE_LABEL) "Etiket yazıcısı" else "Belge yazıcısı",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(printerBindingFrom(effective, row).title.ifBlank { "Seçilmedi" }, fontWeight = FontWeight.Bold)
                if (warning.isNotBlank()) Text(
                    warning,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            TextButton(enabled = enabled, onClick = { query = ""; open = true; generation++ }) {
                Text(if (selected.isBlank()) "Seç" else "Değiştir")
            }
        }
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
                    TextButton(enabled = !loading && !saving, onClick = {
                        saving = true
                        scope.launch {
                            val result = selectTerminalPrinter(context, printer.optString("code"), usage)
                            saving = false
                            if (result.isSuccess) open = false else error = result.exceptionOrNull()?.message.orEmpty()
                        }
                    }) {
                        Column(Modifier.fillMaxWidth()) {
                            Text((if (selected == printer.optString("code")) "✓ " else "") + printerBindingFrom(printer.optString("code"), printer).title, fontWeight = FontWeight.Bold)
                            // Seçim ekranında yer bilgisi kalır: aynı isimli iki
                            // yazıcı yalnız istasyon/konumla ayırt edilebiliyor.
                            Text(
                                listOfNotNull(
                                    printer.optString("description").takeIf(String::isNotBlank),
                                    printer.optString("stationId").takeIf(String::isNotBlank),
                                    printer.optString("locationCode").takeIf(String::isNotBlank),
                                ).joinToString(" · ").ifBlank { "Bilgi yok" },
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }
                    HorizontalDivider()
                }
            }
        }
    }, confirmButton = { TextButton(onClick = { open = false }) { Text("Kapat") } },
        dismissButton = { if (selected.isNotBlank()) TextButton(onClick = {
            saving = true
            scope.launch {
                val result = selectTerminalPrinter(context, "", usage)
                saving = false
                if (result.isSuccess) open = false else error = result.exceptionOrNull()?.message.orEmpty()
            }
        }) { Text("Seçimi kaldır") } })
}
