package com.dynops.bcwms.feature

import org.json.JSONObject

internal data class CountRoundValues(
    val systemQty: Double,
    val countedQty: Double?,
    val systemBins: String,
    val countedBins: String,
    val scopeBins: String = systemBins,
    val recordedLpQty: Double? = null,
) {
    val variance: Double? get() = countedQty?.minus(systemQty)
}

internal data class CountRoundComparison(
    val label: String,
    val previous: CountRoundValues?,
    val current: CountRoundValues?,
) {
    val change: Double? get() = previous?.countedQty?.let { before -> current?.countedQty?.minus(before) }
}

/** LP identity survives a bin move; loose stock stays separate per bin and UOM. */
internal fun compareCountRounds(previous: List<JSONObject>, current: List<JSONObject>, slot: Int): List<CountRoundComparison> {
    fun key(line: JSONObject): List<String> = listOf(
        line.optString("itemNo"), line.optString("variantCode"), line.optString("unitOfMeasureCode"),
        line.optString("lotNo"), line.optString("serialNo"), line.optString("lpNo"),
        if (line.optString("lpNo").isBlank()) line.optString("binCode") else line.optInt("lpLineNo").toString(),
    )
    fun values(lines: List<JSONObject>?): CountRoundValues? = lines?.let { group ->
        val counted = group.all { it.optBoolean("counted$slot") || it.optDouble("countedQty$slot", 0.0) != 0.0 }
        CountRoundValues(
            // Findings have systemQty=0. Do not add foundLpQty to the snapshot:
            // a source-bin zero and its found-bin count describe the same LP.
            systemQty = group.sumOf { it.optDouble("systemQty", 0.0) },
            countedQty = if (counted) group.sumOf { it.optDouble("countedQty$slot", 0.0) } else null,
            systemBins = group.map { it.optString("foundFromBin").ifBlank { it.optString("binCode") } }.distinct().joinToString(", "),
            scopeBins = group.map { it.optString("binCode") }.distinct().joinToString(", "),
            recordedLpQty = group.firstOrNull { it.optString("foundFromBin").isNotBlank() }?.optDouble("foundLpQty"),
            countedBins = group.filter { it.optDouble("countedQty$slot", 0.0) > 0.0 }
                .map { it.optString("binCode") }.distinct().joinToString(", ").ifBlank { "—" },
        )
    }
    val before = previous.groupBy(::key)
    val after = current.groupBy(::key)
    return (before.keys + after.keys).map { identity ->
        val line = (after[identity] ?: before.getValue(identity)).first()
        val label = listOf(line.optString("itemNo"), line.optString("description"),
            line.optString("lpNo").takeIf { it.isNotBlank() }?.let { "LP: $it" }.orEmpty(),
            line.optString("lotNo").takeIf { it.isNotBlank() }?.let { "Lot: $it" }.orEmpty(),
            line.optString("unitOfMeasureCode")).filter { it.isNotBlank() }.joinToString(" · ")
        CountRoundComparison(label, values(before[identity]), values(after[identity]))
    }
}
