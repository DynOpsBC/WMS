package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.ui.WmsActionLabel
import com.dynops.bcwms.ui.WmsGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/** Etiket sayısı ne olursa olsun BC'ye tek istekte giden ürün sayısı (BC sınırı 100). */
internal const val ALL_ITEM_LABELS_BATCH = 50

/** Ürün no sırasındaki konumlar; Kitoko'da tamamlanan eski bloklar gösterilmez. */
internal fun itemLabelRanges(kitoko: Boolean): List<IntRange> = if (kitoko) {
    listOf(1251..1500, 1501..1750, 1751..2000, 2001..2250)
} else {
    listOf(1..300, 301..500, 501..700, 701..1000, 1001..1250, 1251..1500)
}

/** Boş ve tekrar eden ürün numaraları atılır; sıra korunur. */
internal fun allItemLabelBatches(itemNos: List<String>, size: Int = ALL_ITEM_LABELS_BATCH): List<List<String>> =
    itemNos.map { it.trim() }.filter { it.isNotEmpty() }
        .distinctBy { it.uppercase(java.util.Locale.ROOT) }
        .chunked(size)

internal fun allItemLabelsPayload(batch: List<String>, printerId: String, layoutCode: String = ""): String =
    JSONObject().put("itemNosJson", JSONArray(batch).toString()).put("printerId", printerId)
        .apply { if (layoutCode.isNotBlank()) put("layoutCode", layoutCode) }
        .toString()

/** Tasarım seçiliyse items/printLabelsWithLayout; değilse kartın eski aksiyonu (printLabels / printLabelsV2). */
internal fun allItemLabelsAction(v2Format: Boolean, layoutCode: String): String = when {
    layoutCode.isNotBlank() -> "printLabelsWithLayout"
    v2Format -> "printLabelsV2"
    else -> "printLabels"
}

/**
 * Kitoko (21 Eki 2026): tasarım ekranın üstünde seçildiğinde düğmede yalnız
 * aralık yazar; seçici yoksa eski başlıklar (ETIKETV2 adıyla) kalır.
 */
internal fun allItemLabelsTitle(range: IntRange?, v2Format: Boolean, withLayoutPicker: Boolean): String = when {
    withLayoutPicker && range != null && range.first == 1 -> "İlk ${range.last} ürünün etiketi"
    withLayoutPicker && range != null -> "Ürün ${range.first}–${range.last} etiketi"
    withLayoutPicker -> "Tüm ürünlerin etiketi"
    range != null && range.first == 1 && v2Format -> "İlk ${range.last} ürün · ETIKETV2 (QR + madde no)"
    range != null && v2Format -> "Ürün ${range.first}–${range.last} · ETIKETV2 (QR + madde no)"
    v2Format -> "Tüm ürünlerin etiketi · ETIKETV2 (QR + madde no)"
    else -> "Tüm ürünlerin etiketi"
}

internal data class AllItemLabelsOutcome(val sent: Int, val total: Int, val stopped: Boolean, val error: String? = null)

/**
 * Paketleri sırayla gönderir. Durdur isteği gönderilmekte olan paketi kesmez
 * (BC'de yarım paket kalmasın); bir sonraki paketten önce durur. Hata olursa
 * otomatik tekrar denenmez: aynı etiket iki kez basılmasın.
 */
internal suspend fun sendAllItemLabels(
    batches: List<List<String>>,
    send: suspend (List<String>) -> Result<Int>,
    stopRequested: () -> Boolean,
    onProgress: (sent: Int, total: Int) -> Unit = { _, _ -> },
): AllItemLabelsOutcome {
    val total = batches.sumOf { it.size }
    var sent = 0
    onProgress(sent, total)
    for (batch in batches) {
        if (stopRequested()) return AllItemLabelsOutcome(sent, total, stopped = true)
        val result = try {
            send(batch)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            Result.failure(error)
        }
        val error = result.exceptionOrNull()
        if (error != null) return AllItemLabelsOutcome(sent, total, stopped = false, error = error.message ?: "Gönderim başarısız.")
        sent += result.getOrDefault(batch.size)
        onProgress(sent, total)
    }
    return AllItemLabelsOutcome(sent, total, stopped = false)
}

internal sealed interface PrintBatchState {
    data object Waiting : PrintBatchState
    data object Delivered : PrintBatchState
    data class Failed(val message: String) : PrintBatchState
}

