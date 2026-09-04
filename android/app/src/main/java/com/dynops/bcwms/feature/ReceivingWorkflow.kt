package com.dynops.bcwms.feature

import com.dynops.bcwms.ui.operatorFacingApiError

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

/**
 * Mal kabul postunda genel REF mesaji tek basina desteklenebilir degil. Bilinen
 * hatalari normal operator cevirisinden gecir; bilinmeyen BC dogrulamasinda ise
 * teknik ekleri temizleyip yalniz eyleme donuk ilk mesaji goster.
 */
internal fun receiptPostFailureStatus(raw: String, httpCode: Int): String {
    val normal = operatorFacingApiError(raw, httpCode)
    if (!normal.contains("İşlem tamamlanamadı", ignoreCase = true) &&
        !normal.contains("Islem tamamlanamadi", ignoreCase = true)
    ) return normal

    val reason = receiptPostReason(raw) ?: return normal
    return "HATA: Mal kabul kaydedilmedi. Neden: $reason"
}

private fun receiptPostReason(raw: String): String? {
    val cleaned = raw
        .replace(Regex("""\s*CorrelationId:\s*[0-9a-fA-F-]+\.?""", RegexOption.IGNORE_CASE), "")
        .replace(Regex("""\s*Internal_ServerError\s*""", RegexOption.IGNORE_CASE), " ")
        .replace(Regex("""\s*Bad Request\s*""", RegexOption.IGNORE_CASE), " ")
        .replace(Regex("""\s{2,}"""), " ")
        .trim()
        .removePrefix("HATA:")
        .trim()
    if (cleaned.isBlank() || cleaned.startsWith("{")) return null

    Regex(
        """Location Code must be equal to '([^']*)'.*Current value is '([^']*)'""",
        RegexOption.IGNORE_CASE,
    ).find(cleaned)?.let {
        val expected = it.groupValues[1].ifBlank { "boş" }
        val current = it.groupValues[2].ifBlank { "boş" }
        return "Sipariş ve mal kabul lokasyonu uyuşmuyor (beklenen: $expected, mevcut: $current). BC'de sipariş satırının lokasyonunu düzeltin."
    }
    if (cleaned.contains("Location Code must have a value", ignoreCase = true))
        return "Sipariş satırında lokasyon boş. BC'de satır lokasyonunu doldurun."

    return cleaned
        .lineSequence()
        .firstOrNull { it.isNotBlank() }
        ?.substringBefore(" Stack trace", missingDelimiterValue = cleaned)
        ?.substringBefore(" at Microsoft.", missingDelimiterValue = cleaned)
        ?.take(320)
        ?.trim()
        ?.takeIf { it.isNotBlank() }
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
