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
import androidx.compose.ui.Alignment
import kotlinx.coroutines.delay
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
    // DKÇ (21 Eki 2026): BC'de bulunamayan/bloke ürün satırı bütün listeyi durdurmasın;
    // satırlar gösterilir, onaylanırsa atlanıp kalanlar sırayla basılır.
    var skipPrompt by remember { mutableStateOf<List<ExcelLabelRow>>(emptyList()) }
    var promptResume by remember { mutableStateOf(false) }
    var promptOnly by remember { mutableStateOf<Set<Int>?>(null) }
    // DKÇ (21 Eki 2026): yazıcı ajanının reddettiği (ör. eski yazıcı kaydı) etiketler.
    var unprintedPrompt by remember { mutableStateOf<List<Int>?>(null) }
    // DKÇ (21 Eki 2026): durdurulan/yarım kalan gönderimden sonra 1'den yeniden basmamak için
    // son başarıyla gönderilen sıra saklanır; önizlemede "Kaldığı yerden devam" çıkar.
    var resumeAfter by remember { mutableIntStateOf(preferences.getInt("resumeAfter", 0)) }
    var skippedCount by remember { mutableIntStateOf(0) }
    var printTotal by remember { mutableIntStateOf(0) }
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
            val start = uncertainRangeStart(uncertain)
            if (start != null && resumeAfter == 0) {
                resumeAfter = start - 1
                preferences.edit().putInt("resumeAfter", resumeAfter).commit()
            }
            preferences.edit().remove("inFlight").commit()
            uncertain = ""
        }) { Text("Kontrol ettim") } },
    )

    fun promptRows(): List<ExcelLabelRow> = promptOnly?.let { only -> rows.filter { it.order in only } }
        ?: if (promptResume) rowsAfterOrder(rows, resumeAfter) else rows

    fun findUnprinted() {
        loading = true
        error = ""
        scope.launch {
            try {
                val since = java.time.LocalDate.now().atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toString()
                val page = BcApi.getAllPages(context,
                    "printJobs?\$filter=sourceDoc eq 'EXCEL' and createdAt ge $since&\$select=jobId,status,payload&\$orderby=jobId asc",
                    maxPages = 50)
                check(page.complete) { "Yazdırma kuyruğu okunamadı. Bağlantıyı kontrol edin." }
                val jobs = page.rows.map { job ->
                    val zpl = runCatching {
                        String(java.util.Base64.getDecoder().decode(job.optString("payload")), Charsets.UTF_8)
                    }.getOrDefault("")
                    ExcelJobRecord(job.optInt("jobId"), job.optString("status"), excelJobOrders(zpl))
                }
                val listOrders = rows.map { it.order }.toSet()
                val unprinted = unprintedExcelOrders(jobs).filter { it in listOrders }
                if (unprinted.isEmpty()) error = "Bugün yazıcıya ulaşmayan etiket yok."
                else unprintedPrompt = unprinted
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                error = failure.message ?: "Yazdırma kuyruğu okunamadı."
            } finally {
                loading = false
            }
        }
    }

    fun startPrint(skipMissing: Boolean, resume: Boolean, only: Set<Int>? = null) {
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
                val trackResume = only == null
                val source = when {
                    only != null -> rows.filter { it.order in only }
                    resume -> rowsAfterOrder(rows, resumeAfter)
                    else -> rows
                }
                check(source.isNotEmpty()) { "Devam edilecek satır kalmadı." }
                val missing = unavailableLabelRows(source, available)
                if (missing.isNotEmpty() && !skipMissing) {
                    promptResume = resume
                    promptOnly = only
                    skipPrompt = missing
                    return@launch
                }
                val toPrint = source - missing.toSet()
                check(toPrint.isNotEmpty()) { "Basılacak satır kalmadı. Hiçbir etiket gönderilmedi." }
                skippedCount = missing.size
                printTotal = toPrint.size
                printing = true
                loading = false
                stop = false
                sent = 0
                outcome = sendExcelLabels(toPrint, send = { batch ->
                    val range = "${batch.first().order}–${batch.last().order}"
                    check(withContext(Dispatchers.IO) { preferences.edit().putString("inFlight", range).commit() }) {
                        "Baskı durumu kaydedilemedi; gönderim yapılmadı."
                    }
                    uncertain = range
                    val lastJobId = lastExcelPrintJobId(context)
                    val response = BcApi.boundActionLongRunning(context, "items", batch.first().itemNo,
                        "printLabelRows", excelLabelsPayload(batch, choice.printerCode))
                    val count = BcApi.scalarValue(response.body).trim().toIntOrNull()
                    if (response.ok && count == batch.size) {
                        withContext(Dispatchers.IO) {
                            val edit = preferences.edit().remove("inFlight")
                            if (trackResume) edit.putInt("resumeAfter", batch.last().order)
                            edit.commit()
                        }
                        uncertain = ""
                        if (trackResume) resumeAfter = batch.last().order
                        // Paket yazıcıya iletilmeden sonraki gönderilmez (sıra karışmasın).
                        val orderError = if (lastJobId == null) { delay(20_000L); null }
                            else awaitExcelJob(range, fetchJobs = { excelPrintJobsAfter(context, lastJobId) }, pause = { delay(it) })
                        if (orderError == null) Result.success(count) else Result.failure(IllegalStateException(orderError))
                    } else Result.failure(IllegalStateException(
                        if (response.httpCode == 404) "Bu işlem için BCWMSApp 1.14.2.24 veya üzeri gerekir."
                        else "${BcApi.errorMessage(response.body)} (HTTP ${response.httpCode})"))
                }, stopRequested = { stop }, onProgress = { done, _ -> sent = done })
                if (trackResume && outcome?.let { it.error == null && !it.stopped } == true) {
                    preferences.edit().remove("resumeAfter").commit()
                    resumeAfter = 0
                }
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                error = failure.message ?: "Yazdırma başlatılamadı."
            } finally {
                loading = false
                printing = false
            }
        }
    }

    if (rows.isNotEmpty() && !printing && outcome == null) ExcelLabelsPreview(
        rows = rows,
        busy = loading,
        error = error,
        source = previewSource,
        onDismiss = { if (!loading) rows = emptyList() },
        onPrint = { startPrint(false, resume = false) },
        resumeFromOrder = if (resumeAfter > 0 && rows.any { it.order > resumeAfter }) resumeAfter + 1 else 0,
        resumeCount = rowsAfterOrder(rows, resumeAfter).size,
        onResume = { startPrint(false, resume = true) },
        onUnprinted = { findUnprinted() },
    )
    unprintedPrompt?.let { orders -> if (!printing && outcome == null) AlertDialog(
        onDismissRequest = { unprintedPrompt = null },
        title = { Text("${orders.size} etiket yazıcıya ulaşmamış") },
        text = { Column {
            Text("Bugün yazıcı tarafından reddedilen sıralar: ${orderRangesText(orders)}")
            Spacer(Modifier.height(8.dp))
            Text("Seçili yazıcıya sırayla basılsın mı? Önce doğru yazıcının seçili olduğunu kontrol edin.")
        } },
        confirmButton = { Button(onClick = { unprintedPrompt = null; startPrint(false, resume = false, only = orders.toSet()) }) {
            Text("Yazdır (${orders.size})")
        } },
        dismissButton = { TextButton(onClick = { unprintedPrompt = null }) { Text("Vazgeç") } },
    ) }
    if (skipPrompt.isNotEmpty() && !printing && outcome == null) AlertDialog(
        onDismissRequest = { skipPrompt = emptyList() },
        title = { Text("${skipPrompt.size} satır basılamaz") },
        text = { Column {
            Text("Bu ürünler BC'de bulunamadı veya bloke:")
            Spacer(Modifier.height(6.dp))
            skipPrompt.take(8).forEach { row ->
                Text("${row.order}. ${row.itemNo}  •  ${row.bin}", style = MaterialTheme.typography.titleSmall)
            }
            if (skipPrompt.size > 8) Text("… ve ${skipPrompt.size - 8} satır daha")
            Spacer(Modifier.height(8.dp))
            Text("Bu satırlar atlanıp kalan ${promptRows().size - skipPrompt.size} etiket sırayla basılsın mı?")
        } },
        confirmButton = { Button(onClick = { skipPrompt = emptyList(); startPrint(true, promptResume, promptOnly) }) {
            Text("Atlayarak yazdır (${promptRows().size - skipPrompt.size})")
        } },
        dismissButton = { TextButton(onClick = { skipPrompt = emptyList() }) { Text("Vazgeç") } },
    )
    if (printing) AlertDialog(
        onDismissRequest = {},
        properties = DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false),
        title = { Text(if (stop) "Durduruluyor…" else "Etiketler gönderiliyor…") },
        text = { Column {
            Text("$sent / $printTotal etiket yazıcıya gönderildi.")
            Spacer(Modifier.height(12.dp))
            LinearProgressIndicator(progress = { if (printTotal == 0) 0f else sent.toFloat() / printTotal }, modifier = Modifier.fillMaxWidth())
            Text("Sıra korunur; her satır bir etikettir. Durdur, mevcut 50'lik paket bitince uygulanır.")
        } },
        confirmButton = { TextButton(onClick = { stop = true }, enabled = !stop) { Text("Durdur") } },
    )
    outcome?.let { done -> AlertDialog(
        onDismissRequest = { outcome = null; rows = emptyList() },
        title = { Text(if (done.error != null || done.stopped) "Gönderim durdu" else "Etiketler gönderildi") },
        text = { Text("${done.sent} / ${done.total} etiket yazıcıya gönderildi. " +
            (done.error ?: if (done.stopped) "Kalan satırlar gönderilmedi." else "Çıktı sırası önizleme ile aynıdır.") +
            (if (skippedCount > 0) " $skippedCount satır (BC'de bulunamayan/bloke ürün) atlandı." else "") +
            " Gönderilen işler yazıcı kuyruğunda basılmaya devam edebilir.") },
        confirmButton = { TextButton(onClick = { outcome = null; rows = emptyList() }) { Text("Kapat") } },
    ) }
}

