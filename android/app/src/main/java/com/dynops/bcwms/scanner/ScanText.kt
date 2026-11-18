package com.dynops.bcwms.scanner

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/**
 * DKÇ (18 Kas 2026): "QR'da Türkçe harfler gelmiyor". Etiketler ve QR PDF'leri
 * metni UTF-8 bayt olarak yazar (ÜR.0002, KÜLÇE.HM.0001). QR'da karakter
 * kümesi işareti (ECI) olmadığında el terminalinin tarayıcısı baytları Latin-1
 * sayabiliyor ve uygulamaya "ÃœR.0002" gibi bozuk metin gelir. Bu dosya ham
 * baytları ve bozuk metni yeniden UTF-8 olarak çözer.
 */
internal object ScanText {

    /** Baytlar geçerli UTF-8 ise metin; değilse null (kayıplı çözüm yapılmaz). */
    fun strictUtf8(bytes: ByteArray?): String? {
        if (bytes == null || bytes.isEmpty()) return null
        return try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: CharacterCodingException) {
            null
        }
    }

    /**
     * Latin-1 (ya da Windows-1252) diye okunmuş UTF-8 metni onarır:
     * "ÃœR.0002" → "ÜR.0002", "KÃœLÃ‡E" → "KÜLÇE". Metin zaten doğruysa ya da
     * onarım geçerli UTF-8 vermiyorsa olduğu gibi döner.
     */
    fun repair(text: String): String {
        if (text.none { it.code in 0x80..0xFF || it in CP1252_EXTRA.keys }) return text
        val bytes = ByteArray(text.length)
        for ((i, ch) in text.withIndex()) {
            val b = when {
                ch.code <= 0xFF -> ch.code
                else -> CP1252_EXTRA[ch] ?: return text
            }
            bytes[i] = b.toByte()
        }
        // Yalnız gerçekten çok baytlı UTF-8 dizisi içeren metin onarılır; tek
        // başına "É" gibi doğru Latin-1 harfler dokunulmadan kalır.
        val decoded = strictUtf8(bytes) ?: return text
        return if (decoded.length < text.length) decoded else text
    }

    /** Tarayıcının verdiği metin ve (varsa) ham baytlardan doğru metni seçer. */
    fun best(dataString: String, rawBytes: ByteArray?): String {
        val fromBytes = strictUtf8(rawBytes)
        if (fromBytes != null && fromBytes.isNotBlank()) return fromBytes
        return repair(dataString)
    }

    // Windows-1252'nin 0x80–0x9F aralığında Latin-1'den farklı gösterdiği harfler.
    private val CP1252_EXTRA: Map<Char, Int> = mapOf(
        '€' to 0x80, '‚' to 0x82, 'ƒ' to 0x83, '„' to 0x84, '…' to 0x85, '†' to 0x86, '‡' to 0x87,
        'ˆ' to 0x88, '‰' to 0x89, 'Š' to 0x8A, '‹' to 0x8B, 'Œ' to 0x8C, 'Ž' to 0x8E,
        '‘' to 0x91, '’' to 0x92, '“' to 0x93, '”' to 0x94, '•' to 0x95, '–' to 0x96, '—' to 0x97,
        '˜' to 0x98, '™' to 0x99, 'š' to 0x9A, '›' to 0x9B, 'œ' to 0x9C, 'ž' to 0x9E, 'Ÿ' to 0x9F,
    )
}
