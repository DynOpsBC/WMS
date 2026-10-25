package com.dynops.bcwms.feature

import org.json.JSONArray
import org.json.JSONObject

/*
 * BADE (23 Eki 2026, BC 1.14.1.152 / Android 1.14.200 - Merve geri bildirimi):
 * yerleştirme listesinde LP ile arama, atanmamış belgelerin "bana" listesinde
 * görünmesi, boş göz önerisi ve kartın yalnız operatör onayından sonra yeşil olması.
 * Ekran kodundan ayrı tutulan saf kurallar; birim testleri PutAwayWorkflowTest'te.
 */

/** BC suggestEmptyBins yanıtındaki tek öneri (source: BC, EMPTY, BC_FALLBACK). */
internal data class PutAwayBinSuggestion(val binCode: String, val zoneCode: String, val source: String) {
    /** BC'nin kendi önerisi değil, kuralın bulduğu boş göz. */
    val isEmptyBin: Boolean get() = source.equals("EMPTY", true) || source.equals("BC", true)
}

/** suggestEmptyBins skaler yanıtı (JSON dizi metni) → Koy satır no → öneri. Bozuk yanıt boş harita. */
internal fun parsePutAwayBinSuggestions(raw: String): Map<Int, PutAwayBinSuggestion> = runCatching {
    val arr = JSONArray(raw.trim().ifBlank { "[]" })
    buildMap {
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val lineNo = o.optInt("lineNo", 0)
            val bin = o.optString("binCode").trim()
            if (lineNo == 0 || bin.isBlank()) continue
            put(lineNo, PutAwayBinSuggestion(bin, o.optString("zoneCode").trim(), o.optString("source").trim()))
        }
    }
}.getOrDefault(emptyMap())

/** Kartta / adımda gösterilecek hedef: onaylanmamışsa "Öneri", onaylanmışsa "Koy". */
internal data class PutAwayCardTarget(val label: String, val bin: String, val confirmed: Boolean)

/**
 * BC yerleştirme satırlarını Qty. to Handle dolu oluşturduğu için kart hiçbir şey
 * yapılmadan "✓ Hazır" görünüyordu. Kart artık yalnız operatör bu çifti terminalde
 * doğruladığında (staged) yeşil olur; o zamana dek hedef göz nötr "Öneri" olarak
 * gösterilir. Öneri boş göz kuralından gelir, yoksa BC'nin Koy gözü.
 */
internal fun putAwayCardTarget(staged: Boolean, placeBin: String, suggestion: PutAwayBinSuggestion?): PutAwayCardTarget {
    val bc = placeBin.trim()
    if (staged) return PutAwayCardTarget("📥 Koy", bc.ifBlank { "-" }, confirmed = true)
    val suggested = suggestion?.binCode?.trim().orEmpty().ifBlank { bc }
    return if (suggested.isBlank()) PutAwayCardTarget("📥 Koy", "Raf okutun", confirmed = false)
    else PutAwayCardTarget("📥 Öneri", suggested, confirmed = false)
}

/** Kartın "Hazır" sayılması: yalnız terminalde doğrulanmış çift. */
internal fun putAwayPairReady(staged: Boolean): Boolean = staged

/** "Bana + boşta" görünümü: bana atanmış veya hiç atanmamış belgeler. */
internal fun putAwayVisibleForMine(row: JSONObject, myUser: String): Boolean {
    val owner = row.optString("assignedUserId").trim()
    return owner.isBlank() || (myUser.isNotBlank() && owner.equals(myUser.trim(), ignoreCase = true))
}

/** Önce bana atanan, sonra atanmamış, en sonda başkasındaki belgeler; grup içinde sıra korunur. */
internal fun sortPutAwaysForUser(rows: List<JSONObject>, myUser: String): List<JSONObject> =
    rows.sortedBy { row ->
        val owner = row.optString("assignedUserId").trim()
        when {
            myUser.isNotBlank() && owner.equals(myUser.trim(), ignoreCase = true) -> 0
            owner.isBlank() -> 1
            else -> 2
        }
    }

/** Atanan kullanıcının adı (BC 1.14.1.152 assignedUserName); yoksa kimlik; o da yoksa "Atanmamış". */
internal fun putAwayAssigneeLabel(assignedUserId: String, assignedUserName: String): String {
    val name = assignedUserName.trim().takeUnless { it.equals("null", true) }.orEmpty()
    val id = assignedUserId.trim()
    return name.ifBlank { id }.ifBlank { "Atanmamış" }
}

private fun odataQuote(value: String): String = value.trim().replace("'", "''")

/** LP'yi taşıyan yerleştirme satırları (Al veya Koy). */
internal fun putAwayLinesByLpPath(lpNo: String): String =
    "putAwayLines?\$filter=lpNo eq '${odataQuote(lpNo.uppercase())}'&\$select=no&\$top=200"

