package com.dynops.bcwms.feature

import com.dynops.bcwms.ui.rawValue
import org.json.JSONObject

internal data class PickLotInputPolicy(
    val required: Boolean,
    val visible: Boolean,
    val detectFromStock: Boolean,
)

/** Warehouse tracking is authoritative; sales/inventory lots do not enable pick tracking. */
internal fun pickLotInputPolicy(lines: List<JSONObject>): PickLotInputPolicy {
    val required = lines.any {
        it.optBoolean("lotRequired", false) || rawValue(it, "lotNo").isNotBlank()
    }
    // Older BC packages omit the flag. Keep their stock check, but never
    // override an explicit false returned by the warehouse tracking setup.
    val unknown = lines.any { !it.has("lotRequired") || it.isNull("lotRequired") }
    return PickLotInputPolicy(required, required || unknown, unknown && !required)
}
