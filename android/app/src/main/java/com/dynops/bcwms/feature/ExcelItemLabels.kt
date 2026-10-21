package com.dynops.bcwms.feature

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import com.dynops.bcwms.BcApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

@Composable
fun ExcelItemLabelsCard(enabled: Boolean = true, loadPreparedRows: (suspend () -> List<org.json.JSONObject>)? = null) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<ExcelLabelRow>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var printing by remember { mutableStateOf(false) }
    var stop by remember { mutableStateOf(false) }
    var sent by remember { mutableIntStateOf(0) }
    var error by remember { mutableStateOf("") }
    var outcome by remember { mutableStateOf<AllItemLabelsOutcome?>(null) }
    // A process interruption must not silently invite sending an uncertain batch again.
    val preferences = remember { context.getSharedPreferences("excel-label-print", 0) }
    var uncertain by remember { mutableStateOf(preferences.getString("inFlight", "").orEmpty()) }
    var previewSource by remember { mutableStateOf("Excel sırası korunur.") }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            loading = true
            error = ""
            previewSource = "Excel sırası korunur."
            scope.launch {
                val imported = withContext(Dispatchers.IO) {
                    runCatching {
                        context.contentResolver.openInputStream(uri)?.use(ExcelLabelImport::read)
                            ?: throw IllegalArgumentException("Excel dosyası açılamadı.")
                    }
                }
                rows = imported.getOrDefault(emptyList())
                error = imported.exceptionOrNull()?.message.orEmpty()
                loading = false
            }
        }
    }
    PreparedLabelsButton(
        enabled = enabled && !loading && !printing && uncertain.isEmpty() && rows.isEmpty() && outcome == null,
        loading = loading,
        onClick = {
            loading = true
            error = ""
            previewSource = "15.10.2026 tarihli hazır göz listesi."
            scope.launch {
                try {
                    val apiRows = loadPreparedRows?.invoke() ?: run {
                        val page = BcApi.getAllPages(context, PreparedItemLabels.QUERY, maxPages = 100)
                        check(page.complete) { "Hazır liste alınamadı. BCWMSApp 1.14.2.25 ve bağlantıyı kontrol edin." }
                        page.rows
                    }
                    rows = PreparedItemLabels.read(apiRows)
                } catch (cancelled: kotlinx.coroutines.CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    error = failure.message ?: "Hazır liste açılamadı."
                } finally {
                    loading = false
                }
            }
        },
    )
    OutlinedButton(
        onClick = { picker.launch(arrayOf("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")) },
        enabled = enabled && !loading && !printing && uncertain.isEmpty(),
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
    ) { Text(if (loading) "Excel okunuyor…" else "Excel'den sıralı ürün / göz etiketleri") }
    if (error.isNotBlank()) Text(error, color = MaterialTheme.colorScheme.error)

    if (uncertain.isNotEmpty() && !printing && outcome == null) AlertDialog(
        onDismissRequest = {},
        title = { Text("Yazıcı kuyruğunu kontrol edin") },
        text = { Text("Önceki gönderim doğrulanamadı: $uncertain. Bu aralık basılmış olabilir. Tekrar baskıdan önce kuyruğu ve çıkan etiketleri kontrol edin.") },
        confirmButton = { TextButton(onClick = {
            preferences.edit().remove("inFlight").commit()
            uncertain = ""
        }) { Text("Kontrol ettim") } },
    )

    if (rows.isNotEmpty() && !printing && outcome == null) ExcelLabelsPreview(
        rows = rows,
        busy = loading,
        error = error,
        source = previewSource,
        onDismiss = { if (!loading) rows = emptyList() },
        onPrint = {
            // Set synchronously: repeated taps cannot create a second coroutine.
            loading = true
            error = ""
            scope.launch {
                try {
                    val choice = resolveInquiryPrinter(context).getOrThrow()
                    val page = BcApi.getAllPages(context, "items?\$select=no,blocked", maxPages = 1000)
                    check(page.complete) { "Ürünler doğrulanamadı. Hiçbir etiket gönderilmedi." }
                    val available = page.rows.filter { !it.optBoolean("blocked") }
                        .map { it.optString("no").uppercase(Locale.ROOT) }.toSet()
                    val missing = rows.filter { it.itemNo.uppercase(Locale.ROOT) !in available }
                    check(missing.isEmpty()) {
                        "${missing.size} satırdaki ürün bulunamadı veya bloke: ${missing.take(5).joinToString { it.itemNo }}. Hiçbir etiket gönderilmedi."
                    }
                    printing = true
                    loading = false
                    stop = false
                    sent = 0
                    outcome = sendExcelLabels(rows, send = { batch ->
                        val range = "${batch.first().order}–${batch.last().order}"
                        check(withContext(Dispatchers.IO) { preferences.edit().putString("inFlight", range).commit() }) {
                            "Baskı durumu kaydedilemedi; gönderim yapılmadı."
                        }
                        uncertain = range
                        val response = BcApi.boundActionLongRunning(context, "items", batch.first().itemNo,
                            "printLabelRows", excelLabelsPayload(batch, choice.printerCode))
                        val count = BcApi.scalarValue(response.body).trim().toIntOrNull()
                        if (response.ok && count == batch.size) {
                            withContext(Dispatchers.IO) { preferences.edit().remove("inFlight").commit() }
                            uncertain = ""
                            Result.success(count)
                        } else Result.failure(IllegalStateException(
                            if (response.httpCode == 404) "Bu işlem için BCWMSApp 1.14.2.24 veya üzeri gerekir."
                            else "${BcApi.errorMessage(response.body)} (HTTP ${response.httpCode})"))
                    }, stopRequested = { stop }, onProgress = { done, _ -> sent = done })
                } catch (cancelled: kotlinx.coroutines.CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    error = failure.message ?: "Yazdırma başlatılamadı."
                } finally {
                    loading = false
                    printing = false
                }
            }
        },
    )
    if (printing) AlertDialog(
        onDismissRequest = {},
        properties = DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false),
        title = { Text(if (stop) "Durduruluyor…" else "Etiketler gönderiliyor…") },
        text = { Column {
            Text("$sent / ${rows.size} etiket yazıcıya gönderildi.")
            Spacer(Modifier.height(12.dp))
            LinearProgressIndicator(progress = { sent.toFloat() / rows.size }, modifier = Modifier.fillMaxWidth())
            Text("Sıra korunur; her satır bir etikettir. Durdur, mevcut 50'lik paket bitince uygulanır.")
        } },
        confirmButton = { TextButton(onClick = { stop = true }, enabled = !stop) { Text("Durdur") } },
    )
    outcome?.let { done -> AlertDialog(
        onDismissRequest = { outcome = null; rows = emptyList() },
        title = { Text(if (done.error != null || done.stopped) "Gönderim durdu" else "Etiketler gönderildi") },
        text = { Text("${done.sent} / ${done.total} etiket yazıcıya gönderildi. " +
            (done.error ?: if (done.stopped) "Kalan satırlar gönderilmedi." else "Çıktı sırası önizleme ile aynıdır.") +
            " Gönderilen işler yazıcı kuyruğunda basılmaya devam edebilir.") },
        confirmButton = { TextButton(onClick = { outcome = null; rows = emptyList() }) { Text("Kapat") } },
    ) }
}

