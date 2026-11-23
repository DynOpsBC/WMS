package com.dynops.bcwms.feature

import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.floor

/**
 * DKC (23 Kas 2026): üretim çıktısını LP'ye koyma. Çıktı deftere nakledildikten
 * sonra operatör çıkan miktarı yeni LP'lere (eşit bölerek) ya da mevcut bir LP'ye
 * (ör. başka bir paletteki LP) koyar. Satır BC'de addLineFromBin ile eklenir: lot
 * kalem hareketinden doğrulanır, LP başka raftaysa stok o rafa taşınır.
 */
internal fun splitOutputQuantity(total: Double, count: Int): List<Double> {
    if (count <= 0 || !total.isFinite() || total <= 0.0) return emptyList()
    if (count == 1) return listOf(total)
    val whole = abs(total - Math.round(total)) < 0.00001
    val per = if (whole) floor(total / count) else Math.round(total / count * 100000.0) / 100000.0
    if (per <= 0.0) return emptyList()
    val parts = MutableList(count - 1) { per }
    val last = Math.round((total - per * (count - 1)) * 100000.0) / 100000.0
    if (last <= 0.0) return emptyList()
    parts += last
    return parts
}

internal fun outputLpLineBody(itemNo: String, unit: String, quantity: Double, lotNo: String, sourceBin: String, userId: String): String =
    JSONObject()
        .put("itemNo", itemNo)
        .put("unitOfMeasure", unit)
        .put("quantity", quantity)
        .put("lotNo", lotNo)
        .put("serialNo", "")
        .put("sourceBinCode", sourceBin)
        .put("userId", userId)
        .toString()

/** Mevcut LP'ye eklenebilir mi: aktif olmalı ve çıktıyla aynı lokasyonda durmalı. */
internal fun outputTargetLpProblem(lp: JSONObject?, scanned: String, locationCode: String): String? {
    if (lp == null) return "$scanned LP'si bulunamadı. LP etiketini yeniden okutun."
    val status = BcEnum.decodeOData(lp.optString("status")).lowercase()
    if (status !in setOf("open", "built", "assigned")) return "${lp.optString("no")} LP'si kullanılmış/çözülmüş; içine ürün konamaz."
    val loc = lp.optString("locationCode").trim()
    if (locationCode.isNotBlank() && !loc.equals(locationCode.trim(), ignoreCase = true))
        return "${lp.optString("no")} LP'si $loc lokasyonunda; çıktı $locationCode lokasyonunda. Lokasyonlar arası eklenemez."
    return null
}
