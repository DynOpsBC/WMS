package com.dynops.bcwms.feature

import com.dynops.bcwms.BcApi
import org.json.JSONObject

internal fun productionComponentKey(line: JSONObject): String =
    "status='${line.optString("status").ifBlank { BcEnum.ProdOrderStatus.RELEASED }.replace("'", "''")}'," +
        "prodOrderNo='${line.optString("prodOrderNo").replace("'", "''")}'," +
        "prodOrderLineNo=${line.optInt("prodOrderLineNo")},componentLineNo=${line.optInt("componentLineNo")}"

/** A pick must belong to both the selected production order and the terminal operator. */
internal suspend fun createProductionPickForOperator(
    prodOrderNo: String,
    operatorId: String,
    lpNo: String? = null,
    send: suspend (action: String, body: String) -> BcApi.ApiResult,
    readHeader: suspend (pickNo: String) -> BcApi.ApiResult,
): BcApi.ApiResult {
    val userId = operatorId.trim()
    if (userId.isBlank()) return productionPickError(401, "Depo kullanıcısı doğrulanamadı. Yeniden giriş yapın.")
    if (prodOrderNo.isBlank()) return productionPickError(400, "Üretim emri seçilmedi.")
    if (lpNo != null && lpNo.isBlank()) return productionPickError(400, "Hazır LP numarasını okutun.")
    val body = JSONObject().put("userId", userId)
    if (lpNo != null) body.put("lpNo", lpNo.trim())
    val result = send(if (lpNo == null) "createPickFor" else "createPickFromLpFor", body.toString())
    if (!result.ok) return result
    val pickNo = BcApi.scalarValue(result.body).trim()
    if (pickNo.isBlank()) return productionPickError(502, "Ambar çekme isteği gönderildi ancak belge numarası alınamadı. Toplama listesini kontrol edin.")
    val read = readHeader(pickNo)
    val header = if (read.ok) runCatching { JSONObject(read.body) }.getOrNull() else null
    if (header == null || header.optString("no") != pickNo ||
        !header.optString("sourceNo").equals(prodOrderNo, ignoreCase = true)
    ) return productionPickError(409, "$pickNo belgesinin üretim emri bağlantısı doğrulanamadı. Toplama listesinden kontrol edin.")
    val owner = header.optString("assignedUserId")
    if (!canMutateAssignedDocument(owner, userId)) return productionPickError(
        409, "$pickNo belgesinin terminal kullanıcınıza atandığı doğrulanamadı. ${documentOwnershipMessage(owner, userId)}",
    )
    return result
}

internal fun isProductionPick(lines: List<JSONObject>): Boolean {
    val take = lines.filter { BcEnum.decodeOData(it.optString("actionType")).equals("Take", true) }
    return take.isNotEmpty() && take.all { it.optInt("sourceType") == 5407 && it.optInt("sourceSubtype", -1) == 3 }
}

/** A ready production pallet is scoped by BC to its own quantities. */
internal fun initialPalletPickQuantity(lines: List<JSONObject>, outstanding: Double): Double {
    if (!isProductionPick(lines) || lines.none { it.optString("licensePlateNo").isNotBlank() }) return outstanding
    return lines.sumOf { it.optDouble("qtyToHandle", 0.0) }
        .takeIf { it.isFinite() && it >= 0.0 && it <= outstanding + 0.00001 } ?: 0.0
}

private fun productionPickError(code: Int, message: String) = BcApi.ApiResult(
    false, code, JSONObject().put("error", JSONObject().put("message", message)).toString(),
)