@Composable
internal fun ExcelLabelsPreview(
    rows: List<ExcelLabelRow>,
    busy: Boolean,
    error: String = "",
    source: String = "Excel sırası korunur.",
    onDismiss: () -> Unit,
    onPrint: () -> Unit,
    resumeFromOrder: Int = 0,
    resumeCount: Int = 0,
    onResume: () -> Unit = {},
    onUnprinted: (() -> Unit)? = null,
) {
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
        confirmButton = { Column(horizontalAlignment = Alignment.End) {
            if (resumeFromOrder > 0) Button(onClick = onResume, enabled = !busy) {
                Text("Kaldığı yerden devam ($resumeFromOrder'den, $resumeCount)")
            }
            if (resumeFromOrder > 0) OutlinedButton(onClick = onPrint, enabled = !busy) { Text("Baştan yazdır (${rows.size})") }
            else Button(onClick = onPrint, enabled = !busy) { Text("Tümünü yazdır (${rows.size})") }
            if (onUnprinted != null) TextButton(onClick = onUnprinted, enabled = !busy) { Text("Basılamayanları yazdır") }
        } },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("Vazgeç") } },
    )
}

@Composable
internal fun PreparedLabelsButton(enabled: Boolean, loading: Boolean, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled && !loading, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
        Text(if (loading) "Liste hazırlanıyor…" else PreparedItemLabels.BUTTON)
    }
}

