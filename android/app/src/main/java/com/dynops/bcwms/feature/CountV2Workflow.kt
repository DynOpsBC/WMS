package com.dynops.bcwms.feature

import com.dynops.bcwms.scanner.BarcodeKind
import com.dynops.bcwms.scanner.ResolvedBarcode
import org.json.JSONObject
import kotlin.math.abs
import java.util.UUID

internal data class PendingCountV2Scan(
    val scanId: String,
    val binCode: String,
    val label: CountV2Label,
    val counterSlot: Int,
) {
    fun payload(): String = JSONObject().apply {
        put("scanId", scanId); put("binCode", binCode); put("counterSlot", counterSlot)
        put("itemNo", label.itemNo); put("variantCode", label.variantCode)
        put("unitOfMeasureCode", label.unitOfMeasureCode); put("lotNo", label.lotNo)
        put("serialNo", label.serialNo); put("qty", label.quantity)
    }.toString()

    fun storedJson(): String = JSONObject(payload()).put("raw", label.raw).toString()

    companion object {
        fun fromStoredJson(value: String): PendingCountV2Scan {
            val row = JSONObject(value)
            val id = row.getString("scanId").also { UUID.fromString(it) }
            val bin = row.getString("binCode").also { require(it.isNotBlank()) }
            val slot = row.getInt("counterSlot").also { require(it in 1..3) }
            val item = row.getString("itemNo").also { require(it.isNotBlank()) }
            val qty = row.getDouble("qty").also { require(it.isFinite() && it > 0) }
            return PendingCountV2Scan(id, bin, CountV2Label(item, row.getString("variantCode"),
                row.getString("unitOfMeasureCode"), row.getString("lotNo"), row.getString("serialNo"),
                qty, row.getString("raw")), slot)
        }
    }
}

/** Sunucuya tek, atomik Sayım V2 okutması olarak gönderilen kesin etiket bilgisi. */
internal data class CountV2Label(
    val itemNo: String,
    val variantCode: String,
    val unitOfMeasureCode: String,
    val lotNo: String,
    val serialNo: String,
    val quantity: Double,
    val raw: String,
)

internal sealed interface CountV2LabelResult {
    data class Valid(val label: CountV2Label) : CountV2LabelResult
    data class Invalid(val message: String) : CountV2LabelResult
}

/**
 * V2'de sistem miktarına veya elle girişe sessizce düşülmez. Yalnız ürün ve
 * pozitif miktarı açıkça taşıyan QR sayım satırı oluşturabilir.
 */
internal fun validateCountV2Label(resolved: ResolvedBarcode): CountV2LabelResult {
    if (resolved.kind != BarcodeKind.Item)
        return CountV2LabelResult.Invalid("Sayım V2 yalnız ürün etiketi kabul eder.")

    val itemNo = resolved.itemNo?.trim().orEmpty().ifBlank { resolved.value.trim() }
    if (itemNo.isBlank())
        return CountV2LabelResult.Invalid("QR içinde madde kodu bulunamadı.")

    val quantity = resolved.quantity
    if (quantity == null)
        return CountV2LabelResult.Invalid("QR içinde miktar yok. V2 manuel miktar istemez; ürün + lot + miktar içeren etiketi okutun.")
    if (!quantity.isFinite() || quantity <= 0.0)
        return CountV2LabelResult.Invalid("QR miktarı sıfırdan büyük olmalıdır.")

    return CountV2LabelResult.Valid(
        CountV2Label(
            itemNo = itemNo,
            variantCode = resolved.variantCode?.trim().orEmpty(),
            unitOfMeasureCode = resolved.unitOfMeasureCode?.trim().orEmpty(),
            lotNo = resolved.lotNo?.trim().orEmpty(),
            serialNo = resolved.serialNo?.trim().orEmpty(),
            quantity = quantity,
            raw = resolved.raw,
        )
    )
}

/** Miktarsız ürün okutması: madde no (+ varsa lot/seri) belli, miktar operatörden sorulacak. */
internal data class CountV2ManualCandidate(
    val itemNo: String,
    val lotNo: String,
    val serialNo: String,
    val raw: String,
)

/**
 * Sahadaki ürün etiketlerinin çoğu miktar taşımaz (yalnız madde no ya da GS1
 * GTIN+lot). V2 bu durumda okutmayı reddetmek yerine miktarı elle sorar; QR'da
 * miktar varsa (etiketli koli) dokunmadan otomatik satır oluşur. Raf, LP, şablon
 * ve belge barkodları ürün sayılmaz → null.
 */
