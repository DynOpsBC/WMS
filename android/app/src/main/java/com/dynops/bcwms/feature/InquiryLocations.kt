package com.dynops.bcwms.feature

import org.json.JSONObject

/**
 * DKC (20 Kas 2026): Ürün Sorgu'da "ürün nerede" — lokasyon/raf bazında stok ve
 * her lotun hangi lokasyonda, hangi rafta (LP üzerinden) durduğu.
 *
 * DKC'de lot yalnız kalem hareketinde tutulur (depo izleme yok); BC raf içeriği
 * lot ayrımı bilmez. Lotun rafı bu yüzden LP'den okunur; LP'de olmayan miktar için
 * ürün o lokasyonda tek raftaysa o raf, değilse ürünün bulunduğu raflar gösterilir.
 */
internal data class InquiryPlace(
    val locationCode: String,
    val binCode: String,
    val quantity: Double,
    val lpNos: List<String>,
)

internal data class InquiryLotLp(val lpNo: String, val binCode: String, val quantity: Double)

internal data class InquiryLotLocation(
    val locationCode: String,
    val quantity: Double,
    val lps: List<InquiryLotLp>,
    /** LP'de olmayan miktar. */
    val looseQuantity: Double,
    /** LP dışı miktarın olabileceği raflar (ürünün bu lokasyonda bulunduğu raflar). */
    val looseBins: List<String>,
)

internal data class InquiryLpHeader(val lpNo: String, val locationCode: String, val binCode: String)

private val ACTIVE_LP_STATUSES = setOf("open", "built", "assigned")

private fun clean(value: String?): String = value?.trim()?.takeUnless { it.isEmpty() || it == "null" }.orEmpty()

/** Raf içeriğinden miktarı olan satırlar: lokasyon → raf sırasıyla. */
internal fun inquiryBinPlaces(binContents: List<JSONObject>): List<InquiryPlace> =
    binContents.mapNotNull { row ->
        val qty = row.optDouble("quantity", 0.0)
        if (!qty.isFinite() || qty <= PICK_QTY_EPSILON) return@mapNotNull null
        InquiryPlace(
            locationCode = clean(row.optString("locationCode")),
            binCode = clean(row.optString("binCode")),
            quantity = qty,
            lpNos = clean(row.optString("activeLpNos")).split(',').map(String::trim).filter(String::isNotEmpty),
        )
    }.sortedWith(compareBy({ it.locationCode }, { it.binCode }))

/** Aktif (açık/hazır/atanmış) LP başlıkları. */
internal fun activeLpHeaders(lps: List<JSONObject>): Map<String, InquiryLpHeader> =
    lps.filter { BcEnum.decodeOData(it.optString("status")).lowercase() in ACTIVE_LP_STATUSES }
        .mapNotNull { row ->
            val no = clean(row.optString("no"))
            if (no.isEmpty()) null else no.uppercase() to InquiryLpHeader(no, clean(row.optString("locationCode")), clean(row.optString("binCode")))
        }.toMap()

/** LP filtresi için en çok [chunk] numaralık OData parçaları. */
internal fun lpHeaderFilters(lpNos: Collection<String>, chunk: Int = 15): List<String> =
    lpNos.map(::clean).filter(String::isNotEmpty).distinct().chunked(chunk).map { part ->
        part.joinToString(" or ") { "no eq '${it.replace("'", "''")}'" }
    }

/**
 * Bir lotun lokasyonları: miktar açık kalem hareketlerinden (lokasyon bazında),
 * raf ise o lotu taşıyan aktif LP'lerden gelir.
 */
internal fun inquiryLotLocations(
    lotNo: String,
    openLedger: List<JSONObject>,
    lpLines: List<JSONObject>,
    lpHeaders: Map<String, InquiryLpHeader>,
    places: List<InquiryPlace>,
): List<InquiryLotLocation> {
    val byLocation = linkedMapOf<String, Double>()
    openLedger.forEach { row ->
        if (!clean(row.optString("lotNo")).equals(lotNo, ignoreCase = true)) return@forEach
        val remaining = row.optDouble("remainingQuantity", 0.0)
        if (!remaining.isFinite() || remaining <= 0.0) return@forEach
        val loc = clean(row.optString("locationCode"))
        byLocation[loc] = (byLocation[loc] ?: 0.0) + remaining
    }
    val lotLps = lpLines.filter { clean(it.optString("lotNo")).equals(lotNo, ignoreCase = true) }
        .mapNotNull { line ->
            val header = lpHeaders[clean(line.optString("lpNo")).uppercase()] ?: return@mapNotNull null
            val qty = line.optDouble("quantity", 0.0)
            if (!qty.isFinite() || qty <= 0.0) null else header to qty
        }
        .groupBy({ it.first }, { it.second })
        .map { (header, qtys) -> header to qtys.sum() }
    return byLocation.map { (loc, qty) ->
        val lps = lotLps.filter { it.first.locationCode.equals(loc, ignoreCase = true) }
            .map { (h, q) -> InquiryLotLp(h.lpNo, h.binCode, q) }
            .sortedWith(compareBy({ it.binCode }, { it.lpNo }))
        val loose = (qty - lps.sumOf { it.quantity }).let { if (it > PICK_QTY_EPSILON) it else 0.0 }
        val looseBins = if (loose > 0.0)
            places.filter { it.locationCode.equals(loc, ignoreCase = true) && it.binCode.isNotEmpty() }
                .map { it.binCode }.distinct()
        else emptyList()
        InquiryLotLocation(loc, qty, lps, loose, looseBins)
    }.sortedBy { it.locationCode }
}

/** "DKC WMS · Raf A-01" biçiminde yer metni. */
internal fun inquiryPlaceText(locationCode: String, binCode: String): String =
    listOf(locationCode, binCode.takeIf(String::isNotBlank)?.let { "Raf $it" }.orEmpty())
        .filter(String::isNotBlank).joinToString(" · ").ifBlank { "Lokasyonsuz" }

/** LP dışı miktarın raf metni: tek raf kesin, birden çok raf olasılık. */
internal fun looseBinText(bins: List<String>): String = when {
    bins.isEmpty() -> "raf bilgisi yok"
    bins.size == 1 -> "Raf ${bins.first()}"
    else -> "raflar: ${bins.joinToString(", ")}"
}

/** Açık kalem hareketlerinin lokasyon toplamı (miktarı olanlar, lokasyon sırasıyla). */
internal fun inquiryLocationStock(openLedger: List<JSONObject>): List<Pair<String, Double>> {
    val totals = sortedMapOf<String, Double>()
    openLedger.forEach { row ->
        val remaining = row.optDouble("remainingQuantity", 0.0)
        if (!remaining.isFinite() || remaining <= 0.0) return@forEach
        val loc = clean(row.optString("locationCode"))
        totals[loc] = (totals[loc] ?: 0.0) + remaining
    }
    return totals.map { it.key to it.value }
}
