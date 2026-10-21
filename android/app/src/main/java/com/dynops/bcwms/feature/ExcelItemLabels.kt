package com.dynops.bcwms.feature

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import com.dynops.bcwms.BcApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

// Kitoko (21 Eki 2026): EMU 1.14.164–1.14.166'dan Excel'den sıralı ürün / göz
// etiketleri, sıra aralığı ve hazır aralık düğmeleri. DKÇ'ye özel "Hazır göz
// listesi" (PreparedItemLabels) alınmadı; yalnız Excel'den yükleme var.
private const val EXCEL_LABEL_SOURCE = "Excel sırası korunur."

@Composable
fun ExcelItemLabelsCard(enabled: Boolean = true) {
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
    val previewSource = EXCEL_LABEL_SOURCE
    // Seçilen sıra aralığı; kağıt bitince eksikleri ya da yarıda kalan
    // baskıyı kaldığı yerden basmak için.
    var selected by remember { mutableStateOf<List<ExcelLabelRow>>(emptyList()) }
    var resume by remember { mutableStateOf(preferences.getString("resume", "").orEmpty()) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            loading = true
            error = ""
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
        resume = labelResumeRange(resume, previewSource, rows.size),
        onDismiss = { if (!loading) rows = emptyList() },
        onPrint = { chosen ->
            selected = chosen
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
                    val missing = chosen.filter { it.itemNo.uppercase(Locale.ROOT) !in available }
                    check(missing.isEmpty()) {
                        "${missing.size} satırdaki ürün bulunamadı veya bloke: ${missing.take(5).joinToString { it.itemNo }}. Hiçbir etiket gönderilmedi."
                    }
                    printing = true
                    loading = false
                    stop = false
                    sent = 0
                    val result = sendExcelLabels(chosen, send = { batch ->
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
                            if (response.httpCode == 404) "Bu işlem için BCWMSApp 1.14.3.13 veya üzeri gerekir."
                            else "${BcApi.errorMessage(response.body)} (HTTP ${response.httpCode})"))
                    }, stopRequested = { stop }, onProgress = { done, _ -> sent = done })
                    // Yarıda kalırsa bir sonraki açılışta "Kaldığı yerden" önerilir.
                    resume = if (result.sent < result.total) {
                        labelResumeValue(previewSource, rows.size, chosen[result.sent].order, chosen.last().order)
                    } else ""
                    withContext(Dispatchers.IO) { preferences.edit().putString("resume", resume).commit() }
                    outcome = result
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
            Text("$sent / ${selected.size} etiket yazıcıya gönderildi.")
            Spacer(Modifier.height(12.dp))
            LinearProgressIndicator(progress = { sent.toFloat() / selected.size.coerceAtLeast(1) }, modifier = Modifier.fillMaxWidth())
            Text("Sıra korunur; her satır bir etikettir. Durdur, mevcut 50'lik paket bitince uygulanır.")
        } },
        confirmButton = { TextButton(onClick = { stop = true }, enabled = !stop) { Text("Durdur") } },
    )
    outcome?.let { done -> AlertDialog(
        onDismissRequest = { outcome = null; rows = emptyList() },
        title = { Text(if (done.error != null || done.stopped) "Gönderim durdu" else "Etiketler gönderildi") },
        text = { Text("${done.sent} / ${done.total} etiket yazıcıya gönderildi. " +
            (done.error ?: if (done.stopped) "Kalan satırlar gönderilmedi." else "Çıktı sırası önizleme ile aynıdır.") +
            (if (done.sent < done.total) " Kaldığı yerden devam: sıra ${selected[done.sent].order}." else "") +
            " Gönderilen işler yazıcı kuyruğunda basılmaya devam edebilir.") },
        confirmButton = { TextButton(onClick = { outcome = null; rows = emptyList() }) { Text("Kapat") } },
    ) }
}

