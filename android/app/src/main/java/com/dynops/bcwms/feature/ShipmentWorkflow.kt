package com.dynops.bcwms.feature

import org.json.JSONArray
import org.json.JSONObject

/**
 * Sevkiyat için toplama (pick) oluştururken kaynak paleti operatörün seçmesi.
 *
 * Saha sorunu (Merve, BADE/MERKEZDEPO): "Pick Oluştur"a basınca BC hangi paletten
 * toplanacağına kendi karar veriyordu; operatör LP000023'ten sevk etmek isterken
 * toplama LP000024'ten üretiliyordu. Sunucu tarafı artık aday paletleri
 * `pickSourceOptions` ile listeliyor. Bir palet seçilirse kendi rafındaki LP
 * dağıtımında öncelik alır; kalan miktar raf sırasındaki uygun paletlerden tamamlanır.
 * Buradaki saf fonksiyonlar o cevabı yorumlar ve raf sırasını sabitler.
 */

/** `pickSourceOptions` cevabındaki tek bir palet adayı. */
internal data class PickSourceOption(
    val lpNo: String,
    val binCode: String,
    val itemNo: String,
    val itemDescription: String,
    val lotNo: String,
    val availableQtyBase: Double,
    val uom: String,
    val coversFullDemand: Boolean,
)

/**
 * Seçim penceresi yalnız gerçek bir seçim varken açılır. 0 aday = sunucu karar
 * versin, 1 aday = zaten tek palet, sormaya gerek yok (operatör her tuşa iki kez
 * basmasın).
 */
internal fun pickLpChoiceNeeded(optionCount: Int): Boolean = optionCount >= 2

/** Tek bir aday LP sipariş talebinin tamamını karşılayamıyorsa çoklu LP gerekir. */
internal fun combinedLpPickRequired(options: List<PickSourceOption>): Boolean =
    options.size >= 2 && options.none(PickSourceOption::coversFullDemand)

/**
 * Depo yürüme sırası: sayı bloklarını sayısal karşılaştırır (A-2 < A-10), boş
 * rafı sona bırakır. Pick ekranları ve kaynak-LP penceresi aynı sırayı kullanır.
 */
internal val warehouseBinCodeComparator: Comparator<String> = Comparator { a, b ->
    if (a.isBlank() != b.isBlank()) return@Comparator if (a.isBlank()) 1 else -1
    val na = a.length
    val nb = b.length
    var i = 0
    var j = 0
    while (i < na && j < nb) {
        val ca = a[i]
        val cb = b[j]
        if (ca.isDigit() && cb.isDigit()) {
            var si = i
            while (si < na && a[si].isDigit()) si++
            var sj = j
            while (sj < nb && b[sj].isDigit()) sj++
            val da = a.substring(i, si).trimStart('0')
            val db = b.substring(j, sj).trimStart('0')
            if (da.length != db.length) return@Comparator da.length - db.length
            val c = da.compareTo(db)
            if (c != 0) return@Comparator c
            i = si
            j = sj
        } else {
            val c = ca.uppercaseChar().compareTo(cb.uppercaseChar())
            if (c != 0) return@Comparator c
            i++
            j++
        }
    }
    (na - i) - (nb - j)
}

/**
 * Eski BC paketinde `pickSourceOptions` / `createPickFromLp` bound action'ları
 * yok. O durumda operatöre korkutucu bir hata göstermek yerine sessizce eski
 * `createPickFor` davranışına dönülür. Yalnız "böyle bir action yok" anlamına
 * gelen cevaplar fallback sayılır; yetki/kilit/iş kuralı hataları gerçek hatadır.
 */
internal fun shouldFallbackToLegacyCreatePick(httpCode: Int, responseBody: String): Boolean {
    if (httpCode == 404 || httpCode == 405 || httpCode == 501) return true
    if (httpCode != 400) return false
    val body = responseBody.lowercase()
    return listOf(
        "could not find",
        "not found",
        "no http resource",
        "unknown action",
        "does not exist",
        "bound action",
    ).any(body::contains)
}

/**
 * `pickSourceOptions` bir JSON DİZİSİNİ metin değeri olarak döndürür
 * (Edm.String -> {"value":"[...]"}); BcApi.scalarValue ile çıkarılan metin buraya
 * gelir. Bozuk/boş cevapta boş liste döner: operatör hata görmesin, sistem seçsin
 * yoluna düşülsün. LP numarası olmayan kayıtlar atılır — createPickFromLp'ye boş
 * lpNo göndermek BC'de anlamsız hata üretir.
 */
internal fun parsePickSourceOptions(json: String): List<PickSourceOption> {
    val trimmed = json.trim()
    if (trimmed.isBlank()) return emptyList()
    val arr = try {
        JSONArray(trimmed)
    } catch (e: Exception) {
        // Sunucu diziyi {"value":[...]} içinde sarmalarsa da okunsun.
        try {
            JSONObject(trimmed).optJSONArray("value") ?: return emptyList()
        } catch (e2: Exception) {
            return emptyList()
        }
    }
    val out = ArrayList<PickSourceOption>(arr.length())
    for (i in 0 until arr.length()) {
        val o = arr.optJSONObject(i) ?: continue
        val lp = o.optString("lpNo").trim()
        if (lp.isBlank()) continue
        out.add(
            PickSourceOption(
                lpNo = lp,
                binCode = o.optString("binCode").trim(),
                itemNo = o.optString("itemNo").trim(),
                itemDescription = o.optString("itemDescription").trim(),
                lotNo = o.optString("lotNo").trim(),
                availableQtyBase = o.optDouble("availableQtyBase", 0.0).let { if (it.isNaN()) 0.0 else it },
                uom = o.optString("uom").trim(),
                coversFullDemand = o.optBoolean("coversFullDemand", false),
            )
        )
    }
    return out.sortedWith { left, right ->
        val byBin = warehouseBinCodeComparator.compare(left.binCode, right.binCode)
        if (byBin != 0) byBin else left.lpNo.compareTo(right.lpNo, ignoreCase = true)
    }
}

/** Depo ekranında 1000.0 yerine 1000 görünsün. */
internal fun formatPickQty(value: Double): String =
    if (value == value.toLong().toDouble()) value.toLong().toString()
    else "%.2f".format(value).trimEnd('0').trimEnd('.')

/**
 * Seçim listesindeki satır alt yazısı: raf · lot · miktar (birim) · malzeme.
 * Boş alanlar tamamen atlanır, aradaki ayraçlar sarkmasın.
 */
internal fun pickSourceSubtitle(option: PickSourceOption): String {
    val parts = ArrayList<String>(4)
    if (option.binCode.isNotBlank()) parts.add("Raf: ${option.binCode}")
    if (option.lotNo.isNotBlank()) parts.add("Lot: ${option.lotNo}")
    val qty = formatPickQty(option.availableQtyBase)
    parts.add(if (option.uom.isNotBlank()) "Mevcut: $qty ${option.uom}" else "Mevcut: $qty")
    val item = when {
        option.itemNo.isNotBlank() && option.itemDescription.isNotBlank() -> "${option.itemNo} — ${option.itemDescription}"
        option.itemNo.isNotBlank() -> option.itemNo
        else -> option.itemDescription
    }
    if (item.isNotBlank()) parts.add(item)
    return parts.joinToString(" · ")
}
