package com.dynops.bcwms.feature

import org.json.JSONObject

internal data class MteOperatorRequest(val action: String, val body: String)

internal fun mteOperatorAction(entitySet: String, action: String): String? = when (entitySet) {
    "licensePlates" -> when (action) {
        "printPalletLabels" -> "printMteForOperator"
        "stopToPrinter" -> "stopToPrinterWithMte"
        else -> null
    }
    "receipts" -> if (action == "postAndCloseLP") "postAndCloseLPWithMte" else null
    "itemLedgerEntries" -> when (action) {
        "createLicensePlates" -> "createLicensePlatesWithMte"
        "createLicensePlatesIdempotent" -> "createLicensePlatesIdempotentWithMte"
        "createLicensePlatesFromPlanIdempotent" -> "createLicensePlatesFromPlanIdempotentWithMte"
        else -> null
    }
    else -> null
}

/** Preserve quantities, idempotency keys and explicit inspector selections. */
internal fun mteOperatorRequest(action: String, body: String, operatorName: String): MteOperatorRequest {
    require(operatorName.isNotBlank()) { "Giriş yapan kullanıcı belirlenemedi. PIN ile yeniden giriş yapın." }
    val payload = JSONObject(body)
    val options = payload.optString("optionsJson").takeIf { it.isNotBlank() }?.let(::JSONObject) ?: JSONObject()
    if (options.optString("inspectorEmployeeNo").isBlank()) {
        // Use a distinct field so a person's name cannot accidentally match an Employee No.
        options.put("operatorDisplayName", operatorName.trim())
    }
    payload.put("optionsJson", options.toString())
    return MteOperatorRequest(action, payload.toString())
}
