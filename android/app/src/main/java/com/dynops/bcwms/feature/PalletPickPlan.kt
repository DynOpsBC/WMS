package com.dynops.bcwms.feature

import org.json.JSONObject
import java.util.Locale
import kotlin.math.abs

internal fun requiresPalletWorkflow(flavor: String): Boolean = flavor.equals("bade", true)

internal data class PalletPickStep(
    val lpNo: String,
    val binCode: String,
    val lotNo: String,
    val serialNo: String,
    val quantity: Double,
    val baseQuantity: Double,
)

internal data class PalletPickPlan(
    val lineNo: Int,
    val quantity: Double,
    val lotNo: String,
    val steps: List<PalletPickStep>,
    val identity: String = "",
)

private const val PICK_TOLERANCE = 0.00001
private fun JSONObject.pickText(key: String): String = optString(key).takeUnless { it == "null" }.orEmpty().trim()

/** Server candidates are already checked for item, variant, location and assignment.
 * Check their identity against the requested line too; a failed/stale response must
 * never become permission to collect an arbitrary pallet. Quantities use the BC
 * outstanding/base ratio, rather than assuming every pick is in the base UOM.
 * [usedBase] prevents reusing the same stock across lines in a merged confirmation.
 */
internal fun buildPalletPickPlan(
    line: JSONObject,
    quantity: Double,
    response: String,
    usedBase: MutableMap<String, Double> = mutableMapOf(),
): PalletPickPlan {
    require(quantity.isFinite() && quantity > 0) { "Toplanacak miktar sıfırdan büyük olmalı." }
    val data = JSONObject(response)
    require(data.getInt("lineNo") == line.getInt("lineNo")) { "Palet listesi başka bir satıra ait. Yenileyin." }
    for (field in listOf("itemNo", "variantCode", "binCode", "locationCode")) {
        require(data.pickText(field).equals(line.pickText(field), true)) {
            "Palet listesi ile satırın ürün/raf bilgisi uyuşmuyor. Belgeyi yenileyin."
        }
    }
    require(data.pickText("activityNo").equals(line.pickText("no"), true)) { "Palet listesi başka bir belgeye ait." }
    val outstanding = line.getDouble("qtyOutstanding")
    val baseOutstanding = data.getDouble("outstandingBaseQty")
    require(outstanding.isFinite() && outstanding > 0 && baseOutstanding.isFinite() && baseOutstanding > 0) {
        "Satırın kalan miktarı veya ölçü birimi doğrulanamadı. Belgeyi yenileyin."
    }
    require(quantity <= outstanding + PICK_TOLERANCE) { "Miktar satırın kalanını aşamaz." }
    val factor = baseOutstanding / outstanding
    val expectedLot = line.pickText("lotNo")
    val expectedSerial = line.pickText("serialNo")
    require(data.pickText("lotNo").equals(expectedLot, true)) { "Satırın lotu değişmiş. Belgeyi yenileyin." }
    val array = data.getJSONArray("sources")
    val candidates = (0 until array.length()).map { array.getJSONObject(it) }.filter {
        it.pickText("binCode").equals(line.pickText("binCode"), true) &&
            (expectedLot.isBlank() || it.pickText("lotNo").equals(expectedLot, true)) &&
            (expectedSerial.isBlank() || it.pickText("serialNo").equals(expectedSerial, true))
    }
    require(candidates.isNotEmpty()) {
        "Uygun kaynak palet bulunamadı. Beklenen ürün: ${line.pickText("itemNo")} · " +
            "Depo: ${line.pickText("locationCode")} · Raf: ${line.pickText("binCode")} · " +
            "Lot: ${expectedLot.ifBlank { "Paletten doğrulanacak" }}. " +
            "LP içeriğindeki ürün, lot ve rafı bu satırla karşılaştırın. Farklı lotlu palet bu satırda toplanamaz; " +
            "o palet sevk edilecekse BC'deki toplama satırının lotunu ve stok uygunluğunu kontrol edin."
    }
    val lots = candidates.map { it.pickText("lotNo") }.distinctBy { it.uppercase(Locale.ROOT) }
    require(expectedLot.isNotBlank() || lots.size == 1) {
        "Birden fazla lot var. BC'de toplama satırını lotlara ayırıp belgeyi yenileyin."
    }
    val lot = expectedLot.ifBlank { lots.single() }
    // Older pickLines APIs omit serialNo; the server candidates are still
    // filtered by the actual BC serial. Only an unambiguous serial is safe.
    val serials = candidates.map { it.pickText("serialNo") }.distinctBy { it.uppercase(Locale.ROOT) }
    require(expectedSerial.isNotBlank() || serials.size == 1) { "Birden fazla seri var. BC'de satırları ayırıp yenileyin." }
    val serial = expectedSerial.ifBlank { serials.single() }
    require(!data.optBoolean("lotRequired") || lot.isNotBlank()) { "Paletin lot bilgisi eksik." }
    var remaining = quantity * factor
    val consumption = usedBase.toMutableMap()
    val steps = mutableListOf<PalletPickStep>()
    // Registration starts at the explicitly confirmed LP, then follows the
    // server list. Preserve that order when rechecking previously staged rows.
    val preferred = line.pickText("licensePlateNo")
    for (source in candidates.sortedBy { if (it.pickText("lpNo").equals(preferred, true)) 0 else 1 }) {
        if (remaining <= PICK_TOLERANCE) break
        val lp = source.pickText("lpNo")
        require(lp.isNotBlank()) { "Palet numarası eksik." }
        val available = source.getDouble("availableBaseQty")
        require(available.isFinite() && available >= 0) { "Palet miktarı geçersiz." }
        val key = listOf(lp, line.pickText("itemNo"), line.pickText("variantCode"), lot, serial)
            .joinToString("|").uppercase(Locale.ROOT)
        val used = consumption[key] ?: 0.0
        val take = minOf((available - used).coerceAtLeast(0.0), remaining)
        if (take > PICK_TOLERANCE) {
            steps += PalletPickStep(lp, source.pickText("binCode"), lot, serial, take / factor, take)
            consumption[key] = used + take
            remaining -= take
        }
    }
    require(remaining <= PICK_TOLERANCE) { "Uygun paletlerde yeterli stok yok. Miktarı veya BC palet stoklarını kontrol edin." }
    require(steps.isNotEmpty()) { "Toplanacak palet bulunamadı." }
    usedBase.putAll(consumption)
    val identity = listOf("no", "itemNo", "variantCode", "locationCode", "binCode", "serialNo", "unitOfMeasureCode")
        .joinToString("|") { line.pickText(it).uppercase(Locale.ROOT) }
    return PalletPickPlan(line.getInt("lineNo"), quantity, lot, steps, identity)
}

