package com.dynops.bcwms.feature

import org.json.JSONObject

/**
 * DKÇ "Üretim Çıktısı" (18 Kas 2026): üretim emri başına ne üretilecekti, ne
 * kadarı çıktı; parçalı bildirim ProductionPostingSheet üzerinden BC'ye
 * kaydedilir. Etiket yalnız doğrulanmış çıktı hareketinden hazırlanır.
 */
internal const val PRODUCTION_OUTPUT_BC_VERSION = "1.14.2.32"

/** Bir üretim emrinden bir lotta çıkan net miktar (geri alma kayıtları düşülmüş). */
internal data class OutputLot(
    val lotNo: String,
    val quantity: Double,
    val unit: String,
    /** En son çıktı tarihi (yyyy-MM-dd). */
    val lastDate: String,
)

/**
 * Çıktı madde hareketlerini lota göre toplar. Geri alınan çıktı eksi miktarla
 * gelir; neti sıfır ya da eksi olan lot etiketlenecek bir şey bırakmadığı için
 * listelenmez. En son çıkan lot en üstte.
 */
internal fun productionOutputLots(entries: List<JSONObject>): List<OutputLot> =
    entries.groupBy { it.optString("lotNo").trim() }
        .map { (lot, rows) ->
            OutputLot(
                lotNo = lot,
                quantity = rows.sumOf { it.optDouble("quantity", 0.0) },
                unit = rows.firstNotNullOfOrNull { it.optString("baseUnitOfMeasure").trim().takeIf(String::isNotBlank) }.orEmpty(),
                lastDate = rows.filter { it.optDouble("quantity", 0.0) > 0.0 }.maxOfOrNull { it.optString("postingDate") }.orEmpty(),
            )
        }
        .filter { it.quantity > 0.000001 }
        .sortedWith(compareByDescending<OutputLot> { it.lastDate }.thenBy { it.lotNo })

/** Planlanana göre çıkan yüzde; plan yoksa 0, fazla üretimde 100'ü aşabilir. */
internal fun productionOutputPercent(planned: Double, finished: Double): Int =
    if (planned > 0.0 && finished > 0.0) (finished * 100.0 / planned).toInt() else 0

/** BC tarihini (yyyy-MM-dd) ekranda gg.aa.yyyy gösterir; tanınmayan değer olduğu gibi kalır. */
internal fun productionDateText(isoDate: String): String {
    val p = isoDate.trim().take(10).split('-')
    return if (p.size == 3 && p[0].length == 4 && p[0] != "0001") "${p[2]}.${p[1]}.${p[0]}" else ""
}

/** Üretim emri no / ürün no / açıklama içinde arama (büyük-küçük harf ayrımı yok). */
internal fun productionOutputMatches(line: JSONObject, query: String): Boolean {
    val q = query.trim()
    if (q.isEmpty()) return true
    return listOf("prodOrderNo", "itemNo", "description").any { line.optString(it).contains(q, ignoreCase = true) }
}

/** Tek ürün için etiket satırı: [copies] adet, her etikette [qtyPerLabel]. */
internal fun productionLabelRows(
    itemNo: String,
    description: String,
    lotNo: String,
    qtyPerLabel: Double,
    unit: String,
    copies: Int,
): List<ReceiptLabelRow> =
    if (itemNo.isBlank() || !qtyPerLabel.isFinite() || qtyPerLabel <= 0.0 || unit.isBlank() || copies <= 0) emptyList()
    else listOf(
        ReceiptLabelRow(
            itemNo = itemNo.trim(),
            description = description.trim(),
            lotNo = lotNo.trim(),
            supplierLotNo = "",
            quantity = qtyPerLabel,
            unit = unit.trim(),
            copies = copies.coerceAtMost(RECEIPT_LABEL_COPIES_MAX),
        ),
    )

/** Quantities in item ledger entries are in the base unit, never the order unit. */
internal fun productionOutputEntriesPath(orderNo: String, lineNo: Int, itemNo: String): String {
    fun escaped(value: String) = value.replace("'", "''")
    return "itemLedgerEntries?\$filter=orderNo eq '${escaped(orderNo)}' and orderLineNo eq $lineNo" +
        " and itemNo eq '${escaped(itemNo)}' and entryType eq 'Output'" +
        "&\$select=entryNo,postingDate,quantity,lotNo,baseUnitOfMeasure"
}

/** Bir bileşenin, emrin şu ana kadarki çıktısına göre sarfiyat durumu. */
internal data class ComponentConsumption(
    /** Çıkan miktar için gereken toplam (çıkan × birim başına). */
    val neededForOutput: Double,
    /** Bugüne kadar tüketilen. */
    val consumed: Double,
    /** Şimdi tüketilebilecek: gereken − tüketilen; emirde kalanı ve üretim gözüne çekileni aşmaz. */
    val consumableNow: Double,
)

/**
 * "Önce üret, sonra tüket": çıktı kaydedildikten sonra bileşenden ne kadar
 * tüketilebileceği. [qtyPer] bir birim ürün için bileşen miktarı,
 * [remainingOnOrder] emrin tamamı için hâlâ tüketilmemiş miktardır.
 */
internal fun componentConsumption(
    finished: Double,
    qtyPer: Double,
    consumed: Double,
    remainingOnOrder: Double,
    /** Üretim gözüne toplanmış (çekilmiş) stok; null = okunamadı, sınır uygulanmaz. */
    pickedInBin: Double? = null,
): ComponentConsumption {
    val needed = (finished.coerceAtLeast(0.0) * qtyPer.coerceAtLeast(0.0))
    val used = consumed.coerceAtLeast(0.0)
    // DKÇ: yalnız çekilen (üretim gözüne toplanan) kadar tüketilebilir.
    val now = minOf(needed - used, remainingOnOrder.coerceAtLeast(0.0), pickedInBin?.coerceAtLeast(0.0) ?: Double.MAX_VALUE).coerceAtLeast(0.0)
    // 5 hane: BC miktar hassasiyeti; 115.50000000000001 gibi kayan nokta artığı gösterilmesin.
    fun r(v: Double) = java.math.BigDecimal.valueOf(v).setScale(5, java.math.RoundingMode.HALF_UP).toDouble()
    return ComponentConsumption(r(needed), r(used), r(now))
}

/** Sarfiyat madde hareketlerinden ürün başına tüketilen miktar (hareketler eksi gelir, geri almalar artı). */
internal fun consumedByItem(entries: List<JSONObject>): Map<String, Double> =
    entries.groupBy { it.optString("itemNo").trim() }
        .filterKeys { it.isNotBlank() }
        .mapValues { (_, rows) -> (-rows.sumOf { it.optDouble("quantity", 0.0) }).coerceAtLeast(0.0) }

internal fun productionConsumptionEntriesPath(orderNo: String, lineNo: Int): String =
    "itemLedgerEntries?\$top=1000&\$filter=orderNo eq '${orderNo.replace("'", "''")}' and orderLineNo eq $lineNo" +
        " and entryType eq 'Consumption'&\$select=entryNo,itemNo,quantity"