/** SSCC okutulduğunda LP no'yu bulmak için. */
internal fun licensePlateBySsccPath(sscc: String): String =
    "licensePlates?\$filter=sscc eq '${odataQuote(sscc)}'&\$select=no,assignedDocumentType,assignedDocumentNo&\$top=2"

/** LP başlığı bir yerleştirmeye atanmışsa o belge (satır damgası olmayan eski belgeler için). */
internal fun putAwayNoFromLpAssignment(lp: JSONObject?): String? {
    if (lp == null) return null
    val type = lp.optString("assignedDocumentType").trim()
    val no = lp.optString("assignedDocumentNo").trim()
    return no.takeIf { it.isNotBlank() && type.replace(" ", "").equals("WhsePutaway", ignoreCase = true) }
}

/** Arama/okutma sonucu ne yapılacak: tek belge açılır, birden çoksa liste süzülür. */
internal sealed class PutAwaySearchOutcome {
    data class Open(val no: String) : PutAwaySearchOutcome()
    data class Filter(val docs: Set<String>) : PutAwaySearchOutcome()
    object NotFound : PutAwaySearchOutcome()
}

internal fun putAwaySearchOutcome(docs: Set<String>): PutAwaySearchOutcome = when (docs.size) {
    0 -> PutAwaySearchOutcome.NotFound
    1 -> PutAwaySearchOutcome.Open(docs.first())
    else -> PutAwaySearchOutcome.Filter(docs)
}

/** BADE (25 Eki 2026): bins yanıtında okutulan koda TAM eşit raf (büyük/küçük harf duyarsız). */
internal fun putAwayExactBinRow(rows: List<JSONObject>, binCode: String): JSONObject? =
    rows.firstOrNull { it.optString("code").trim().equals(binCode.trim(), ignoreCase = true) }

/**
 * BADE (25 Eki 2026): hedef raf için operatöre gösterilecek hata; null = raf uygun.
 * [bin] null ise raf lokasyonda yok. Sunucu putAwayBlock / putAwayBlockMessage
 * (BC 1.14.1.153+) verir; eski BC'de yalnız blockMovement'a bakılır.
 * Kalite reddi alan LP'nin ret/karantina gözü ([qualityRejectBin]) her zaman kabul edilir.
 */
internal fun putAwayTargetBinError(
    scanned: String,
    locationCode: String,
    bin: JSONObject?,
    qualityRejectBin: String = "",
): String? {
    val shown = scanned.trim()
    if (bin == null) {
        return if (locationCode.isNotBlank())
            "❌ $shown rafı $locationCode lokasyonunda yok. Raf kodunu kontrol edip tekrar okutun."
        else
            "❌ $shown rafı bulunamadı. Raf kodunu kontrol edip tekrar okutun."
    }
    val code = bin.optString("code").trim().ifBlank { shown }
    if (qualityRejectBin.isNotBlank() && code.equals(qualityRejectBin.trim(), ignoreCase = true)) return null
    val reason = bin.optString("putAwayBlock").trim().lowercase().ifBlank {
        when (BcEnum.decodeOData(bin.optString("blockMovement")).trim().lowercase()) {
            "inbound", "all" -> "blocked"
            else -> ""
        }
    }
    if (reason.isBlank()) return null
    val serverMessage = bin.optString("putAwayBlockMessage").trim()
    if (serverMessage.isNotBlank()) return "❌ $serverMessage"
    return when (reason) {
        "blocked" -> "❌ $code rafı yerleştirmeye kapalı (hareket blokajı). Başka bir raf okutun."
        "receive" -> "❌ $code rafı mal kabul gözüdür; yerleştirme hedefi olamaz. Başka bir raf okutun."
        "ship" -> "❌ $code rafı sevkiyat gözüdür; yerleştirme hedefi olamaz. Başka bir raf okutun."
        "adjustment" -> "❌ $code rafı düzeltme (sayım farkı) gözüdür; yerleştirme hedefi olamaz. Başka bir raf okutun."
        else -> "❌ $code rafına yerleştirme yapılamaz. Başka bir raf okutun."
    }
}

/**
 * Toplu LP yerleştirmede okutulan/yazılan raf: önce tam eşleşme; yoksa kısmi
 * yazımda (ör. "Y.G03") yalnız TEK aday varsa o. Birden çok aday ya da hiç
 * aday yoksa null — eskiden ilk kısmi eşleşme sessizce seçiliyordu.
 */
internal fun putAwayBatchBinRow(rows: List<JSONObject>, candidate: String): JSONObject? =
    putAwayExactBinRow(rows, candidate) ?: rows.singleOrNull()