internal fun samePalletPickPlan(a: PalletPickPlan, b: PalletPickPlan): Boolean =
    a.identity == b.identity && a.lineNo == b.lineNo && a.lotNo == b.lotNo && abs(a.quantity - b.quantity) <= PICK_TOLERANCE &&
        a.steps.size == b.steps.size && a.steps.zip(b.steps).all { (x, y) ->
            x.lpNo == y.lpNo && x.binCode == y.binCode && x.lotNo == y.lotNo &&
                x.serialNo == y.serialNo && abs(x.baseQuantity - y.baseQuantity) <= PICK_TOLERANCE
        }

internal fun acceptsPalletStep(steps: List<PalletPickStep>, scannedCount: Int, value: String): Boolean =
    steps.getOrNull(scannedCount)?.lpNo?.equals(value.trim(), true) == true

internal fun palletScansComplete(steps: List<PalletPickStep>, scannedCount: Int): Boolean =
    steps.isNotEmpty() && scannedCount == steps.size

/** A shared pallet is scanned once for the total needed by this group. */
internal fun palletScanSteps(plans: List<PalletPickPlan>): List<PalletPickStep> {
    val combined = linkedMapOf<List<String>, PalletPickStep>()
    for (step in plans.flatMap { it.steps }) {
        val key = listOf(step.lpNo, step.binCode, step.lotNo, step.serialNo)
        val prior = combined[key]
        combined[key] = if (prior == null) step else prior.copy(
            quantity = prior.quantity + step.quantity,
            baseQuantity = prior.baseQuantity + step.baseQuantity,
        )
    }
    return combined.values.toList()
}
