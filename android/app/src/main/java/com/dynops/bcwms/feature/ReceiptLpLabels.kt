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
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.BuildConfig
import org.json.JSONObject

// Kitoko (22 Eki 2026): Kitoko MTE (BADE kozmetik etiketi) kullanmaz. Mal kabul
// kaydında BC'ye her zaman "yazdırmadan" isteği gider (BC MTE basmaz); terminal
// bu kayıtla stoğa giren her LP için LP etiketini etiket yazıcısına basar.
// BADE/EMU aynen kalır.

/** Kitoko: mal kabul etiketleri terminalden (LP etiketi); BC'de MTE yok. */
internal fun terminalPrintsReceiptLabels(flavor: String = BuildConfig.FLAVOR): Boolean =
    flavor.equals("kitoko", ignoreCase = true)

/** MTE düğmeleri/bölümleri: Kitoko dışında (BADE/EMU/DynamicsOps) aynen gösterilir. */
internal fun mteOffered(flavor: String = BuildConfig.FLAVOR): Boolean = !terminalPrintsReceiptLabels(flavor)

/**
 * Kitoko'da kayıt her zaman "Yazdırmadan kaydet" ile aynı aksiyona (postToPrinter,
 * BC'de LP/MTE etiketi yok) gider; yalnız "Belgeyi yazdır" seçiliyse mal kabul
 * belgesi belge yazıcısından basılır. Diğer flavor'larda [receiptPostRequest] aynen.
 */
internal fun receiptPostRequestFor(
    flavor: String,
    skipPrinting: Boolean,
    printReceipt: Boolean,
    documentPrinter: String,
    lpPrinter: String,
): ReceiptPostRequest {
    if (!terminalPrintsReceiptLabels(flavor)) return receiptPostRequest(skipPrinting, printReceipt, documentPrinter, lpPrinter)
    val printDocument = !skipPrinting && printReceipt
    return ReceiptPostRequest("postToPrinter", JSONObject().apply {
        put("print", printDocument)
        put("invoice", false)
        put("printerId", if (printDocument) documentPrinter else "")
    }.toString())
}

/** Kayıttan sonra terminal LP etiketi basar mı: Kitoko ve "Yazdırmadan kaydet" işaretli değil. */
internal fun receiptAutoLpLabels(flavor: String, skipPrinting: Boolean): Boolean =
    terminalPrintsReceiptLabels(flavor) && !skipPrinting

/**
 * Bu kayda katılan LP'ler (kayıttan önce bilinen): miktarı kaydedilecek mal kabul
 * satırlarının LP'si ve belgenin aktif LP'si. Toplu/karma palet taslakları
 * (satırda LP yok) kayıttan sonra yeni içerikli LP olarak ayrıca bulunur.
 */
internal fun receiptPostLpCandidates(postLines: List<JSONObject>, headerLpNo: String?, activeLpNo: String?): Set<String> =
    (postLines.map { it.optString("licensePlateNo").trim() } + listOfNotNull(headerLpNo?.trim(), activeLpNo?.trim()))
        .filter { it.isNotBlank() && it != "null" }
        .toSet()

/**
 * Bu kayıtla kapanan/stoğa giren LP'ler: kayıttan sonra bu mal kabule ait içerikli
 * LP'lerden kayıttan önce içeriği olmayanlar (taslaklar bu kayıtta doldu) ile bu
 * kayda katılan [candidates]. Önceki kısmi kabullerin LP'leri tekrar basılmaz.
 */
internal fun receiptLpsClosedByPost(
    receiptNo: String,
    linesBeforePost: List<JSONObject>,
    linesAfterPost: List<JSONObject>,
    candidates: Set<String>,
): List<String> {
    val before = receiptMteLpNos(receiptNo, linesBeforePost).toSet()
    return receiptMteLpNos(receiptNo, linesAfterPost).filter { it !in before || it in candidates }
}

internal data class ReceiptAutoLabelResult(
    val lpNos: List<String>,
    val lpPrinted: List<String>,
    /** "LP No" ya da "LP No lot" → hata. */
    val failures: Map<String, String>,
    val lotRequested: Int = 0,
    val lotPrinted: Int = 0,
    val printerCode: String = "",
    /** Hiç istek gitmediyse (LP listesi okunamadı, yazıcı yok): operatör Etiketler ekranından basar. */
    val error: String = "",
)

