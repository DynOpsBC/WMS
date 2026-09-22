package com.dynops.bcwms.feature

import android.content.Context
import com.dynops.bcwms.BcApi
import org.json.JSONArray
import org.json.JSONObject

/** Reproduce BC's line/LP allocation order, including already staged rows
 * that can use the selected stock. Registration checks the entire document.
 * Otherwise two separate confirmations could both instruct the operator to
 * take the last available units from the same pallet.
 */
internal suspend fun loadDocumentPalletPlans(
    context: Context,
    pickNo: String,
    requested: List<Pair<JSONObject, Double>>? = null,
): List<PalletPickPlan> {
    val safeNo = pickNo.replace("'", "''")
    val page = BcApi.getAllPages(context, "pickLines?\$filter=no eq '$safeNo'&\$top=100")
    check(page.complete) { "Toplama satırlarının tamamı alınamadı. Belgeyi yenileyin." }
    return buildDocumentPalletPlans(page.rows, requested) { lineNo ->
        val response = BcApi.pickLineSources(context, pickNo, lineNo)
        check(response.ok) { "Satır $lineNo paletleri doğrulanamadı: ${BcApi.errorMessage(response.body)}" }
        BcApi.scalarValue(response.body)
    }
}

internal suspend fun buildDocumentPalletPlans(
    documentRows: List<JSONObject>,
    requested: List<Pair<JSONObject, Double>>? = null,
    loadSources: suspend (Int) -> String,
): List<PalletPickPlan> {
    val overrides = requested?.associate { it.first.optInt("lineNo") to it.second }.orEmpty()
    val rows = documentRows.filter { it.optString("actionType").equals("Take", true) }.sortedBy { it.optInt("lineNo") }
    check(overrides.keys.all { no -> rows.any { it.optInt("lineNo") == no } }) { "Toplama satırı değişmiş. Belgeyi yenileyin." }
    requested?.forEach { (expected, _) ->
        val actual = rows.first { it.optInt("lineNo") == expected.optInt("lineNo") }
        check(listOf("itemNo", "variantCode", "locationCode", "binCode", "lotNo", "serialNo", "unitOfMeasureCode").all {
            actual.optString(it).equals(expected.optString(it), true)
        }) { "Toplama satırının ürün/lot/raf bilgisi değişmiş. Belgeyi yenileyin." }
    }
    check(requested == null || requested.map { it.first.optString("unitOfMeasureCode") }.distinct().size <= 1) {
        "Farklı ölçü birimlerini ayrı satırlarda toplayın."
    }
    val lastRequested = overrides.keys.maxOrNull() ?: Int.MAX_VALUE
    val used = mutableMapOf<String, Double>()
    val result = mutableListOf<PalletPickPlan>()
    for (row in rows) {
        val lineNo = row.optInt("lineNo")
        if (lineNo > lastRequested) break
        // A prefilled quantity on an unrelated earlier item is not a dependency
        // of this sheet. Keep earlier overlapping rows to reserve shared LP
        // capacity, but never let YM.00273's missing LP block AB.02029's scanner.
        if (requested != null && lineNo !in overrides &&
            requested.none { (selected, _) -> palletStockMayOverlap(row, selected) }
        ) continue
        val amount = overrides[lineNo] ?: row.optDouble("qtyToHandle", 0.0)
        if (amount <= 0) continue
        val plan = buildPalletPickPlan(row, amount, loadSources(lineNo), used)
        if (requested == null || lineNo in overrides) result += plan
    }
    return result
}

private fun palletStockMayOverlap(first: JSONObject, second: JSONObject): Boolean {
    fun text(row: JSONObject, field: String) = row.optString(field).takeUnless { it == "null" }.orEmpty().trim()
    if (listOf("itemNo", "variantCode", "locationCode", "binCode").any {
        !text(first, it).equals(text(second, it), ignoreCase = true)
    }) return false
    // Blank tracking is resolved from LP candidates and may overlap an explicit
    // lot/serial. UOM is deliberately excluded: allocation is in base quantities.
    return listOf("lotNo", "serialNo").all {
        val a = text(first, it)
        val b = text(second, it)
        a.isBlank() || b.isBlank() || a.equals(b, ignoreCase = true)
    }
}

