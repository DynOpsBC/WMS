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

/**
 * Mal kabulü ve LP içeriğini tek transaction'da kaydeden sunucu aksiyonu eski
 * BC paketlerinde yoktur. Bu durumda genel REF kodu yerine kurulması gereken
 * paketi açıkça söyle; eski iki-adımlı akışa dönmek stoklu taslak LP bırakır.
 */
internal fun missingReceiptPostBackendStatus(httpCode: Int, responseBody: String): String? {
    val body = responseBody.lowercase()
    val missingHttpAction = httpCode == 404 || httpCode == 405 || httpCode == 501 ||
        (httpCode == 400 && listOf(
            "could not find",
            "not found",
            "no http resource",
            "unknown action",
            "does not exist",
        ).any(body::contains))
    if (!missingHttpAction) return null
    return "HATA: Mal kabul kaydı için BCWMS BC paketi 1.14.1.20 kurulmalı; belge ve LP kaydedilmedi."
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
