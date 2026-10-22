package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.BuildConfig
import com.dynops.bcwms.ui.StatusText
import com.dynops.bcwms.ui.WmsActionLabel
import com.dynops.bcwms.ui.WmsGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

// Kitoko (22 Eki 2026): Taşıma Kabı ekranından HER LP'nin (içerikli olanlar dahil)
// LP etiketi etiket (ZPL) yazıcısına: printLabel / printLabelWithLayout, LP etiket
// tasarımı ve adet. MTE ve "LP QR Belgesi (A4)" ayrı düğmeler olarak kalır.

/** LP ekranındaki "LP Etiketi Yazdır" düğmeleri yalnız Kitoko'da; BADE/EMU aynen kalır. */
internal fun lpLabelActionsOffered(flavor: String = BuildConfig.FLAVOR): Boolean =
    flavor.equals("kitoko", ignoreCase = true)

internal data class LpLabelPrintOutcome(
    val printerCode: String,
    val warning: String,
    val printed: List<String>,
    /** LP No → hata (gönderilen kısmi adet notuyla). */
    val failures: Map<String, String>,
    /** Yazıcı çözülemediyse hiçbir istek gitmez. */
    val error: String = "",
)

/** Operatöre gösterilen tek satır sonuç. */
internal fun lpLabelPrintStatus(outcome: LpLabelPrintOutcome, copies: Int, layoutCode: String): String {
    if (outcome.error.isNotBlank()) return "HATA: ${outcome.error}"
    val warning = if (outcome.warning.isBlank()) "" else " ${outcome.warning}"
    val target = outcome.printerCode.ifBlank { "BC yazıcı eşlemesi" }
    if (outcome.failures.isEmpty()) {
        val what = if (outcome.printed.size == 1) "${outcome.printed.first()} LP etiketi" else "${outcome.printed.size} LP etiketi"
        return "TAMAM: $what × $copies $target kuyruğuna alındı." + labelLayoutNote(layoutCode) + warning
    }
    val (firstNo, firstError) = outcome.failures.entries.first()
    val okPart = if (outcome.printed.isEmpty()) "" else " ${outcome.printed.size} LP kuyruğa alındı;"
    return "UYARI:$okPart ${outcome.failures.size} LP etiketi yazdırılamadı. $firstNo: $firstError$warning"
}

/**
 * LP'lerin LP etiketi sırayla; her LP'de adet 10'luk işlere bölünür. Hata alan
 * LP atlanır, diğerleri basılır (yeniden denemede yalnız başarısızlar seçili kalır).
 */
internal suspend fun printLpLabelsToLabelPrinter(
    context: Context,
    lpNos: List<String>,
    copies: Int,
    layoutCode: String,
    onProgress: (done: Int, total: Int) -> Unit = { _, _ -> },
): LpLabelPrintOutcome {
    val choice = resolveInquiryPrinter(context).getOrElse {
        return LpLabelPrintOutcome("", "", emptyList(), emptyMap(), it.message.orEmpty().ifBlank { "Yazıcı seçilemedi." })
    }
    val printed = mutableListOf<String>()
    val failures = linkedMapOf<String, String>()
    val action = labelPrintAction(layoutCode)
    lpNos.forEachIndexed { index, lpNo ->
        onProgress(index, lpNos.size)
        var sent = 0
        for (batch in labelCopyBatches(copies)) {
            val r = try {
                BcApi.boundActionLongRunning(context, "licensePlates", lpNo, action, labelPrintPayload(choice.printerCode, batch, layoutCode))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                BcApi.ApiResult(false, -1, error.message.orEmpty())
            }
            if (!r.ok) {
                val message = if (r.httpCode == -1) r.body.ifBlank { "bağlantı hatası" }
                    else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode).removePrefix("HATA: ")
                failures[lpNo] = message + if (sent > 0) " ($copies adetin $sent adedi kuyruğa alınmıştı)" else ""
                break
            }
            sent += batch
        }
        if (lpNo !in failures) printed += lpNo
    }
    onProgress(lpNos.size, lpNos.size)
    return LpLabelPrintOutcome(choice.printerCode, choice.warning, printed, failures)
}

/**
 * LP etiketi baskı penceresi: etiket yazıcısı bilgisi, LP etiket tasarımı, LP
 * başına adet. Bitince [onFinished] sonuç satırını ve başarısız LP'leri verir.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LpLabelPrintSheet(
    lpNos: List<String>,
    onDismiss: () -> Unit,
    onFinished: (status: String, failed: Set<String>) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val layout = rememberLabelLayoutChoice(LabelLayoutKind.LP)
    var copies by remember { mutableStateOf("1") }
    var printing by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    val labelPrinter = remember { getDefaultPrinter(context, PRINTER_USAGE_LABEL) }
    val documentPrinter = remember { getDefaultPrinter(context, PRINTER_USAGE_DOCUMENT) }

    fun print() {
        if (printing || lpNos.isEmpty()) return
        val total = parseLabelCopies(copies) ?: run { status = "HATA: Etiket adedi 1 ile $LABEL_COPIES_MAX arasında olmalı."; return }
        printing = true
        scope.launch {
            try {
                val code = layout.awaitLayoutCode(context)
                val outcome = printLpLabelsToLabelPrinter(context, lpNos, total, code) { done, all ->
                    status = "🖨 LP etiketi gönderiliyor: $done/$all"
                }
                onFinished(lpLabelPrintStatus(outcome, total, code), outcome.failures.keys + if (outcome.error.isNotBlank()) lpNos else emptyList())
            } finally {
                printing = false
            }
        }
    }

    ModalBottomSheet(onDismissRequest = { if (!printing) onDismiss() }) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                if (lpNos.size == 1) "LP Etiketi Yazdır · ${lpNos.first()}" else "LP Etiketi Yazdır · ${lpNos.size} LP",
                fontWeight = FontWeight.Bold, fontSize = 18.sp,
            )
            Text(
                "LP etiketi (QR = LP No) etiket yazıcısına gider; içerikli LP'de de MTE değil LP etiketi basılır.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                when {
                    labelPrinter.isNotBlank() -> "Etiket yazıcısı: $labelPrinter"
                    documentPrinter.isNotBlank() -> "Etiket yazıcısı seçilmedi; belge yazıcısı $documentPrinter kullanılacak. Yazıcılar ekranından etiket yazıcısı seçin."
                    else -> "Etiket yazıcısı seçilmedi. Yazıcılar ekranından bir etiket yazıcısı seçin."
                },
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = if (labelPrinter.isNotBlank()) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.error,
            )
            LabelLayoutSelector(layout, enabled = !printing)
            LabelCopiesField(copies, { copies = it }, enabled = !printing, label = if (lpNos.size == 1) "Etiket adedi" else "LP başına adet")
            StatusText(status)
            Button(
                onClick = { print() },
                enabled = !printing && lpNos.isNotEmpty(),
                modifier = Modifier.fillMaxWidth().height(54.dp),
                shape = RoundedCornerShape(14.dp),
            ) { WmsActionLabel(WmsGlyph.PRINTER, if (printing) "Gönderiliyor..." else "LP Etiketi Yazdır") }
            TextButton(onClick = onDismiss, enabled = !printing, modifier = Modifier.fillMaxWidth()) { Text("Vazgeç") }
        }
    }
}
