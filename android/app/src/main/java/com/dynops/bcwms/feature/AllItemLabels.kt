package com.dynops.bcwms.feature

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
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** Etiket sayısı ne olursa olsun BC'ye tek istekte giden ürün sayısı (BC sınırı 100). */
internal const val ALL_ITEM_LABELS_BATCH = 50

/** Boş ve tekrar eden ürün numaraları atılır; sıra korunur. */
internal fun allItemLabelBatches(itemNos: List<String>, size: Int = ALL_ITEM_LABELS_BATCH): List<List<String>> =
    itemNos.map { it.trim() }.filter { it.isNotEmpty() }
        .distinctBy { it.uppercase(java.util.Locale.ROOT) }
        .chunked(size)

internal fun allItemLabelsPayload(batch: List<String>, printerId: String): String =
    JSONObject().put("itemNosJson", JSONArray(batch).toString()).put("printerId", printerId).toString()

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
fun AllItemLabelsCard(enabled: Boolean = true) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var step by remember { mutableStateOf<AllItemLabelsStep>(AllItemLabelsStep.Idle) }
    var stopRequested by remember { mutableStateOf(false) }
    var loadError by remember { mutableStateOf("") }

    OutlinedButton(
        onClick = {
            loadError = ""
            step = AllItemLabelsStep.Loading
            scope.launch {
                val page = BcApi.getAllPages(context, "items?\$select=no&\$filter=blocked eq false", maxPages = 1000)
                val itemNos = page.rows.map { it.optString("no") }
                step = if (page.complete && itemNos.isNotEmpty()) AllItemLabelsStep.Confirm(itemNos)
                else {
                    loadError = if (page.complete) "BC'de etiket basılacak ürün bulunamadı." else "Ürün listesi alınamadı. Bağlantıyı kontrol edip tekrar deneyin."
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
        } else WmsActionLabel(WmsGlyph.PRINTER, "Tüm ürünlerin etiketi")
    }
    if (loadError.isNotBlank()) Text(loadError, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)

    when (val current = step) {
        is AllItemLabelsStep.Confirm -> {
            val count = allItemLabelBatches(current.itemNos).sumOf { it.size }
            AlertDialog(
                onDismissRequest = { step = AllItemLabelsStep.Idle },
                title = { Text("Tüm ürünlerin etiketi", fontWeight = FontWeight.Bold) },
                text = {
                    Text(
                        "$count ürün için $count etiket basılacak (yaklaşık ${count * 4 / 100} metre rulo). " +
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
                                sendAllItemLabels(
                                    batches,
                                    send = { batch ->
                                        val response = BcApi.boundActionLongRunning(
                                            context, "items", batch.first(), "printLabels",
                                            allItemLabelsPayload(batch, choice.printerCode),
                                        )
                                        if (response.ok) Result.success(BcApi.scalarValue(response.body).trim().toIntOrNull() ?: batch.size)
                                        else Result.failure(IllegalStateException("${BcApi.errorMessage(response.body)} (HTTP ${response.httpCode})"))
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
