package com.dynops.bcwms.feature

import android.content.Context
import com.dynops.bcwms.BcApi
import org.json.JSONObject

internal data class TerminalPrinterSelection(val label: String, val document: String)

/** Never replace cached settings with an unrelated or incomplete BC response. */
internal fun parseTerminalPrinterSelection(body: String, terminal: String, action: Boolean): TerminalPrinterSelection? = runCatching {
    val envelope = JSONObject(body)
    val row = if (action) JSONObject(envelope.getString("value")) else envelope
    require(row.getString(if (action) "terminalCode" else "code") == terminal)
    TerminalPrinterSelection(row.getString("labelPrinterCode"), row.getString("documentPrinterCode"))
}.getOrNull()

/**
 * BADE: the terminal's printer is saved on its BC terminal record, then BC's
 * answer becomes the local default. Requires a PIN session; a selection that
 * finishes after the operator switched terminal or company is not applied.
 * Shared by the Yazıcılar screen and the label screens' printer card.
 */
internal suspend fun selectTerminalPrinter(context: Context, code: String, usage: String): Result<TerminalPrinterSelection> = runCatching {
    require(TerminalSession.authenticated(context)) { "Yazıcı ayarı için PIN ile giriş yapın." }
    val terminal = TerminalSession.code(context)
    val terminalScope = TerminalSession.scope(context)
    val response = BcApi.boundAction(context, "wmsTerminals", terminal, "selectPrinter",
        JSONObject().put("username", BcApi.getLocalUser(context))
            .put("usage", usage).put("printerCode", code).toString())
    val selection = (if (response.ok) parseTerminalPrinterSelection(response.body, terminal, true) else null)
        ?: error(if (response.httpCode == 404) "BC uzantısını 1.14.1.58 veya üstüne güncelleyin. Yazıcı kaydedilmedi."
            else "Yazıcı BC'ye kaydedilemedi. Bağlantıyı ve yetkinizi kontrol edip yenileyin.")
    check(terminalScope == TerminalSession.scope(context) && terminal == TerminalSession.code(context)) {
        "Terminal değişti; yazıcı seçimi bu terminale uygulanmadı."
    }
    applyTerminalPrinterDefault(context, selection.label, PRINTER_USAGE_LABEL)
    applyTerminalPrinterDefault(context, selection.document, PRINTER_USAGE_DOCUMENT)
    selection
}