@Composable
internal fun ExcelLabelsPreview(
    rows: List<ExcelLabelRow>,
    busy: Boolean,
    error: String = "",
    source: String = EXCEL_LABEL_SOURCE,
    resume: IntRange? = null,
    presets: List<IntRange> = LABEL_RANGE_PRESETS,
    onDismiss: () -> Unit,
    onPrint: (List<ExcelLabelRow>) -> Unit,
) {
    val first = rows.first().order
    val last = rows.last().order
    var from by remember(rows) { mutableStateOf(first.toString()) }
    var to by remember(rows) { mutableStateOf(last.toString()) }
    val range = labelRange(rows, from, to)
    val chosen = range.getOrDefault(emptyList())
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text("${rows.size} etiket hazır") },
        text = { Column {
            Text("$source Her satır bir etiket.", style = MaterialTheme.typography.bodySmall)
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = from, onValueChange = { from = it.filter(Char::isDigit).take(5) },
                    label = { Text("İlk sıra") }, singleLine = true, enabled = !busy,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.weight(1f).testTag("label-range-from"),
                )
                OutlinedTextField(
                    value = to, onValueChange = { to = it.filter(Char::isDigit).take(5) },
                    label = { Text("Son sıra") }, singleLine = true, enabled = !busy,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.weight(1f).testTag("label-range-to"),
                )
            }
            val shown = presets.filter { it.first >= first && it.last <= last }
            if (shown.isNotEmpty()) Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                shown.forEach { preset ->
                    val active = from == preset.first.toString() && to == preset.last.toString()
                    val pick = { from = preset.first.toString(); to = preset.last.toString() }
                    val label: @Composable () -> Unit = {
                        Text("${preset.first}–${preset.last}", maxLines = 1, softWrap = false,
                            style = MaterialTheme.typography.labelLarge)
                    }
                    val chipModifier = Modifier.weight(1f).heightIn(min = 40.dp).testTag("label-range-preset-${preset.first}")
                    val padding = PaddingValues(horizontal = 4.dp)
                    if (active) Button(onClick = pick, enabled = !busy, modifier = chipModifier, contentPadding = padding) { label() }
                    else OutlinedButton(onClick = pick, enabled = !busy, modifier = chipModifier, contentPadding = padding) { label() }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton(
                    onClick = { from = first.toString(); to = last.toString() }, enabled = !busy,
                    modifier = Modifier.testTag("label-range-all"),
                ) { Text("Tümü") }
                if (resume != null) TextButton(
                    onClick = { from = resume.first.toString(); to = resume.last.toString() }, enabled = !busy,
                    modifier = Modifier.testTag("label-range-resume"),
                ) { Text("Kaldığı yerden (${resume.first}–${resume.last})") }
            }
            range.exceptionOrNull()?.let { Text(it.message.orEmpty(), color = MaterialTheme.colorScheme.error) }
            Spacer(Modifier.height(8.dp))
            LazyColumn(Modifier.heightIn(max = 260.dp)) {
                items(chosen, key = { it.order }) { row ->
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
        confirmButton = {
            Button(onClick = { onPrint(chosen) }, enabled = !busy && chosen.isNotEmpty(), modifier = Modifier.testTag("label-range-print")) {
                Text(if (chosen.size == rows.size) "Tümünü yazdır (${chosen.size})" else "Yazdır (${chosen.size})")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("Vazgeç") } },
    )
}

/** Sık basılan bloklar tek dokunuşla seçilir (EMU, 21 Eki 2026). */
internal val LABEL_RANGE_PRESETS = listOf(301..500, 501..700, 701..1000)

/** Sıra numarasına göre aralık (ikisi dahil). Liste sırası ve tekrarlar korunur. */
internal fun labelRange(rows: List<ExcelLabelRow>, fromText: String, toText: String): Result<List<ExcelLabelRow>> = runCatching {
    require(rows.isNotEmpty()) { "Liste boş." }
    val first = rows.first().order
    val last = rows.last().order
    val from = fromText.trim().toIntOrNull()
    val to = toText.trim().toIntOrNull()
    require(from != null && to != null) { "İlk ve son sıra numarasını yazın." }
    require(from in first..last && to in first..last) { "Sıra numarası $first ile $last arasında olmalı." }
    require(from <= to) { "İlk sıra son sıradan büyük olamaz." }
    rows.filter { it.order in from..to }
}

internal fun labelResumeValue(source: String, total: Int, from: Int, to: Int): String = "$source|$total|$from|$to"

/** Kayıtlı devam noktası yalnız aynı liste (kaynak + satır sayısı) açıldığında önerilir. */
internal fun labelResumeRange(value: String, source: String, total: Int): IntRange? {
    val parts = value.split("|")
    if (parts.size != 4 || parts[0] != source || parts[1] != total.toString()) return null
    val from = parts[2].toIntOrNull() ?: return null
    val to = parts[3].toIntOrNull() ?: return null
    return if (from <= to) from..to else null
}
