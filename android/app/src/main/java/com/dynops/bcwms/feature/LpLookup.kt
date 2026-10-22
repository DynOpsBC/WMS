package com.dynops.bcwms.feature

import android.content.Context
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import org.json.JSONObject

// Kitoko (22 Eki 2026): Etiket Çıkar → LP Etiketi. LP'yi yalnız okutmak/yazmak
// yerine aranabilir liste: varsayılan aktif LP'ler (Açık/Oluşturuldu/Atandı),
// "Tümü" ile hepsi; LP no / ürün / lot / raf metniyle süzülür, en yeni LP üstte,
// $top ile sayfalı. Dokununca mevcut LP kartı (LP / lot etiketi) açılır.

internal const val LP_LOOKUP_PAGE_SIZE = 25

/** Ürün/lot eşleşmesinden LP başlık sorgusuna taşınan en fazla LP (URL kısa kalsın). */
internal const val LP_LOOKUP_LINE_MATCH_MAX = 40

internal val LP_LOOKUP_ACTIVE_STATUSES = listOf("Open", "Built", "Assigned")

internal const val LP_LOOKUP_HEADER_SELECT = "no,status,locationCode,binCode,sscc,lineCount,totalQuantity"

private fun odataLiteral(value: String) = value.replace("'", "''")

private fun clean(value: String?): String = value?.trim()?.takeUnless { it == "null" }.orEmpty()

/** Arama metni: BC kod alanları (LP no, ürün no, lot, raf) büyük harf tutulur. */
internal fun lpLookupNormalize(raw: String): String = raw.trim().uppercase()

/**
 * Listeye okutulan LP dışı barkod: ürün etiketinde (GS1 / alan adlı QR) lot
 * varsa lot, yoksa ürün no; diğerlerinde okunan metin.
 */
internal fun lpLookupQueryFromScan(raw: String): String {
    val resolved = BarcodeIntentResolver.resolve(raw)
    val value = clean(resolved.lotNo).ifEmpty { clean(resolved.itemNo) }.ifEmpty { resolved.value.trim() }.ifEmpty { raw.trim() }
    return lpLookupNormalize(value)
}

/** Ürün no ya da lot no'su aramayı içeren LP satırları (yalnız lpNo); boş aramada null. */
internal fun lpLookupLineMatchPath(query: String): String? {
    val q = lpLookupNormalize(query)
    if (q.isEmpty()) return null
    val s = odataLiteral(q)
    return "licensePlateLines?\$filter=contains(itemNo,'$s') or contains(lotNo,'$s')&\$select=lpNo&\$orderby=lpNo desc&\$top=200"
}

/** Satır eşleşmesinden gelen LP no'ları: tekrarsız, en yeni önce, en fazla [max]. */
internal fun lpLookupLineMatches(lpNos: List<String>, max: Int = LP_LOOKUP_LINE_MATCH_MAX): List<String> =
    lpNos.map { clean(it) }.filter { it.isNotEmpty() }.distinct()
        .sortedWith(warehouseBinCodeComparator.reversed()).take(max)

/**
 * LP başlık sorgusu: aktif durum süzgeci, metin (LP no / raf / SSCC içerir ya da
 * ürün/lot eşleşen LP), LP No azalan (en yeni üstte). Sonraki sayfa var mı
 * anlamak için [pageSize] + 1 satır istenir.
 */
internal fun lpLookupHeaderPath(
    query: String,
    activeOnly: Boolean,
    lineMatchLpNos: List<String>,
    skip: Int,
    pageSize: Int = LP_LOOKUP_PAGE_SIZE,
): String {
    val clauses = mutableListOf<String>()
    if (activeOnly) clauses += LP_LOOKUP_ACTIVE_STATUSES.joinToString(" or ", "(", ")") { "status eq '$it'" }
    val q = lpLookupNormalize(query)
    if (q.isNotEmpty()) {
        val s = odataLiteral(q)
        val text = mutableListOf("contains(no,'$s')", "contains(binCode,'$s')", "contains(sscc,'$s')")
        lpLookupLineMatches(lineMatchLpNos).forEach { text += "no eq '${odataLiteral(it)}'" }
        clauses += text.joinToString(" or ", "(", ")")
    }
    val filter = if (clauses.isEmpty()) "" else "&\$filter=" + clauses.joinToString(" and ")
    return "licensePlates?\$select=$LP_LOOKUP_HEADER_SELECT&\$orderby=no desc&\$top=${pageSize + 1}&\$skip=${skip.coerceAtLeast(0)}$filter"
}

/** Listedeki LP'lerin içeriği (ürün, açıklama, lot, miktar) tek sorguda; LP yoksa null. */
internal fun lpLookupContentPath(lpNos: List<String>): String? {
    val nos = lpNos.map { clean(it) }.filter { it.isNotEmpty() }.distinct()
    if (nos.isEmpty()) return null
    val filter = nos.joinToString(" or ") { "lpNo eq '${odataLiteral(it)}'" }
    return "licensePlateLines?\$filter=$filter&\$select=lpNo,lineNo,itemNo,itemDescription,lotNo,quantity,unitOfMeasure&\$orderby=lpNo,lineNo"
}