internal fun countV2ManualCandidate(resolved: ResolvedBarcode): CountV2ManualCandidate? {
    if (resolved.quantity != null) return null
    val itemNo = when (resolved.kind) {
        BarcodeKind.Item -> resolved.itemNo?.trim().orEmpty().ifBlank { resolved.value.trim() }
        BarcodeKind.Unknown -> resolved.value.trim()
        BarcodeKind.Lot, BarcodeKind.Serial -> resolved.itemNo?.trim().orEmpty()
        else -> return null
    }
    if (itemNo.isBlank()) return null
    return CountV2ManualCandidate(
        itemNo = itemNo,
        lotNo = resolved.lotNo?.trim().orEmpty(),
        serialNo = resolved.serialNo?.trim().orEmpty(),
        raw = resolved.raw,
    )
}

/** Donanım/kamera aynı decode olayını art arda yayarsa miktarın iki kez eklenmesini önler. */
internal fun isRapidCountV2Duplicate(
    previousRaw: String,
    previousAtMillis: Long,
    raw: String,
    nowMillis: Long,
    debounceMillis: Long = 1_500L,
): Boolean =
    previousRaw.isNotBlank() &&
        previousRaw == raw &&
        nowMillis >= previousAtMillis &&
        nowMillis - previousAtMillis < debounceMillis

internal fun classicCountSheetV2Message(lineCount: Int): String =
    "Bu belge klasik sayım için hazırlanmış ve $lineCount hazır satır içeriyor. " +
        "Mevcut satırlar silinmedi. Bu belgeyle ana menüdeki Sayım ekranından devam edin " +
        "veya Sayfa Listesi'ne dönüp Yeni V2 Sayımı Oluştur'a basın."

internal data class CountV2BinVariance(val bin: String, val difference: Double, val complete: Boolean)

internal data class CountV2VarianceGroup(
    val item: String,
    val variant: String,
    val lot: String,
    val serial: String,
    val uom: String,
    val bins: List<CountV2BinVariance>,
) {
    val complete: Boolean get() = bins.all { it.complete }
    val net: Double get() = bins.sumOf { it.difference }
    val possibleBinMismatch: Boolean get() = complete && abs(net) < 0.00001 &&
        bins.any { it.difference > 0.00001 } && bins.any { it.difference < -0.00001 }
}

/** Never net different lots, variants, serials or units; uncounted is not zero. */
internal fun countV2VarianceGroups(lines: List<JSONObject>, slot: Int, useWinningVariance: Boolean): List<CountV2VarianceGroup> =
    lines.groupBy { line -> listOf("itemNo", "variantCode", "lotNo", "serialNo", "unitOfMeasureCode").map { line.optString(it) } }
        .map { (key, itemLines) ->
            CountV2VarianceGroup(key[0], key[1], key[2], key[3], key[4],
                itemLines.groupBy { it.optString("binCode") }.toSortedMap().map { (bin, binLines) ->
                    CountV2BinVariance(bin, binLines.sumOf {
                        if (useWinningVariance) it.optDouble("variance", Double.NaN)
                        else it.optDouble("countedQty$slot", Double.NaN) - it.optDouble("systemQty", Double.NaN)
                    }, binLines.all {
                        it.optBoolean("counted$slot", false) &&
                            it.optDouble("countedQty$slot", Double.NaN).isFinite() &&
                            it.optDouble("systemQty", Double.NaN).isFinite() &&
                            (!useWinningVariance || (!it.optBoolean("recountRequired", false) && it.optDouble("variance", Double.NaN).isFinite()))
                    })
                })
        }.filter { group -> !group.complete || group.bins.any { abs(it.difference) > 0.00001 } }
        .sortedWith(compareBy({ it.item }, { it.variant }, { it.lot }, { it.serial }, { it.uom }))

internal fun countV2VarianceReviewText(groups: List<CountV2VarianceGroup>): String =
    groups.joinToString("\n\n") { group ->
        val identity = listOf(group.item, group.variant, group.lot.takeIf { it.isNotBlank() }?.let { "lot $it" }.orEmpty(),
            group.serial, group.uom).filter { it.isNotBlank() }.joinToString(" · ")
        fun qty(value: Double): String = if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()
        val bins = group.bins.joinToString(" · ") {
            "${it.bin}: " + if (it.complete) (if (it.difference > 0) "+" else "") + qty(it.difference) else "sayım bekliyor"
        }
        val result = when {
            !group.complete -> "İlgili rafların sayımı tamamlanmalı"
            group.possibleBinMismatch -> "Olası raf farkı · toplam stok farkı 0"
            else -> "Toplam stok farkı ${qty(group.net)}"
        }
        "$identity\n$bins\n$result"
    }.ifBlank { "Sayılmış satırlarda stok farkı yok" }