/**
 * Kitoko (21 Eki 2026): BC her paketi ayrı bir arka plan göreviyle yazıcıya
 * iletir; görevler yer değiştirirse paketler karışık basılır. Paketin işi
 * (gönderimden sonra açılan, kaynağı paketteki bir ürün olan iş) "Queued"dan
 * çıkmadan sonraki paket gönderilmez. Yazıcı ajanı işleri geliş sırasıyla tek tek basar.
 */
internal fun printBatchState(jobs: List<JSONObject>, batch: List<String>): PrintBatchState {
    val itemNos = batch.map { it.trim().uppercase(Locale.ROOT) }.toSet()
    val own = jobs.filter { it.optString("sourceDoc").trim().uppercase(Locale.ROOT) in itemNos }
    if (own.isEmpty()) return PrintBatchState.Waiting
    own.firstOrNull { it.optString("status").equals("Failed", ignoreCase = true) }?.let {
        return PrintBatchState.Failed(it.optString("lastError").ifBlank { "Yazdırma işi başarısız." })
    }
    return if (own.any { it.optString("status").equals("Queued", ignoreCase = true) }) PrintBatchState.Waiting
    else PrintBatchState.Delivered
}

internal const val PRINT_BATCH_POLL_MS = 2_000L
internal const val PRINT_BATCH_MAX_WAIT_MS = 5 * 60_000L

/** BC yazdırma kuyruğu okunamıyorsa (yetki/eski sürüm) paketler arasında beklenen süre. */
internal const val PRINT_BATCH_FALLBACK_GAP_MS = 20_000L

/** null: paket yazıcıya iletildi. Aksi halde kalan paketleri durduran hata metni. */
internal suspend fun awaitPrintBatch(
    batch: List<String>,
    fetchJobs: suspend () -> List<JSONObject>?,
    pause: suspend (Long) -> Unit,
    pollMs: Long = PRINT_BATCH_POLL_MS,
    maxWaitMs: Long = PRINT_BATCH_MAX_WAIT_MS,
): String? {
    var waited = 0L
    while (true) {
        // Okunamayan yanıt (ağ kesintisi) beklemeye sayılır; süre dolunca durur.
        when (val state = fetchJobs()?.let { printBatchState(it, batch) } ?: PrintBatchState.Waiting) {
            PrintBatchState.Delivered -> return null
            is PrintBatchState.Failed ->
                return "${batch.first()}–${batch.last()} paketi yazıcıya iletilemedi: ${state.message} Sıra bozulmasın diye kalan etiketler gönderilmedi."
            PrintBatchState.Waiting -> Unit
        }
        if (waited >= maxWaitMs) return "${batch.first()}–${batch.last()} paketi ${maxWaitMs / 60_000} dakikadır yazıcıya iletilmedi. " +
            "Sıra bozulmasın diye kalan etiketler gönderilmedi; yazıcı ajanını ve BC yazdırma kuyruğunu kontrol edin."
        pause(pollMs)
        waited += pollMs
    }
}

private fun jobRows(body: String): List<JSONObject>? = runCatching {
    val array = JSONObject(body).getJSONArray("value")
    (0 until array.length()).map { array.getJSONObject(it) }
}.getOrNull()

private suspend fun lastPrintJobId(context: Context): Int? {
    val response = BcApi.get(context, "printJobs?\$select=jobId&\$orderby=jobId desc&\$top=1")
    if (!response.ok) return null
    return jobRows(response.body)?.let { rows -> rows.firstOrNull()?.optInt("jobId") ?: 0 }
}

private suspend fun printJobsAfter(context: Context, jobId: Int): List<JSONObject>? {
    val response = BcApi.get(context, "printJobs?\$select=jobId,sourceDoc,status,lastError&\$filter=jobId gt $jobId&\$orderby=jobId asc&\$top=100")
    return if (response.ok) jobRows(response.body) else null
}

private sealed interface AllItemLabelsStep {
    data object Idle : AllItemLabelsStep
    data object Loading : AllItemLabelsStep
    data class Confirm(val itemNos: List<String>) : AllItemLabelsStep
    data class Printing(val sent: Int, val total: Int, val stopping: Boolean) : AllItemLabelsStep
    data class Done(val outcome: AllItemLabelsOutcome) : AllItemLabelsStep
}

