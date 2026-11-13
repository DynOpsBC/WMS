package com.dynops.bcwms.feature

import org.json.JSONObject

/** Keep each variant/UOM row intact. The item card supplies the total in base UOM. */
internal fun stockedItemBins(rows: List<JSONObject>): List<JSONObject> = rows
    .filter { it.optDouble("quantity", 0.0) != 0.0 }
    .sortedWith(compareBy({ it.optString("locationCode") }, { it.optString("binCode") },
        { it.optString("variantCode") }, { it.optString("unitOfMeasureCode") }))

internal data class ItemStockBin(val code: String, val rows: List<JSONObject>) {
    val baseQuantity: Double? get() = stockBaseQuantity(rows)
}

internal data class ItemStockLocation(val code: String, val bins: List<ItemStockBin>) {
    val baseQuantity: Double? get() = stockBaseQuantity(bins.flatMap { it.rows })
}

/** Never add quantities in different UOMs; BC supplies the converted base quantity. */
private fun stockBaseQuantity(rows: List<JSONObject>): Double? {
    val values = rows.map { it.optDouble("qtyBaseUoM", Double.NaN) }
    return if (values.all { it.isFinite() }) values.sum() else null
}

internal fun itemStockLocations(rows: List<JSONObject>): List<ItemStockLocation> {
    require(rows.all { it.optDouble("quantity", Double.NaN).isFinite() }) { "Eksik stok miktarı" }
    return stockedItemBins(rows).groupBy { it.optString("locationCode") }.map { (location, contents) ->
        ItemStockLocation(location, contents.groupBy { it.optString("binCode") }.map { (bin, lines) ->
            ItemStockBin(bin, lines)
        })
    }
}

internal fun itemStockPath(itemNo: String): String =
    "binContents?\$filter=itemNo eq '${itemNo.replace("'", "''")}'"

/** Preserve BC quantity precision, including small fractional stock. */
internal fun formatStockQuantity(quantity: Double): String =
    java.text.NumberFormat.getNumberInstance(java.util.Locale.forLanguageTag("tr-TR")).apply {
        maximumFractionDigits = 5
    }.format(quantity)