@Composable
internal fun ExcelLabelsPreview(rows: List<ExcelLabelRow>, busy: Boolean, error: String = "", source: String = "Excel sırası korunur.", onDismiss: () -> Unit, onPrint: () -> Unit) {
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text("${rows.size} satır → ${rows.size} etiket") },
        text = { Column {
            Text(source, style = MaterialTheme.typography.labelLarge)
            Spacer(Modifier.height(6.dp))
            Text("${rows.map { it.itemNo }.distinct().size} farklı ürün. Tekrarlar ve göz sırası korunur. Stok miktarı baskı adedi değildir. QR yalnız ürün numarasını içerir; göz etikette ayrıca yazılır.")
            Spacer(Modifier.height(12.dp))
            LazyColumn(Modifier.heightIn(max = 320.dp)) {
                items(rows, key = { it.order }) { row ->
                    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                        Text("${row.order}. ${row.itemNo}  •  ${row.bin}", style = MaterialTheme.typography.titleSmall)
                        Text(row.description, style = MaterialTheme.typography.bodySmall)
                        HorizontalDivider()
                    }
                }
            }
            if (busy) { Spacer(Modifier.height(8.dp)); Text("Yazıcı ve ürünler doğrulanıyor…") }
            if (error.isNotBlank()) Text(error, color = MaterialTheme.colorScheme.error)
        } },
        confirmButton = { Button(onClick = onPrint, enabled = !busy) { Text("Tümünü yazdır (${rows.size})") } },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("Vazgeç") } },
    )
}

@Composable
internal fun PreparedLabelsButton(enabled: Boolean, loading: Boolean, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled && !loading, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
        Text(if (loading) "Liste hazırlanıyor…" else PreparedItemLabels.BUTTON)
    }
}
