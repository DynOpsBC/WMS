package com.dynops.bcwms.feature

/**
 * Eski BC uzantisinda bound action gercekten yoksa PATCH uyumluluk yoluna dus.
 * Her 400 yanitinda fallback yapmak; yetki, kilit veya is kurali hatasini farkli
 * bir yazma yoluyla asmayi deneyerek asil hatayi gizliyordu.
 */
internal fun shouldFallbackReceiptExcludeAction(httpCode: Int, responseBody: String): Boolean {
    if (httpCode == 404 || httpCode == 405 || httpCode == 501) return true
    if (httpCode != 400) return false
    val body = responseBody.lowercase()
    return listOf(
        "could not find",
        "not found",
        "no http resource",
        "unknown action",
        "does not exist",
    ).any(body::contains)
}

internal fun receivingPreflightFailureStatus(resetCount: Int): String =
    receivingPreflightFailureStatus(resetCount, null, null)

/**
 * Post öncesi "okutulmamış satırları sıfırla" adımı bir satırda takıldığında
 * gösterilecek metin. Eskiden yalnız genel bir cümle vardı ve operatör hangi
 * satırın neden engellediğini göremiyordu; BC'nin gerçek gerekçesi eklendi.
 */
internal fun receivingPreflightFailureStatus(
    resetCount: Int,
    blockedLineNo: Int?,
    reason: String?,
): String {
    val head = if (resetCount > 0) {
        "UYARI: $resetCount satır sıfırlandı, kalan satırlar işlenemedi."
    } else {
        "HATA: Okutulmayan satırlar sıfırlanamadı."
    }
    val where = blockedLineNo?.let { " Takılan satır: $it." }.orEmpty()
    val why = reason?.takeIf { it.isNotBlank() }?.let { " Sebep: ${it.removePrefix("HATA: ")}" }.orEmpty()
    return "$head$where$why Belge yenilendi; mal kabul kaydedilmedi."
}
