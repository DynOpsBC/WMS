package com.dynops.bcwms.feature

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import org.json.JSONObject

/*
 * Kitoko (19 Eki 2026): EMU'nun TerminalPrinterBar.kt dosyasından yalnız etiket
 * ekranlarının yazıcı kartı için gerekenler. Üst çubuk BADE'nin ActiveLabelPrinter'ı
 * olarak kalır; EMU'nun LabelPrinterBar / TerminalPrintersScreen'i taşınmadı.
 */

/**
 * One printer binding as the operator sees it: the operator-facing name (BC
 * description, typed in the print agent), the code, and whether the agent last
 * reported it online.
 */
internal data class PrinterBinding(
    val code: String,
    val name: String,
    val online: Boolean?,
    val lastSeen: String,
) {
    val isSet: Boolean get() = code.isNotBlank()
    val title: String get() = if (name.isNotBlank() && !name.equals(code, ignoreCase = true)) name else code
}

internal fun printerBindingFrom(code: String, row: JSONObject?): PrinterBinding {
    if (code.isBlank()) return PrinterBinding("", "", null, "")
    if (row == null) return PrinterBinding(code, "", null, "")
    val status = row.optString("agentStatus").lowercase()
    val online = when (status) {
        "online", "printing" -> true
        "offline", "error" -> false
        else -> null
    }
    val lastSeen = runCatching {
        java.time.Instant.parse(row.optString("lastSeenAt")).atZone(java.time.ZoneId.systemDefault())
            .takeIf { it.year > 2000 }?.format(java.time.format.DateTimeFormatter.ofPattern("dd.MM HH:mm"))
    }.getOrNull().orEmpty()
    return PrinterBinding(code, row.optString("description").trim(), online, lastSeen)
}

/**
 * The terminal's printer for a usage, re-read whenever any preference changes.
 * Goes through [getDefaultPrinter] so it follows the per-terminal scoped keys.
 */
@Composable
internal fun rememberDevicePrinter(usage: String): String {
    val context = LocalContext.current
    val prefs = remember(context) { context.getSharedPreferences("bcwms_prefs", Context.MODE_PRIVATE) }
    var value by remember(prefs, usage) { mutableStateOf(getDefaultPrinter(context, usage)) }
    DisposableEffect(prefs, usage) {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
            value = getDefaultPrinter(context, usage)
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        value = getDefaultPrinter(context, usage)
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    return value
}
