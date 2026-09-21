package com.dynops.bcwms.feature

import com.dynops.bcwms.ui.rawValue
import kotlinx.coroutines.CancellationException

internal data class InquiryLabelProduct(val itemNo: String, val description: String, val copies: String)
internal data class InquiryLabelJob(val itemNo: String, val copies: Int)
internal data class InquiryLabelBatchResult(
    val sentCopies: Map<String, Int>,
    val error: String? = null,
    val failedItemNo: String? = null,
) {
    val complete: Boolean get() = error == null
    val totalSent: Int get() = sentCopies.values.sum()
}

/** A product found by both its barcode and an LP must appear only once. */
internal fun inquiryLabelProducts(entries: List<InquiryItemEntry>): List<InquiryLabelProduct> =
    entries.mapNotNull { entry ->
        val item = entry.item ?: return@mapNotNull null
        val no = rawValue(item, "no", "number").trim().takeIf(String::isNotBlank) ?: return@mapNotNull null
        InquiryLabelProduct(no, rawValue(item, "description", "displayName"), entry.labelCopies)
    }.distinctBy { it.itemNo.uppercase(java.util.Locale.ROOT) }

/** Stop on the first error, retain confirmed batches, and never retry a print request automatically. */
internal suspend fun sendInquiryLabelBatch(
    jobs: List<InquiryLabelJob>,
    send: suspend (itemNo: String, copies: Int) -> Result<Unit>,
    onProgress: (itemNo: String, confirmedCopies: Int, totalCopies: Int) -> Unit = { _, _, _ -> },
): InquiryLabelBatchResult {
    require(jobs.isNotEmpty()) { "En az bir ürün seçin." }
    require(jobs.all { it.itemNo.isNotBlank() && it.copies in 1..LABEL_COPIES_MAX }) { "Geçersiz ürün veya etiket adedi." }
    require(jobs.distinctBy { it.itemNo.uppercase(java.util.Locale.ROOT) }.size == jobs.size) { "Aynı ürün birden fazla kez seçilemez." }
    val sent = linkedMapOf<String, Int>()
    val total = jobs.sumOf { it.copies }
    for (job in jobs) {
        for (copies in labelCopyBatches(job.copies)) {
            onProgress(job.itemNo, sent.values.sum(), total)
            val result = try {
                send(job.itemNo, copies)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                Result.failure(error)
            }
            val error = result.exceptionOrNull()
            if (error is CancellationException) throw error
            if (error != null) return InquiryLabelBatchResult(sent.toMap(), error.message ?: "Gönderim başarısız.", job.itemNo)
            sent[job.itemNo] = (sent[job.itemNo] ?: 0) + copies
        }
    }
    return InquiryLabelBatchResult(sent.toMap())
}