/** BC'de olmayan ya da bloke ürünün satırları; sıra korunur. */
internal fun unavailableLabelRows(rows: List<ExcelLabelRow>, availableItemNos: Set<String>): List<ExcelLabelRow> =
    rows.filter { it.itemNo.uppercase(Locale.ROOT) !in availableItemNos }

/** "501–551" → 501; okunamazsa null. */
internal fun uncertainRangeStart(range: String): Int? =
    range.split('–', '-').firstOrNull()?.trim()?.toIntOrNull()?.takeIf { it > 1 }

private fun excelJobRows(body: String): List<org.json.JSONObject>? = runCatching {
    val array = org.json.JSONObject(body).getJSONArray("value")
    (0 until array.length()).map { array.getJSONObject(it) }
}.getOrNull()

private suspend fun lastExcelPrintJobId(context: android.content.Context): Int? {
    val response = BcApi.get(context, "printJobs?\$select=jobId&\$orderby=jobId desc&\$top=1")
    if (!response.ok) return null
    return excelJobRows(response.body)?.let { rows -> rows.firstOrNull()?.optInt("jobId") ?: 0 }
}

private suspend fun excelPrintJobsAfter(context: android.content.Context, jobId: Int): List<org.json.JSONObject>? {
    val response = BcApi.get(context, "printJobs?\$select=jobId,sourceDoc,status,lastError&\$filter=jobId gt $jobId&\$orderby=jobId asc&\$top=100")
    return if (response.ok) excelJobRows(response.body) else null
}