/**
 * DKÇ (9 Eki 2026): BC'deki bütün (bloke olmayan) ürünlerin etiketi. Basarken
 * dönen gösterge ve "X / N", Durdur'a basınca o anki paket bitince durur.
 */
@Composable
internal fun AllItemLabelsCard(
    enabled: Boolean = true,
    v2Format: Boolean = false,
    itemLimit: Int? = null,
    itemRange: IntRange? = null,
    // Kitoko (21 Eki 2026): ekranın üstündeki "Etiket tasarımı" seçimi; boş = eski aksiyon.
    layout: LabelLayoutChoice? = null,
) {
    // Kitoko (21 Eki 2026): ürün no sırasına göre 301–500, 501–700 gibi bloklar.
    val range = itemRange ?: itemLimit?.let { 1..it }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val title = allItemLabelsTitle(range, v2Format, layout != null)
    val defaultDesign = if (v2Format) "ETIKETV2" else "BC'de aktif tasarım"
    var step by remember { mutableStateOf<AllItemLabelsStep>(AllItemLabelsStep.Idle) }
    var stopRequested by remember { mutableStateOf(false) }
    var loadError by remember { mutableStateOf("") }

    OutlinedButton(
        onClick = {
            loadError = ""
            step = AllItemLabelsStep.Loading
            scope.launch {
                val query = buildString {
                    append("items?\$select=no&\$filter=blocked eq false")
                    if (range != null) append("&\$orderby=no asc&\$top=${range.last}")
                }
                val page = BcApi.getAllPages(context, query, maxPages = 1000)
                val itemNos = page.rows.map { it.optString("no") }.let { rows ->
                    if (range == null) rows else itemsInRange(rows, range)
                }
                step = if (page.complete && itemNos.isNotEmpty()) AllItemLabelsStep.Confirm(itemNos)
                else {
                    loadError = if (page.complete) {
                        allItemLabelsEmptyMessage(range, page.rows.size, BcApi.getEnvironment(context), BcApi.getCompanyName(context))
                    } else "Ürün listesi alınamadı. Bağlantıyı kontrol edip tekrar deneyin."
                    AllItemLabelsStep.Idle
                }
            }
        },
        enabled = enabled && step == AllItemLabelsStep.Idle,
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
    ) {
        if (step == AllItemLabelsStep.Loading) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            Spacer(Modifier.width(10.dp))
            Text("Ürün listesi alınıyor…")
        } else WmsActionLabel(WmsGlyph.PRINTER, title)
    }
    if (loadError.isNotBlank()) Text(loadError, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)

    when (val current = step) {
        is AllItemLabelsStep.Confirm -> {
            val count = allItemLabelBatches(current.itemNos).sumOf { it.size }
            AlertDialog(
                onDismissRequest = { step = AllItemLabelsStep.Idle },
                title = { Text(title, fontWeight = FontWeight.Bold) },
                text = {
                    val design = layout?.layoutCode.orEmpty().ifBlank { defaultDesign }
                    Text(
                        "$count ürün için $count etiket basılacak (yaklaşık ${count * 4 / 100} metre rulo). " +
                            (if (layout != null) "Tasarım: $design. " else "") +
                            "Ürün no sırasıyla basılır; bir paket yazıcıya ulaşmadan sonraki gönderilmez. " +
                            "İstediğiniz an Durdur'a basabilirsiniz."
                    )
                },
                confirmButton = {
                    Button(onClick = {
                        val batches = allItemLabelBatches(current.itemNos)
                        stopRequested = false
                        step = AllItemLabelsStep.Printing(0, count, stopping = false)
                        scope.launch {
                            val outcome = try {
                                val choice = resolveInquiryPrinter(context).getOrElse {
                                    step = AllItemLabelsStep.Done(AllItemLabelsOutcome(0, count, false, it.message ?: "Yazıcı seçimi doğrulanamadı."))
                                    return@launch
                                }
                                val layoutCode = layout?.awaitLayoutCode(context).orEmpty()
                                val action = allItemLabelsAction(v2Format, layoutCode)
                                sendAllItemLabels(
                                    batches,
                                    send = { batch ->
                                        val lastJobId = lastPrintJobId(context)
                                        val response = BcApi.boundActionLongRunning(
                                            context, "items", batch.first(), action,
                                            allItemLabelsPayload(batch, choice.printerCode, layoutCode),
                                        )
                                        if (!response.ok) Result.failure(IllegalStateException("${BcApi.errorMessage(response.body)} (HTTP ${response.httpCode})"))
                                        else {
                                            val count = BcApi.scalarValue(response.body).trim().toIntOrNull() ?: batch.size
                                            val orderError = if (lastJobId == null) {
                                                delay(PRINT_BATCH_FALLBACK_GAP_MS)
                                                null
                                            } else awaitPrintBatch(batch, fetchJobs = { printJobsAfter(context, lastJobId) }, pause = { delay(it) })
                                            if (orderError == null) Result.success(count) else Result.failure(IllegalStateException(orderError))
                                        }
                                    },
                                    stopRequested = { stopRequested },
                                    onProgress = { sent, total -> step = AllItemLabelsStep.Printing(sent, total, stopRequested) },
                                )
                            } catch (cancelled: CancellationException) {
                                throw cancelled
                            } catch (error: Exception) {
                                AllItemLabelsOutcome(0, count, false, error.message ?: "Yazdırma başlatılamadı.")
                            }
                            step = AllItemLabelsStep.Done(outcome)
                        }
                    }) { Text("Yazdır", fontWeight = FontWeight.Bold) }
                },
                dismissButton = { OutlinedButton(onClick = { step = AllItemLabelsStep.Idle }) { Text("Vazgeç") } },
            )
        }
        is AllItemLabelsStep.Printing -> AlertDialog(
            onDismissRequest = {},
            properties = DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false),
            title = { Text(if (current.stopping) "Durduruluyor…" else "Yazdırılıyor…", fontWeight = FontWeight.Bold) },
            text = {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                    CircularProgressIndicator(Modifier.size(48.dp))
                    Spacer(Modifier.height(16.dp))
                    Text("${current.sent} / ${current.total} etiket gönderildi", fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(8.dp))
                    LinearProgressIndicator(
                        progress = { if (current.total == 0) 0f else current.sent.toFloat() / current.total },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (current.stopping) {
                        Spacer(Modifier.height(8.dp))
                        Text("Gönderilmekte olan paket bitince duracak.", style = MaterialTheme.typography.bodySmall)
                    }
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        stopRequested = true
                        step = current.copy(stopping = true)
                    },
                    enabled = !current.stopping,
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                ) { Text("Durdur", fontWeight = FontWeight.Bold) }
            },
        )
        is AllItemLabelsStep.Done -> {
            val outcome = current.outcome
            AlertDialog(
                onDismissRequest = { step = AllItemLabelsStep.Idle },
                title = {
                    Text(
                        when {
                            outcome.error != null -> "Yazdırma durdu"
                            outcome.stopped -> "Durduruldu"
                            else -> "Tamamlandı"
                        },
                        fontWeight = FontWeight.Bold,
                    )
                },
                text = {
                    Column {
                        Text("${outcome.sent} / ${outcome.total} etiket yazıcıya gönderildi.")
                        if (outcome.stopped || outcome.error != null) {
                            Spacer(Modifier.height(6.dp))
                            Text(
                                "Gönderilen etiketler yazıcı kuyruğundan basılmaya devam eder.",
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                        outcome.error?.let {
                            Spacer(Modifier.height(6.dp))
                            Text("HATA: $it", color = MaterialTheme.colorScheme.error)
                        }
                    }
                },
                confirmButton = { Button(onClick = { step = AllItemLabelsStep.Idle }) { Text("Kapat") } },
            )
        }
        else -> Unit
    }
}

/** Ürün no sırasındaki 1'den başlayan konumlar (ikisi dahil). */
/**
 * Kitoko (27 Eki 2026): demo ortamda 1251'den az ürün olduğu için aralıklar boş
 * geliyordu; mesaj bağlantıyı ve ürün sayısını söyler ki yanlış ortam fark edilsin.
 */
internal fun allItemLabelsEmptyMessage(range: IntRange?, itemCount: Int, environment: String, company: String): String =
    if (range != null && itemCount < range.first) {
        "Bu aralıkta ürün yok: $environment · $company bağlantısında $itemCount ürün var, aralık ${range.first}. üründen başlıyor. Ortam / şirket seçimini kontrol edin."
    } else "BC'de etiket basılacak ürün bulunamadı."

internal fun <T> itemsInRange(rows: List<T>, range: IntRange): List<T> =
    rows.drop(range.first - 1).take(range.last - range.first + 1)
