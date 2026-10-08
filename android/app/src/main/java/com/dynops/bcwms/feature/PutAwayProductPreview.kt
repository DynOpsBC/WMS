package com.dynops.bcwms.feature

import com.dynops.bcwms.ui.rawValue
import org.json.JSONObject

internal fun putAwayProductPreviewPath(documentNos: List<String>): String {
    require(documentNos.isNotEmpty())
    val filter = documentNos.joinToString(" or ") { "no eq '${it.replace("'", "''")}'" }
    return "putAwayLines?\$select=no,itemNo,description&\$filter=($filter)"
}

/** Collapse Take/Place, lot and bin splits into one product per document. */
internal fun putAwayProductPreviews(lines: List<JSONObject>): Map<String, List<String>> = lines
    .filter { rawValue(it, "no").isNotBlank() && rawValue(it, "itemNo").isNotBlank() }
    .groupBy { rawValue(it, "no") }
    .mapValues { (_, documentLines) ->
        documentLines.groupBy { rawValue(it, "itemNo") }.map { (itemNo, itemLines) ->
            val description = itemLines.firstNotNullOfOrNull { line ->
                rawValue(line, "description").trim().takeIf { it.isNotBlank() }
            }
            if (description == null) itemNo else "$itemNo · $description"
        }
    }
