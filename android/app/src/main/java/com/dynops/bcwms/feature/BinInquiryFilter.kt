package com.dynops.bcwms.feature

import org.json.JSONObject

/** Filters the complete, already loaded bin contents without changing quantities or LP selection. */
internal fun filterBinInquiryItems(rows: List<JSONObject>, query: String): List<JSONObject> {
    val term = query.trim()
    if (term.isEmpty()) return rows
    return rows.filter {
        it.optString("itemNo").contains(term, ignoreCase = true) ||
            it.optString("itemDescription").contains(term, ignoreCase = true)
    }
}
