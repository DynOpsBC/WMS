package com.dynops.bcwms.feature

import org.json.JSONObject
import java.time.LocalDate
import java.util.UUID

internal fun pickSourceCaption(line: JSONObject): String {
    val no = line.optString("sourceNo").trim()
    if (no.isBlank()) return ""
    val title = when {
        line.optInt("sourceType") == 37 && line.optInt("sourceSubtype") == 1 -> "Satış siparişi"
        line.optInt("sourceType") in setOf(5406, 5407) && line.optInt("sourceSubtype") == 3 -> "Serbest bırakılmış üretim emri"
        else -> "Kaynak belge"
    }
    return "$title: $no"
}

internal fun pickSourceSummary(header: JSONObject): String =
    header.optString("sourceSummary").trim().ifBlank { pickSourceCaption(header) }

/**
 * Liste kartı için kısa kaynak: yalnız belge numaraları ("UR000382" ya da
 * "UR000382 · SS000044"). Uzun başlık ("Serbest bırakılmış üretim emri: …")
 * belge ekranında kalır; listede yer kaplıyordu.
 */
internal fun pickSourceNumbers(header: JSONObject): String {
    val fromSummary = header.optString("sourceSummary").split('·')
        .map { it.substringAfterLast(':').trim() }
        .filter { it.isNotBlank() }
    val numbers = fromSummary.ifEmpty { listOf(header.optString("sourceNo").trim()).filter { it.isNotBlank() && it != "null" } }
    return numbers.distinct().joinToString(" · ")
}

/**
 * Toplama belgesi başına ürünler (liste kartında gösterilir): yalnız Take
 * satırları, ürün başına bir kez, "ÜRÜN NO — açıklama".
 */
internal fun pickItemsByDocument(lines: List<JSONObject>): Map<String, List<String>> =
    pickTakeLines(lines)
        .filter { it.optString("no").isNotBlank() && it.optString("itemNo").isNotBlank() }
        .groupBy { it.optString("no") }
        .mapValues { (_, rows) ->
            rows.distinctBy { it.optString("itemNo") }.map { row ->
                val item = row.optString("itemNo").trim()
                val description = row.optString("description").trim().takeIf { it.isNotBlank() && it != "null" && !it.equals(item, ignoreCase = true) }
                listOfNotNull(item, description).joinToString(" — ")
            }
        }

internal fun productionReportQuantityError(quantity: Double?, remaining: Double): String? = when {
    quantity == null || !quantity.isFinite() || quantity <= 0.0 -> "Bildirilen miktar sıfırdan büyük olmalı."
    !remaining.isFinite() || quantity > remaining -> "Bildirilen miktar kalan miktarı aşıyor. Emir bilgilerini yenileyin."
    else -> null
}

internal fun productionIsoDate(text: String, optional: Boolean = false): String? =
    if (text.isBlank() && optional) "0001-01-01"
    else runCatching { LocalDate.parse(text.trim()).takeIf { it.year in 1900..9999 }?.toString() }.getOrNull()

/** Saved before any mutating call, scoped by company and order line on the device. */
internal data class ProductionOutputDraft(
    val requestId: String,
    val orderNo: String,
    val lineNo: Int,
    val itemNo: String,
    val body: String,
    val phase: String = "prepare",
    val result: String = "",
) {
    fun toJson(): String = JSONObject().put("requestId", requestId).put("orderNo", orderNo)
        .put("lineNo", lineNo).put("itemNo", itemNo).put("body", body).put("phase", phase).put("result", result).toString()
}

internal fun productionOutputDraftFromJson(text: String): ProductionOutputDraft? = runCatching {
    val json = JSONObject(text)
    val draft = ProductionOutputDraft(json.getString("requestId"), json.getString("orderNo"), json.getInt("lineNo"),
        json.getString("itemNo"), json.getString("body"), json.getString("phase"), json.optString("result"))
    require(UUID.fromString(draft.requestId).toString() == draft.requestId)
    require(draft.orderNo.isNotBlank() && draft.lineNo > 0 && draft.itemNo.isNotBlank())
    require(draft.phase in setOf("prepare", "prepared", "posting", "posted", "cancel", "cancel_prepare"))
    val body = JSONObject(draft.body)
    require(body.getString("requestId") == draft.requestId)
    require(body.getDouble("quantity").let { it.isFinite() && it > 0.0 })
    require(productionIsoDate(body.getString("postingDate")) != null)
    require(body.getString("binCode").length <= 20)
    require(body.getString("expirationDate") == "0001-01-01" || productionIsoDate(body.getString("expirationDate")) != null)
    if (draft.phase in setOf("prepared", "posted")) {
        val result = validatedProductionOutputResult(draft, draft.result)
        require(result != null && !result.optBoolean("cancelled"))
        require(result.getBoolean("completed") == (draft.phase == "posted"))
    }
    draft
}.getOrNull()

internal fun productionPreparePath(draft: ProductionOutputDraft): String =
    "productionOrderLines(status='Released',prodOrderNo='${draft.orderNo.replace("'", "''")}',lineNo=${draft.lineNo})/Microsoft.NAV.prepareOutput"

internal fun productionRequestPath(draft: ProductionOutputDraft, action: String): String {
    require(action in setOf("postOutput", "cancelOutput"))
    return "productionOutputRequests(${UUID.fromString(draft.requestId)})/Microsoft.NAV.$action"
}

internal fun validatedProductionOutputResult(draft: ProductionOutputDraft, text: String): JSONObject? = runCatching {
    val result = JSONObject(text)
    require(UUID.fromString(result.getString("requestId").trim('{', '}')).toString() == draft.requestId)
    require(result.getString("prodOrderNo") == draft.orderNo && result.getInt("lineNo") == draft.lineNo)
    require(result.getString("itemNo") == draft.itemNo)
    require(result.getDouble("quantity") == JSONObject(draft.body).getDouble("quantity"))
    val completed = result.getBoolean("completed")
    val cancelled = result.getBoolean("cancelled")
    require(!(completed && cancelled))
    result.getString("lotNo")
    result.getString("postingDate")
    if (completed) {
        require(result.getInt("entryNo") > 0)
        require(result.getDouble("quantityBase").let { it.isFinite() && it > 0.0 })
        require(result.getString("baseUnitOfMeasure").isNotBlank())
        require(result.getString("documentNo").isNotBlank())
    }
    result
}.getOrNull()

internal fun productionDraftMatchesLine(draft: ProductionOutputDraft, line: JSONObject): Boolean =
    draft.orderNo == line.optString("prodOrderNo") && draft.lineNo == line.optInt("lineNo") && draft.itemNo == line.optString("itemNo")