internal data class LpLookupRow(
    val no: String,
    val status: String,
    val locationCode: String,
    val binCode: String,
    val firstItemNo: String,
    val firstItemDescription: String,
    /** İlk üründen sonra kaç farklı ürün daha var. */
    val otherItemCount: Int,
    val lots: List<String>,
    /** "48 KOLİ · 12 ADET"; boş LP'de "Boş LP". */
    val totals: String,
)

/**
 * Başlık + içerik satırlarından liste satırı. [lines] null = içerik okunamadı;
 * toplam o zaman başlıktaki totalQuantity'den yazılır.
 */
internal fun lpLookupRows(headers: List<JSONObject>, lines: List<JSONObject>?): List<LpLookupRow> {
    val byLp = lines.orEmpty().filter { clean(it.optString("itemNo")).isNotEmpty() }.groupBy { clean(it.optString("lpNo")) }
    return headers.mapNotNull { h ->
        val no = clean(h.optString("no")).ifEmpty { return@mapNotNull null }
        val itemLines = byLp[no].orEmpty()
        val items = itemLines.map { clean(it.optString("itemNo")) }.distinct()
        val first = itemLines.firstOrNull()
        val totals = when {
            itemLines.isNotEmpty() -> lpCardTotals(itemLines)
            lines != null -> "Boş LP"
            h.optDouble("totalQuantity", 0.0) > 0.0 -> fmtItemQty(h.optDouble("totalQuantity", 0.0))
            else -> ""
        }
        LpLookupRow(
            no = no,
            status = clean(h.optString("status")),
            locationCode = clean(h.optString("locationCode")),
            binCode = clean(h.optString("binCode")),
            firstItemNo = clean(first?.optString("itemNo")),
            firstItemDescription = clean(first?.optString("itemDescription")),
            otherItemCount = (items.size - 1).coerceAtLeast(0),
            lots = itemLines.map { clean(it.optString("lotNo")) }.filter { it.isNotEmpty() }.distinct(),
            totals = totals,
        )
    }
}

/** "L1, L2, L3 +2"; lot yoksa "". */
internal fun lpLookupLotsLabel(lots: List<String>, shown: Int = 3): String =
    if (lots.isEmpty()) "" else lots.take(shown).joinToString(", ") + if (lots.size > shown) " +${lots.size - shown}" else ""

/** OK'a basılan metin listedeki bir LP'nin numarasıysa o LP (ör. "PAL-0001" gibi özel seri). */
internal fun lpLookupExactMatch(rows: List<LpLookupRow>, text: String): String? {
    val q = lpLookupNormalize(text)
    if (q.isEmpty()) return null
    return rows.firstOrNull { it.no.equals(q, ignoreCase = true) }?.no
}

internal sealed interface LpLookupLoad {
    data class Ready(val rows: List<LpLookupRow>, val hasMore: Boolean, val note: String) : LpLookupLoad
    data class Failed(val status: String) : LpLookupLoad
}

/** Bir sayfa LP: önce ürün/lot eşleşmesi, sonra başlıklar, sonra o sayfanın içeriği. */
internal suspend fun loadLpLookupPage(context: Context, query: String, activeOnly: Boolean, skip: Int): LpLookupLoad {
    val notes = mutableListOf<String>()
    var lineMatches = emptyList<String>()
    lpLookupLineMatchPath(query)?.let { path ->
        val r = BcApi.get(context, path)
        if (r.ok) {
            val all = BcApi.parseValueArray(r.body).map { it.optString("lpNo") }
            lineMatches = lpLookupLineMatches(all)
            if (all.map { clean(it) }.filter { it.isNotEmpty() }.distinct().size > LP_LOOKUP_LINE_MATCH_MAX)
                notes += "Ürün/lot eşleşmesi çok; en yeni $LP_LOOKUP_LINE_MATCH_MAX LP aranıyor, aramayı daraltın."
        } else {
            notes += "Ürün/lot ile aranamadı (HTTP ${r.httpCode}); yalnız LP no / raf aranıyor."
        }
    }
    val h = BcApi.get(context, lpLookupHeaderPath(query, activeOnly, lineMatches, skip))
    if (!h.ok) return LpLookupLoad.Failed("HATA: LP listesi alınamadı. ${BcApi.errorMessage(h.body)} (HTTP ${h.httpCode})")
    val all = BcApi.parseValueArray(h.body)
    val headers = all.take(LP_LOOKUP_PAGE_SIZE)
    val content = lpLookupContentPath(headers.map { it.optString("no") })?.let { path ->
        val page = BcApi.getAllPages(context, path)
        if (page.complete) page.rows else {
            notes += "LP içerikleri okunamadı; ürün/lot bilgisi eksik."
            null
        }
    }
    return LpLookupLoad.Ready(lpLookupRows(headers, content ?: if (headers.isEmpty()) emptyList() else null), all.size > LP_LOOKUP_PAGE_SIZE, notes.joinToString(" "))
}
