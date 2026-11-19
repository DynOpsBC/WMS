package com.dynops.bcwms.feature

import org.json.JSONObject

/**
 * DKÇ (19 Kas 2026): operatör boş bir LP açıp içine kendisi ürün koyar (iki
 * farklı ürün ya da bir ürünün bir kısmı). "Stoktan LP Oluştur" tek bir stok
 * kaydından tek ürünlü LP üretir; karışık LP için boş LP gerekir.
 */
internal sealed interface EmptyLpBin {
    data class Found(val binCode: String, val locationCode: String) : EmptyLpBin
    data class Problem(val message: String) : EmptyLpBin
}

/** Okutulan rafın lokasyonu: raf tek lokasyonda olmalı, yoksa LP yanlış depoda açılır. */
internal fun resolveEmptyLpBin(binRows: List<JSONObject>, scannedBin: String): EmptyLpBin {
    val wanted = scannedBin.trim()
    val matches = binRows.filter { it.optString("code").trim().equals(wanted, ignoreCase = true) }
    val locations = matches.map { it.optString("locationCode").trim() }.filter { it.isNotEmpty() }.distinct()
    return when {
        wanted.isEmpty() -> EmptyLpBin.Problem("LP'nin duracağı rafı okutun.")
        matches.isEmpty() -> EmptyLpBin.Problem("$wanted rafı bulunamadı. Raf etiketini yeniden okutun.")
        locations.size != 1 ->
            EmptyLpBin.Problem("$wanted rafı birden çok lokasyonda var (${locations.joinToString(", ")}). Yöneticinize bildirin.")
        else -> EmptyLpBin.Found(matches.first().optString("code").trim(), locations.first())
    }
}

internal fun emptyLpRequestBody(templateCode: String, bin: EmptyLpBin.Found): String =
    JSONObject()
        .put("templateCode", templateCode.trim())
        .put("locationCode", bin.locationCode)
        .put("binCode", bin.binCode)
        .toString()

/** Sunucunun döndürdüğü yeni LP numarası; okunamazsa boş. */
internal fun createdLpNo(responseBody: String): String =
    runCatching { JSONObject(responseBody).optString("no").trim() }.getOrDefault("")
