package com.dynops.bcwms.feature

import org.json.JSONArray
import org.json.JSONObject
import java.text.NumberFormat
import java.util.Locale

/**
 * DKÇ (19 Kas 2026): Ürün Sorgu'da stoktaki lotlar listelenir; bir lota ya da
 * LP satırına dokununca o lotun ve LP'nin yazdığı ürün etiketi basılır.
 */
internal data class InquiryLotStock(val lotNo: String, val quantity: Double, val lpNos: List<String>)

/** Basılacak etiket: ürünün bir lotu, miktarı ve (varsa) LP'leri. */
internal data class InquiryLotLabel(val lotNo: String, val quantity: Double, val lpNos: List<String>)

/** Açık stok kayıtlarını (kalan > 0) lota göre toplar; LP'ler LP satırlarından gelir. */
internal fun inquiryLotStocks(openLedger: List<JSONObject>, lpLines: List<JSONObject>): List<InquiryLotStock> {
    val totals = linkedMapOf<String, Double>()
    openLedger.forEach { row ->
        val lot = row.optString("lotNo").trim()
        val remaining = row.optDouble("remainingQuantity", 0.0)
        if (lot.isNotEmpty() && lot != "null" && remaining.isFinite() && remaining > 0.0)
            totals[lot] = (totals[lot] ?: 0.0) + remaining
    }
    return totals.map { (lot, qty) ->
        InquiryLotStock(lot, qty, lpNosForLot(lpLines, lot))
    }.sortedBy { it.lotNo }
}

internal fun lpNosForLot(lpLines: List<JSONObject>, lotNo: String): List<String> =
    lpLines.filter { it.optString("lotNo").trim().equals(lotNo, ignoreCase = true) }
        .map { it.optString("lpNo").trim() }
        .filter { it.isNotEmpty() && it != "null" }
        .distinct().sorted()

/** Etiketin belge satırı: en çok 20 karakter (BC sınırı). */
internal fun lotLabelLpText(lpNos: List<String>): String = when {
    lpNos.isEmpty() -> ""
    lpNos.size == 1 -> "LP: ${lpNos.first()}"
    else -> "LP: ${lpNos.first()} +${lpNos.size - 1}"
}.take(20)

internal fun lotLabelQuantityText(quantity: Double, uom: String): String {
    val number = NumberFormat.getNumberInstance(Locale.forLanguageTag("tr-TR")).apply { maximumFractionDigits = 3 }.format(quantity)
    return "$number ${uom.trim()}".trim().take(30)
}

internal fun lotLabelRowsJson(itemNo: String, label: InquiryLotLabel, uom: String, dateText: String, copies: Int): String =
    JSONArray().put(
        JSONObject()
            .put("itemNo", itemNo)
            .put("lotNo", label.lotNo)
            .put("supplierLotNo", "")
            .put("quantityText", lotLabelQuantityText(label.quantity, uom))
            .put("receiptNo", lotLabelLpText(label.lpNos))
            .put("dateText", dateText)
            .put("copies", copies),
    ).toString()
