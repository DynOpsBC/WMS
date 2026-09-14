package com.dynops.bcwms.feature

import android.content.Context
import com.dynops.bcwms.BcApi
import org.json.JSONArray
import org.json.JSONObject

/** Reproduce BC's line/LP allocation order, including already staged rows.
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
    val overrides = requested?.associate { it.first.optInt("lineNo") to it.second }.orEmpty()
    val rows = page.rows.filter { it.optString("actionType").equals("Take", true) }.sortedBy { it.optInt("lineNo") }
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
        val amount = overrides[lineNo] ?: row.optDouble("qtyToHandle", 0.0)
        if (amount <= 0) continue
        val response = BcApi.pickLineSources(context, pickNo, lineNo)
        check(response.ok) { "Satır $lineNo paletleri doğrulanamadı: ${BcApi.errorMessage(response.body)}" }
        val plan = buildPalletPickPlan(row, amount, BcApi.scalarValue(response.body), used)
        if (requested == null || lineNo in overrides) result += plan
    }
    return result
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

    suspend fun requireVerifiedDocument(context: Context, pickNo: String) {
        val plans = loadDocumentPalletPlans(context, pickNo)
        check(plans.isNotEmpty()) { "Kaydedilecek doğrulanmış toplama satırı yok." }
        for (plan in plans) {
            val proof = palletPlanFromJson(prefs(context).getString(key(context, pickNo, plan.lineNo), "").orEmpty())
            check(proof != null && samePalletPickPlan(plan, proof)) {
                "${plan.lineNo} satırındaki paletler doğrulanmamış veya stok planı değişmiş. Satırı açıp paletleri yeniden okutun."
            }
        }
    }
}