/** Kayıttan sonra operatöre gösterilen tek mesaj; hatalı LP'leri listeler, otomatik tekrar yoktur. */
internal fun receiptAutoLabelStatus(result: ReceiptAutoLabelResult): String {
    if (result.error.isNotBlank()) return "UYARI: Mal kabul kaydedildi, LP etiketi basılmadı: ${result.error} Etiketler ekranından basın."
    if (result.lpNos.isEmpty()) return "TAMAM: Mal kabul kaydedildi. Bu kayıtta etiketlenecek LP bulunamadı."
    val target = result.printerCode.ifBlank { "BC yazıcı eşlemesi" }
    val lotPart = if (result.lotRequested > 0) " + ${result.lotPrinted}/${result.lotRequested} LP'nin lot etiketi" else ""
    if (result.failures.isEmpty())
        return "TAMAM: Mal kabul kaydedildi. ${result.lpPrinted.size} LP etiketi$lotPart $target kuyruğuna alındı."
    val listed = result.failures.entries.joinToString("; ") { (key, error) -> "$key: $error" }
    return "UYARI: Mal kabul kaydedildi. ${result.lpPrinted.size}/${result.lpNos.size} LP etiketi$lotPart kuyruğa alındı. " +
        "Basılamayan ${result.failures.size}: $listed. Otomatik tekrar denenmedi; çıktıları kontrol edip yalnız eksikleri Etiketler ekranından basın."
}

internal fun receiptLpLinesPath(receiptNo: String): String =
    "licensePlateLines?\$filter=sourceDocumentType eq 'WhseReceipt' and sourceDocumentNo eq '${receiptNo.replace("'", "''")}' and quantity gt 0"

/**
 * Kitoko: kayıttan sonra [lpNos] için birer LP etiketi (printLabel /
 * printLabelWithLayout, [lpLayoutCode]) ve istenirse lot takipli LP'lerin lot
 * etiketi. Hata alan atlanır, otomatik tekrar yoktur (çift baskı olmasın).
 */
internal suspend fun printReceiptLpLabels(
    context: Context,
    lpNos: List<String>,
    lpLines: List<JSONObject>,
    lpLayoutCode: String,
    lotLayoutCode: String?,
    onProgress: (String) -> Unit,
): ReceiptAutoLabelResult {
    if (lpNos.isEmpty()) return ReceiptAutoLabelResult(lpNos, emptyList(), emptyMap())
    val outcome = printLpLabelsToLabelPrinter(context, lpNos, 1, lpLayoutCode) { done, all ->
        if (done < all) onProgress("🖨 LP etiketi gönderiliyor: ${done + 1}/$all · ${lpNos[done]}")
    }
    if (outcome.error.isNotBlank()) return ReceiptAutoLabelResult(lpNos, emptyList(), emptyMap(), error = outcome.error)
    val failures = linkedMapOf<String, String>()
    failures.putAll(outcome.failures)
    val lotTargets = if (lotLayoutCode == null) emptyList() else receiptLotLabelLpNos(lpNos, lpLines)
    var lotPrinted = 0
    lotTargets.forEachIndexed { index, lpNo ->
        onProgress("🖨 Lot etiketi gönderiliyor: ${index + 1}/${lotTargets.size} · $lpNo")
        val r = printLpCardLabels(context, lpNo, lot = true, total = 1, layoutCode = lotLayoutCode.orEmpty())
        if (r.startsWith("🟢")) lotPrinted++ else failures["$lpNo lot"] = r.removePrefix("HATA: ").removePrefix("🔴 ")
    }
    return ReceiptAutoLabelResult(lpNos, outcome.printed, failures, lotTargets.size, lotPrinted, outcome.printerCode)
}

/** Kayıttan önceki LP içerik görüntüsü; okunamazsa null (otomatik baskı yapılmaz). */
internal suspend fun fetchReceiptLpLines(context: Context, receiptNo: String): List<JSONObject>? {
    val page = BcApi.getAllPages(context, receiptLpLinesPath(receiptNo))
    return if (page.complete) page.rows else null
}

/**
 * Kitoko: kayıt onayında kayıt sonrası etiket seçenekleri — etiket yazıcısı, LP
 * etiket tasarımı ve "Lot etiketi de bas" (varsayılan kapalı).
 */
@Composable
internal fun ReceiptPostLabelOptions(
    skipPrinting: Boolean,
    lpLayout: LabelLayoutChoice,
    lotLayout: LabelLayoutChoice,
    lotLabelsToo: Boolean,
    onLotLabelsToo: (Boolean) -> Unit,
) {
    val context = LocalContext.current
    if (skipPrinting) {
        Text(
            "Yazdırmadan kaydet seçili: etiket basılmaz. Kayıttan sonra Etiketler ekranından basabilirsiniz.",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        return
    }
    val labelPrinter = remember { mtePrinterCode(getDefaultPrinter(context, PRINTER_USAGE_LABEL), getDefaultPrinter(context, PRINTER_USAGE_DOCUMENT)) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("Kayıttan sonra her LP'ye 1 LP etiketi basılır", fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        Text(
            if (labelPrinter.isNotBlank()) "Etiket yazıcısı: $labelPrinter" else "Etiket yazıcısı seçilmedi; Yazıcılar ekranından seçin.",
            fontSize = 12.sp,
            color = if (labelPrinter.isNotBlank()) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error,
        )
        LabelLayoutSelector(lpLayout)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(checked = lotLabelsToo, onCheckedChange = onLotLabelsToo)
            Text("Lot etiketi de bas", fontSize = 13.sp)
        }
        if (lotLabelsToo) LabelLayoutSelector(lotLayout)
    }
}
