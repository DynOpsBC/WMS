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

/** Read current BC ownership before asking to take over; cancellation never writes. */
internal suspend fun claimPickWithConfirmation(
    operatorId: String,
    readHeader: suspend () -> BcApi.ApiResult,
    confirmTakeover: suspend (String) -> Boolean,
    send: suspend (String, String) -> BcApi.ApiResult,
): BcApi.ApiResult {
    val me = operatorId.trim()
    if (me.isBlank()) return pickClaimError(401, "Depo kullanıcısı doğrulanamadı. Yeniden giriş yapın.")
    val current = readHeader()
    if (!current.ok) return current
    val header = runCatching { JSONObject(current.body) }.getOrNull()
    if (header == null || !header.has("assignedUserId") || header.isNull("assignedUserId"))
        return pickClaimError(409, "Belge sahibi doğrulanamadı. Belgeyi yenileyin.")
    val owner = header.optString("assignedUserId").trim()
    val takeover = owner.isNotBlank() && !owner.equals(me, ignoreCase = true)
    if (takeover && !confirmTakeover(owner))
        return pickClaimError(409, "Atama iptal edildi; belge sahibi değiştirilmedi.")
    if (takeover) {
        // The confirmation names this owner. Recheck before using the existing BC forceReassign action.
        val latest = readHeader()
        if (!latest.ok) return latest
        val latestOwner = runCatching { JSONObject(latest.body).getString("assignedUserId").trim() }.getOrNull()
        if (latestOwner != owner)
            return pickClaimError(409, "Belgenin sahibi değişti. Yenileyip tekrar Bana Ata'ya basın.")
    }
    return claimPickForOperator(me, { _, body ->
        if (takeover) send("forceReassign", JSONObject(body).put("reason", "Terminalde onaylı devralma: $owner -> $me").toString())
        else send("claim", body)
    }, readHeader)
}
