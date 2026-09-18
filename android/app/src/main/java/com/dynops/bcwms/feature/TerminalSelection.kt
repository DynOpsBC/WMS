package com.dynops.bcwms.feature

import android.content.Context
import com.dynops.bcwms.BcApi
import org.json.JSONObject

internal data class WmsTerminalOption(
    val code: String,
    val labelPrinterCode: String,
    val documentPrinterCode: String,
)

internal fun terminalPreferenceScope(tenant: String, environment: String, company: String): String =
    listOf(tenant, environment, company).joinToString(":") { "${it.length}:$it" }

internal object WmsTerminalSession {
    private fun prefs(context: Context) = context.getSharedPreferences("bcwms_prefs", Context.MODE_PRIVATE)
    fun scope(context: Context) = terminalPreferenceScope(
        BcApi.getTenant(context), BcApi.getEnvironment(context), BcApi.getCompanyId(context),
    )
    private fun key(context: Context) = "wms_terminal." + scope(context)
    fun code(context: Context): String = prefs(context).getString(key(context), "").orEmpty()
    fun select(context: Context, terminal: WmsTerminalOption) {
        prefs(context).edit().putString(key(context), terminal.code).apply()
        applyTerminalPrinterDefault(context, terminal.labelPrinterCode, PRINTER_USAGE_LABEL)
        applyTerminalPrinterDefault(context, terminal.documentPrinterCode, PRINTER_USAGE_DOCUMENT)
    }
    fun clear(context: Context) { prefs(context).edit().remove(key(context)).apply() }
}

internal data class TerminalPrinterSelection(val label: String, val document: String)

internal fun parseTerminalPrinterSelection(body: String, terminal: String, action: Boolean): TerminalPrinterSelection? = runCatching {
    val envelope = JSONObject(body)
    val row = if (action) JSONObject(envelope.getString("value")) else envelope
    require(row.getString(if (action) "terminalCode" else "code") == terminal)
    TerminalPrinterSelection(row.getString("labelPrinterCode"), row.getString("documentPrinterCode"))
}.getOrNull()

internal suspend fun selectTerminalPrinter(context: Context, code: String, usage: String): Result<TerminalPrinterSelection> = runCatching {
    val terminal = WmsTerminalSession.code(context)
    val username = BcApi.getLocalUser(context)
    require(terminal.isNotBlank()) { "Önce terminal seçin." }
    require(username.isNotBlank()) { "Önce kullanıcı girişi yapın." }
    val response = BcApi.boundAction(
        context, "wmsTerminals", terminal, "selectPrinter",
        JSONObject().put("username", username).put("usage", usage).put("printerCode", code).toString(),
    )
    require(response.ok) { BcApi.errorMessage(response.body).ifBlank { "Yazıcı BC'ye kaydedilemedi." } }
    val selected = requireNotNull(parseTerminalPrinterSelection(response.body, terminal, true)) { "BC yanıtı doğrulanamadı." }
    applyTerminalPrinterDefault(context, selected.label, PRINTER_USAGE_LABEL)
    applyTerminalPrinterDefault(context, selected.document, PRINTER_USAGE_DOCUMENT)
    selected
}
