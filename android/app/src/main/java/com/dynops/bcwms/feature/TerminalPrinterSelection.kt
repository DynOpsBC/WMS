package com.dynops.bcwms.feature

import org.json.JSONObject

internal data class TerminalPrinterSelection(val label: String, val document: String)

/** Never replace cached settings with an unrelated or incomplete BC response. */
internal fun parseTerminalPrinterSelection(body: String, terminal: String, action: Boolean): TerminalPrinterSelection? = runCatching {
    val envelope = JSONObject(body)
    val row = if (action) JSONObject(envelope.getString("value")) else envelope
    require(row.getString(if (action) "terminalCode" else "code") == terminal)
    TerminalPrinterSelection(row.getString("labelPrinterCode"), row.getString("documentPrinterCode"))
}.getOrNull()
