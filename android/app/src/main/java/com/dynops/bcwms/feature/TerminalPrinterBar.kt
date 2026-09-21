package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * BADE (17 Eyl 2026): "terminalde hangi yazıcıya bağlı olduğum adı gözüksün,
 * etiket yazıcısı sürekli gözüksün". One printer binding as the operator sees
 * it: the operator-facing name (BC description, typed in the print agent),
 * the code, and whether the agent last reported it online.
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

internal suspend fun loadPrinterBinding(context: Context, code: String): PrinterBinding {
    if (code.isBlank()) return printerBindingFrom("", null)
    val r = BcApi.get(context, "printers?\$filter=code eq '${code.replace("'", "''")}'&\$top=1")
    val row = if (r.ok) BcApi.parseValueArray(r.body).firstOrNull() else null
    return printerBindingFrom(code, row)
}

/**
 * The device's printer for a usage, re-read whenever any preference changes.
 * Goes through [getDefaultPrinter] so it follows whatever key scheme the
 * flavour uses (plain per-device keys or per-terminal scoped keys).
 */
@Composable
internal fun rememberDevicePrinter(usage: String): String {
    val context = LocalContext.current
    val prefs = remember(context) { context.getSharedPreferences("bcwms_prefs", Context.MODE_PRIVATE) }
    var value by remember(prefs, usage) { mutableStateOf(getDefaultPrinter(context, usage)) }
    DisposableEffect(prefs, usage) {
        val listener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
            value = getDefaultPrinter(context, usage)
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        value = getDefaultPrinter(context, usage)
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    return value
}

/** Top bar shortcut with the Print Agent display name of the active label printer. */
@Composable
internal fun ActivePrinterTopBarButton(onClick: () -> Unit) {
    val context = LocalContext.current
    val code = rememberDevicePrinter(PRINTER_USAGE_LABEL)
    var binding by remember { mutableStateOf(printerBindingFrom(code, null)) }
    LaunchedEffect(code) {
        binding = printerBindingFrom(code, null)
        binding = runCatching { loadPrinterBinding(context, code) }.getOrDefault(binding)
    }
    TextButton(onClick = onClick) {
        Text(
            if (code.isBlank()) "Yazıcı · Seçilmedi" else "Yazıcı · ${binding.title.ifBlank { code }}",
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
        )
    }
}

/** Green / red / grey dot for the agent-reported state. */
@Composable
internal fun PrinterStateDot(online: Boolean?, size: androidx.compose.ui.unit.Dp = 10.dp) {
    val color = when (online) {
        true -> Color(0xFF16A34A)
        false -> Color(0xFFDC2626)
        null -> Color(0xFF9CA3AF)
    }
    Box(Modifier.size(size).background(color, CircleShape))
}

/**
 * Thin strip under the top bar on every operational screen: which label
 * printer this terminal prints to. Tapping opens the printers screen.
 */
@Composable
internal fun LabelPrinterBar(onOpenPrinters: () -> Unit, quiet: Boolean = false) {
    val context = LocalContext.current
    val code = rememberDevicePrinter(PRINTER_USAGE_LABEL)
    var binding by remember { mutableStateOf(printerBindingFrom(code, null)) }
    LaunchedEffect(code) {
        binding = printerBindingFrom(code, null)
        while (true) {
            binding = runCatching { loadPrinterBinding(context, code) }.getOrDefault(binding)
            delay(60_000)
        }
    }
    val missing = !binding.isSet
    Surface(
        color = if (missing && !quiet) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.surfaceVariant,
        modifier = Modifier.fillMaxWidth().clickable(onClick = onOpenPrinters),
    ) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (!missing) {
                PrinterStateDot(binding.online)
                Spacer(Modifier.width(8.dp))
            }
            Text(
                if (missing && quiet) "Etiket yazıcısı seçin" else if (missing) "Etiket yazıcısı seçilmedi" else "Etiket yazıcısı",
                fontSize = 12.sp,
                color = if (missing && !quiet) MaterialTheme.colorScheme.onErrorContainer else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (!missing) {
                Spacer(Modifier.width(8.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        binding.name.ifBlank { binding.code },
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                    )
                    if (binding.code.isNotBlank() && binding.name.isNotBlank()) Text(
                        binding.code,
                        fontSize = 10.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                    )
                }
            } else {
                Spacer(Modifier.weight(1f))
            }
            Text("›", fontSize = 18.sp, color = MaterialTheme.colorScheme.primary)
        }
    }
}

/**
 * The whole printers screen for a customer terminal: one card per usage,
 * nothing else. Selection either comes from BC (terminal card) or, when
 * [onChange] is given, from the classic list behind "Değiştir".
 */
@Composable
internal fun TerminalPrintersScreen(onChange: (() -> Unit)?) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val labelCode = rememberDevicePrinter(PRINTER_USAGE_LABEL)
    val documentCode = rememberDevicePrinter(PRINTER_USAGE_DOCUMENT)
    var label by remember { mutableStateOf(printerBindingFrom(labelCode, null)) }
    var document by remember { mutableStateOf(printerBindingFrom(documentCode, null)) }
    var loading by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var printing by remember { mutableStateOf(false) }

    suspend fun refresh() {
        loading = true
        label = runCatching { loadPrinterBinding(context, labelCode) }.getOrDefault(printerBindingFrom(labelCode, null))
        document = runCatching { loadPrinterBinding(context, documentCode) }.getOrDefault(printerBindingFrom(documentCode, null))
        loading = false
    }
    LaunchedEffect(labelCode, documentCode) { refresh() }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Terminal: ${WmsTerminalSession.code(context).ifBlank { "Seçilmedi" }}", fontWeight = FontWeight.Bold)
        PrinterBindingCard(
            title = "Etiket yazıcısı",
            binding = label,
            onSelect = onChange,
            onTest = if (label.isSet) ({
                scope.launch {
                    val r = BcApi.boundAction(context, "printers", label.code, "testPrint", "{}")
                    status = if (r.ok) "Test etiketi ${label.title} yazıcısına gönderildi." else "HATA: ${BcApi.errorMessage(r.body)}"
                }
            }) else null,
        )
        if (labelCode.isNotBlank()) {
            TextButton(onClick = {
                scope.launch {
                    val result = selectTerminalPrinter(context, "", PRINTER_USAGE_LABEL)
                    status = if (result.isSuccess) "Etiket yazıcısı terminalden ve BC'den kaldırıldı."
                    else "HATA: ${result.exceptionOrNull()?.message.orEmpty()}"
                }
            }) { Text("Etiket seçimini kaldır") }
            OutlinedButton(enabled = !printing && !loading, onClick = {
                printing = true
                scope.launch {
                    try {
                        val result = BcApi.boundAction(context, "printers", labelCode, "printNameLabel", "{}")
                        status = if (result.ok) "Yazıcı ad etiketi ${label.title} yazıcısının kuyruğuna eklendi."
                            else "HATA: ${BcApi.errorMessage(result.body)}"
                    } finally { printing = false }
                }
            }) { Text(if (printing) "Gönderiliyor…" else "Yazıcı ad etiketi çıkar") }
        }
        PrinterBindingCard(title = "Belge yazıcısı", binding = document, onTest = null, onSelect = onChange)
        if (documentCode.isNotBlank()) TextButton(onClick = {
            scope.launch {
                val result = selectTerminalPrinter(context, "", PRINTER_USAGE_DOCUMENT)
                status = if (result.isSuccess) "Belge yazıcısı terminalden ve BC'den kaldırıldı."
                else "HATA: ${result.exceptionOrNull()?.message.orEmpty()}"
            }
        }) { Text("Belge seçimini kaldır") }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { scope.launch { refresh() } }, enabled = !loading) { Text(if (loading) "..." else "Yenile") }
            if (onChange != null) TextButton(onClick = onChange) { Text("Değiştir") }
        }
        if (status.isNotBlank()) Text(status, fontSize = 12.sp, color = if (status.startsWith("HATA")) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
        if (onChange == null) Text(
            "Yazıcılar BC'deki terminal kartından gelir; değişince yeniden giriş yapın.",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun PrinterBindingCard(title: String, binding: PrinterBinding, onTest: (() -> Unit)?, onSelect: (() -> Unit)? = null) {
    Card(Modifier.fillMaxWidth().then(if (onSelect != null) Modifier.clickable(onClick = onSelect) else Modifier), shape = RoundedCornerShape(14.dp)) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(title, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    if (binding.isSet) binding.name.ifBlank { binding.code } else "Seçilmedi",
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (binding.isSet) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.error,
                )
                if (binding.isSet && binding.name.isNotBlank()) Text(
                    binding.code,
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (binding.isSet) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        PrinterStateDot(binding.online, 8.dp)
                        Spacer(Modifier.width(6.dp))
                        Text(
                            when (binding.online) {
                                true -> "Çevrimiçi"
                                false -> "Çevrimdışı"
                                null -> "Durum bilinmiyor"
                            } + (if (binding.lastSeen.isNotBlank()) " · $binding.lastSeen" else ""),
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            if (onTest != null) OutlinedButton(onClick = onTest) { Text("Test") }
        }
    }
}
