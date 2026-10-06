package com.dynops.bcwms

import com.dynops.bcwms.feature.canMutateAssignedDocument
import org.json.JSONObject

/** A successful POST alone does not prove that the signed-in operator owns the pick. */
internal suspend fun claimPickForOperator(
    operatorId: String,
    send: suspend (action: String, body: String) -> BcApi.ApiResult,
    readHeader: suspend () -> BcApi.ApiResult,
): BcApi.ApiResult {
    val userId = operatorId.trim()
    if (userId.isBlank()) return pickClaimError(401, "Depo kullanıcısı doğrulanamadı. Yeniden giriş yapın.")

    // Never fall back to assignToMe: that endpoint uses the shared BC account.
    val claimed = send("claim", JSONObject().put("userId", userId).toString())
    if (!claimed.ok) return claimed

    val refreshed = readHeader()
    if (!refreshed.ok) return pickClaimError(
        refreshed.httpCode,
        "Atama isteği gönderildi ancak belge sahibi doğrulanamadı. Belgeyi yenileyip kontrol edin.",
    )
    val owner = runCatching { JSONObject(refreshed.body).optString("assignedUserId") }.getOrDefault("")
    if (!canMutateAssignedDocument(owner, userId)) return pickClaimError(
        409,
        if (owner.isBlank()) "Belgenin size atandığı doğrulanamadı. Belgeyi yenileyip kontrol edin."
        else "Belge hâlâ $owner kullanıcısına atanmış. BC üzerinden atamayı kontrol edin.",
    )
    return refreshed
}

private fun pickClaimError(code: Int, message: String) = BcApi.ApiResult(
    false, code, JSONObject().put("error", JSONObject().put("message", message)).toString(),
)
