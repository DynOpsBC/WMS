package com.dynops.bcwms.feature

import org.json.JSONObject
import java.util.Locale

/** The entire leading letter group is the section: X01 and XY01 differ. */
internal fun binSection(code: String): String =
    code.trim().takeWhile { it.isLetter() }.uppercase(Locale.ROOT).ifBlank { "Diğer" }

internal fun binSectionChoices(rows: List<JSONObject>): List<Pair<String, String>> =
    rows.groupingBy { binSection(it.optString("code")) }.eachCount()
        .toSortedMap().map { (section, count) -> section to "$count raf" }

internal fun filterBinSection(rows: List<JSONObject>, section: String): List<JSONObject> =
    sortedBinCodes(if (section.isBlank()) rows else rows.filter {
        binSection(it.optString("code")).equals(section.trim(), ignoreCase = true)
    })