internal fun palletPlanJson(plan: PalletPickPlan): String = JSONObject().apply {
    put("lineNo", plan.lineNo); put("quantity", plan.quantity); put("lotNo", plan.lotNo); put("identity", plan.identity)
    put("steps", JSONArray().apply {
        plan.steps.forEach { step -> put(JSONObject().apply {
            put("lpNo", step.lpNo); put("binCode", step.binCode); put("lotNo", step.lotNo)
            put("serialNo", step.serialNo); put("quantity", step.quantity); put("baseQuantity", step.baseQuantity)
        }) }
    })
}.toString()

internal fun palletPlanFromJson(json: String): PalletPickPlan? = runCatching {
    val data = JSONObject(json)
    val array = data.getJSONArray("steps")
    PalletPickPlan(data.getInt("lineNo"), data.getDouble("quantity"), data.getString("lotNo"),
        (0 until array.length()).map { index ->
            val step = array.getJSONObject(index)
            PalletPickStep(step.getString("lpNo"), step.getString("binCode"), step.getString("lotNo"),
                step.getString("serialNo"), step.getDouble("quantity"), step.getDouble("baseQuantity"))
        }, data.getString("identity"))
}.getOrNull()

internal fun firstUnverifiedPalletLine(
    plans: List<PalletPickPlan>, readProof: (Int) -> PalletPickPlan?,
): Int? = plans.firstOrNull { plan ->
    val proof = readProof(plan.lineNo)
    proof == null || !samePalletPickPlan(plan, proof)
}?.lineNo

internal object PalletPickVerification {
    private fun prefs(context: Context) = context.getSharedPreferences("pallet_pick_verification_v1", Context.MODE_PRIVATE)
    private fun key(context: Context, pickNo: String, lineNo: Int): String = JSONArray(listOf(
        BcApi.getTenant(context), BcApi.getEnvironment(context), BcApi.getCompanyId(context), pickNo, lineNo,
    )).toString()

    fun save(context: Context, pickNo: String, plan: PalletPickPlan) {
        prefs(context).edit().putString(key(context, pickNo, plan.lineNo), palletPlanJson(plan)).apply()
    }

    fun clear(context: Context, pickNo: String, lineNo: Int) {
        prefs(context).edit().remove(key(context, pickNo, lineNo)).apply()
    }

    suspend fun firstUnverifiedLine(context: Context, pickNo: String): Int? =
        firstUnverifiedPalletLine(loadDocumentPalletPlans(context, pickNo)) { lineNo ->
            palletPlanFromJson(prefs(context).getString(key(context, pickNo, lineNo), "").orEmpty())
        }

    suspend fun requireVerifiedDocument(context: Context, pickNo: String): List<PalletPickPlan> {
        val plans = loadDocumentPalletPlans(context, pickNo)
        check(plans.isNotEmpty()) { "Kaydedilecek doğrulanmış toplama satırı yok." }
        for (plan in plans) {
            val proof = palletPlanFromJson(prefs(context).getString(key(context, pickNo, plan.lineNo), "").orEmpty())
            check(proof != null && samePalletPickPlan(plan, proof)) {
                "${plan.lineNo} satırındaki paletler doğrulanmamış veya stok planı değişmiş. Satırı açıp paletleri yeniden okutun."
            }
        }
        return plans
    }
}

/** Wire contract for BC registerScannedFor. Base amounts use BC's five-decimal
 * precision so binary floating-point artifacts cannot reject a valid plan. */
internal fun scannedPalletRegistrationJson(plans: List<PalletPickPlan>): String {
    require(plans.isNotEmpty() && plans.map { it.lineNo }.distinct().size == plans.size)
    return JSONArray().apply {
        plans.forEach { plan ->
            require(plan.quantity.isFinite() && plan.quantity > 0 && plan.steps.isNotEmpty())
            require(plan.steps.all { it.lpNo.isNotBlank() && it.baseQuantity.isFinite() && it.baseQuantity > 0 })
            val json = JSONObject(palletPlanJson(plan))
            val steps = json.getJSONArray("steps")
            plan.steps.forEachIndexed { index, step ->
                require(step.lpNo.isNotBlank() && step.baseQuantity.isFinite() && step.baseQuantity > 0)
                val base = java.math.BigDecimal.valueOf(step.baseQuantity).setScale(5, java.math.RoundingMode.HALF_UP)
                require(base.signum() > 0)
                steps.getJSONObject(index).put("baseQuantity", base)
            }
            put(json)
        }
    }.toString()
}
