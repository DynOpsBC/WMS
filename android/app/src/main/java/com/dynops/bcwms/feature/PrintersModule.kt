package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.BuildConfig
import com.dynops.bcwms.shouldForceProductionFlow
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.EmptyState
import com.dynops.bcwms.ui.InfoPill
import com.dynops.bcwms.ui.StatusText
import com.dynops.bcwms.ui.WmsGlyph
import com.dynops.bcwms.ui.WmsIcon
import com.dynops.bcwms.ui.WmsRefreshLabel
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Printers module — view agent-discovered printers and set the default printer
 * for this device (per-usage). The selection is stored in SharedPreferences
 * under `bcwms.printer.<usage>` and consumed by LP/Pick/Ship print buttons.
 */

private const val PREF_NAMESPACE = "bcwms.printer."
const val PRINTER_USAGE_LABEL = "LpLabel"
const val PRINTER_USAGE_DOCUMENT = "Document"

private fun printerPreferenceKey(context: Context, usage: String): String {
    val terminal = TerminalSession.code(context)
    if (terminal.isBlank()) return PREF_NAMESPACE + usage
    return PREF_NAMESPACE + terminalPreferenceScope(BcApi.getTenant(context), BcApi.getEnvironment(context), BcApi.getCompanyId(context)) + ":" + terminal + ":" + usage
}

fun getDefaultPrinter(context: Context, usage: String = PRINTER_USAGE_LABEL): String {
    return context.getSharedPreferences("bcwms_prefs", Context.MODE_PRIVATE)
        .getString(printerPreferenceKey(context, usage), "") ?: ""
}

fun setDefaultPrinter(context: Context, code: String, usage: String = PRINTER_USAGE_LABEL) {
    context.getSharedPreferences("bcwms_prefs", Context.MODE_PRIVATE)
        .edit().putString(printerPreferenceKey(context, usage), code)
        .putBoolean(printerPreferenceKey(context, usage) + ".localSelection", true).apply()
}

/** BC is authoritative after terminal-side selections have been saved through its API. */
internal fun applyTerminalPrinterDefault(context: Context, code: String, usage: String) {
    val prefs = context.getSharedPreferences("bcwms_prefs", Context.MODE_PRIVATE)
    val key = printerPreferenceKey(context, usage)
    prefs.edit().putString(key, code).remove(key + ".localSelection").apply()
}

/** MTE / LP material labels: the device's label printer, else its document printer, else BC mapping. */
fun getMtePrinter(context: Context): String =
    mtePrinterCode(getDefaultPrinter(context, PRINTER_USAGE_LABEL), getDefaultPrinter(context, PRINTER_USAGE_DOCUMENT))

internal data class InquiryPrinterChoice(val printerCode: String, val warning: String)

/**
 * The device's label printer is used as selected; its BC record is only checked
 * to warn the operator. Falls back to the document printer when no label
 * printer is selected, and to BC's device mapping when neither is.
 */
internal suspend fun resolveInquiryPrinter(context: Context): Result<InquiryPrinterChoice> = runCatching {
    val label = getDefaultPrinter(context)
    val document = getDefaultPrinter(context, PRINTER_USAGE_DOCUMENT)
    if (label.isBlank()) return@runCatching InquiryPrinterChoice(document, "")
    val escaped = label.replace("'", "''")
    val response = BcApi.get(context, "printers?\$filter=code eq '$escaped'&\$top=1")
    // An unavailable API is not evidence of an inactive printer: print anyway.
    val available = if (!response.ok) true else runCatching {
        val data = JSONObject(response.body).getJSONArray("value")
        val printer = if (data.length() == 0) null else data.getJSONObject(0)
        printer != null && printer.optBoolean("active", true) && printer.optString("format").equals("ZPL", true)
    }.getOrDefault(true)
    InquiryPrinterChoice(inquiryLabelPrinter(label, document), inquiryLabelWarning(label, available))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrintersModule() {
    val context = LocalContext.current
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var defaultLabelCode by remember { mutableStateOf(getDefaultPrinter(context, PRINTER_USAGE_LABEL)) }
    var defaultDocumentCode by remember { mutableStateOf(getDefaultPrinter(context, PRINTER_USAGE_DOCUMENT)) }
    var scannedBarcode by rememberSaveable { mutableStateOf("") }
    var barcodePrintBusy by remember { mutableStateOf(false) }
    val productionCustomer = shouldForceProductionFlow(BuildConfig.FLAVOR)
    val terminalManaged = BuildConfig.FLAVOR == "bade" && TerminalSession.code(context).isNotBlank()

    fun saveTerminalPrinter(code: String, usage: String, displayName: String = "") {
        if (loading || saving) return
        if (!TerminalSession.authenticated(context)) {
            status = "UYARI: Yazıcı ayarı için PIN ile giriş yapın."
            return
        }
        val terminal = TerminalSession.code(context)
        val terminalScope = TerminalSession.scope(context)
        saving = true
        status = "Yazıcı BC'ye kaydediliyor..."
        scope.launch {
            try {
                val response = BcApi.boundAction(context, "wmsTerminals", terminal, "selectPrinter",
                    JSONObject().put("username", BcApi.getLocalUser(context))
                        .put("usage", usage).put("printerCode", code).toString())
                val selection = if (response.ok) parseTerminalPrinterSelection(response.body, terminal, true) else null
                if (selection == null) {
                    status = if (response.httpCode == 404) "HATA: BC uzantısını 1.14.1.58 veya üstüne güncelleyin. Yazıcı kaydedilmedi."
                        else "HATA: Yazıcı BC'ye kaydedilemedi. Bağlantıyı ve yetkinizi kontrol edip yenileyin."
                    return@launch
                }
                if (terminalScope != TerminalSession.scope(context) || terminal != TerminalSession.code(context)) return@launch
                applyTerminalPrinterDefault(context, selection.label, PRINTER_USAGE_LABEL)
                applyTerminalPrinterDefault(context, selection.document, PRINTER_USAGE_DOCUMENT)
                defaultLabelCode = selection.label
                defaultDocumentCode = selection.document
                status = if (code.isBlank()) "TAMAM: ${if (usage == PRINTER_USAGE_LABEL) "Etiket" else "Belge"} yazıcısı seçimi terminalden ve BC'den kaldırıldı."
                else "TAMAM: $displayName seçildi ve BC terminal kaydına kaydedildi."
            } finally { saving = false }
        }
    }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            if (terminalManaged) {
                val terminal = TerminalSession.code(context)
                val terminalScope = TerminalSession.scope(context)
                val key = java.net.URLEncoder.encode(terminal.replace("'", "''"), "UTF-8").replace("+", "%20")
                val response = BcApi.get(context, "wmsTerminals('$key')")
                val selection = if (response.ok) parseTerminalPrinterSelection(response.body, terminal, false) else null
                if (selection == null || terminalScope != TerminalSession.scope(context) || terminal != TerminalSession.code(context)) {
                    loading = false
                    status = "HATA: BC terminal yazıcı ayarları alınamadı. Yenileyip tekrar deneyin."
                    return@launch
                }
                applyTerminalPrinterDefault(context, selection.label, PRINTER_USAGE_LABEL)
                applyTerminalPrinterDefault(context, selection.document, PRINTER_USAGE_DOCUMENT)
                defaultLabelCode = selection.label
                defaultDocumentCode = selection.document
            }
            val page = BcApi.getAllPages(context, "printers?\$top=100&\$orderby=code")
            loading = false
            rows = if (page.complete) page.rows else emptyList()
            // Ajan yazıcıyı yeni kodla yeniden eşitlediğinde telefonda kayıtlı
            // eski kod sessizce geçersiz kalıyor ve her baskı BC'den
            // "Printer X is not registered" ile dönüyordu.
            val codes = rows.map { it.optString("code") }.toSet()
            val stale = listOfNotNull(
                defaultLabelCode.takeIf { it.isNotBlank() && it !in codes }?.let { "etiket ($it)" },
                defaultDocumentCode.takeIf { it.isNotBlank() && it !in codes }?.let { "belge ($it)" },
            )
            status = if (!page.complete) "HATA: Yazıcı listesinin tamamı alınamadı. Windows yazıcı ajanının bağlantısını kontrol edin."
                else if (rows.isEmpty()) "Henüz eşitlenmiş yazıcı yok. Windows ajanında Yazıcıları Yenile ve Buluta Eşitle'yi çalıştırın."
                else if (stale.isNotEmpty()) "UYARI: Kayıtlı ${stale.joinToString(" ve ")} yazıcısı listede yok. Aşağıdan yeniden seçin."
                else printerReadinessMessage(rows)
        }
    }
    LaunchedEffect(Unit) { load() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            WmsIcon(WmsGlyph.PRINTER, MaterialTheme.colorScheme.primary, Modifier.size(24.dp))
            Spacer(Modifier.width(8.dp))
            Text("Yazıcılar", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        }
        Text(
            if (terminalManaged) TerminalSession.code(context) else "Bu terminalin yazıcısını seçin.",
            fontSize = 12.sp, color = Color.Gray
        )
        if (terminalManaged) {
            Text("Etiket: ${defaultLabelCode.ifBlank { "Seçilmemiş" }}", fontWeight = FontWeight.Medium)
            Text("Belge: ${defaultDocumentCode.ifBlank { "Seçilmemiş" }}", fontWeight = FontWeight.Medium)
        }
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { load() }, enabled = !loading && !saving) { WmsRefreshLabel(loading) }
        }
        if (terminalManaged) {
            if (defaultLabelCode.isNotBlank()) {
                TextButton(onClick = { saveTerminalPrinter("", PRINTER_USAGE_LABEL) }, enabled = !loading && !saving) {
                    Text("Etiket seçimini kaldır")
                }
            }
            if (defaultDocumentCode.isNotBlank()) {
                TextButton(onClick = { saveTerminalPrinter("", PRINTER_USAGE_DOCUMENT) }, enabled = !loading && !saving) {
                    Text("Belge seçimini kaldır")
                }
            }
        }
        if (defaultLabelCode.isNotBlank() && !terminalManaged) {
            TextButton(onClick = {
                setDefaultPrinter(context, "", PRINTER_USAGE_LABEL)
                defaultLabelCode = ""
                status = "Etiket seçimi kaldırıldı. Ürün/Raf Sorgu için Belge yazıcısı kullanılacak."
            }) { Text("Etiket seçimini kaldır") }
        }
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!productionCustomer) item {
                Card(
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
                ) {
                    Column(Modifier.padding(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            WmsIcon(WmsGlyph.SCAN, MaterialTheme.colorScheme.primary, Modifier.size(22.dp))
                            Spacer(Modifier.width(8.dp))
                            Text("Barkod Baskı Testi", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                        }
                        Text(
                            "Barkodu okutun; okunan numara aşağıda görünür ve seçili belge yazıcısına PDF olarak basılır.",
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.75f),
                        )
                        Spacer(Modifier.height(8.dp))
                        ScanField(
                            label = "Barkodu okut",
                            value = scannedBarcode,
                            onValueChange = { scannedBarcode = it },
                            modifier = Modifier.fillMaxWidth(),
                            onScanned = { raw ->
                                scannedBarcode = raw.trim()
                                status = "Okunan barkod: ${raw.trim()}"
                                keyboardController?.hide()
                            },
                        )
                        if (scannedBarcode.isNotBlank()) {
                            Spacer(Modifier.height(8.dp))
                            Surface(
                                color = MaterialTheme.colorScheme.surface,
                                shape = RoundedCornerShape(8.dp),
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Column(Modifier.padding(10.dp)) {
                                    Text("OKUNAN NUMARA", fontSize = 11.sp, color = Color.Gray)
                                    Text(
                                        scannedBarcode,
                                        fontFamily = FontFamily.Monospace,
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 20.sp,
                                    )
                                }
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        Button(
                            onClick = {
                                keyboardController?.hide()
                                focusManager.clearFocus(force = true)
                                scope.launch {
                                    barcodePrintBusy = true
                                    val payload = JSONObject().apply {
                                        put("barcodeValue", scannedBarcode.trim())
                                        put("copies", 1)
                                    }.toString()
                                    val result = BcApi.boundAction(
                                        context,
                                        "printers",
                                        defaultDocumentCode,
                                        "printBarcodeTest",
                                        payload,
                                    )
                                    barcodePrintBusy = false
                                    status = if (result.ok) {
                                        val jobId = runCatching { JSONObject(result.body).optInt("value") }.getOrDefault(0)
                                        if (jobId > 0) "Barkod $scannedBarcode, iş $jobId olarak Azure'a gönderildi."
                                        else "Barkod $scannedBarcode Azure'a gönderildi."
                                    } else {
                                        "HATA: ${result.body.take(180)}"
                                    }
                                }
                            },
                            enabled = !barcodePrintBusy && scannedBarcode.trim().length in 1..100 && defaultDocumentCode.isNotBlank(),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(if (barcodePrintBusy) "Gönderiliyor..." else "🖨 Belge Yazıcısına Yazdır")
                        }
                        if (defaultDocumentCode.isBlank()) {
                            Text("Önce aşağıdaki PDF yazıcısında Belge düğmesine basın.", fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
                        } else {
                            Text("Belge yazıcısı: $defaultDocumentCode", fontSize = 11.sp, color = Color.Gray)
                        }
                    }
                }
            }
            if (rows.isEmpty() && !loading) item { EmptyState("Kayıtlı yazıcı yok. Windows Print Agent'ta yazıcıları yenileyip Buluta Eşitle'yi çalıştırın.") }
            items(rows) { row ->
                val code = row.optString("code")
                val desc = row.optString("description")
                val format = row.optString("format").trim().uppercase()
                val handle = row.optString("printerHandle").ifBlank { row.optString("hostname") }
                val active = row.optBoolean("active", true)
                val agentStatus = row.optString("agentStatus")
                val stationId = row.optString("stationId")
                val isLabelDefault = defaultLabelCode == code
                val isDocumentDefault = defaultDocumentCode == code
                fun selectPrinter(usage: String) {
                    if (loading || saving) return
                    val issue = if (usage == PRINTER_USAGE_LABEL) labelPrinterSelectionIssue(active, format)
                        else if (!active) "Yazıcı pasif."
                        else if (format != "PDF") "Belge yazıcısı PDF formatında olmalı." else null
                    if (issue != null) {
                        status = "UYARI: $code seçilemedi. $issue"
                        return
                    }
                    saveTerminalPrinter(code, usage, desc.ifBlank { code })
                }
                Card(
                    modifier = Modifier.fillMaxWidth().then(
                        if (terminalManaged) Modifier.clickable(enabled = !loading && !saving) {
                            selectPrinter(if (format == "PDF") PRINTER_USAGE_DOCUMENT else PRINTER_USAGE_LABEL)
                        } else Modifier
                    ),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Column(Modifier.padding(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(code, fontWeight = FontWeight.Bold)
                            Spacer(Modifier.width(8.dp))
                            if (isLabelDefault) InfoPill("Etiket")
                            if (isDocumentDefault) {
                                Spacer(Modifier.width(4.dp))
                                InfoPill("Belge")
                            }
                            if (!active) {
                                Spacer(Modifier.width(4.dp))
                                InfoPill(
                                    "Pasif",
                                    containerColor = MaterialTheme.colorScheme.errorContainer,
                                    contentColor = MaterialTheme.colorScheme.onErrorContainer,
                                )
                            }
                            if (agentStatus.isNotBlank() && !productionCustomer) {
                                Spacer(Modifier.width(4.dp))
                                InfoPill("Bağlantı $agentStatus")
                            }
                        }
                        Text(
                            if (productionCustomer) "$desc · ${if (format == "ZPL") "Etiket yazıcısı" else "Belge yazıcısı"}"
                            else "$desc · $format · ${handle.ifBlank { "-" }}",
                            fontSize = 12.sp,
                            color = Color.Gray,
                        )
                        if (!productionCustomer && stationId.isNotBlank()) Text(stationId, fontSize = 11.sp, color = Color.Gray)
                        Spacer(Modifier.height(8.dp))
                        if (terminalManaged) {
                            OutlinedButton(onClick = {
                                selectPrinter(if (format == "PDF") PRINTER_USAGE_DOCUMENT else PRINTER_USAGE_LABEL)
                            }, enabled = !loading && !saving && active && format in setOf("ZPL", "PDF")) {
                                Text(if (isLabelDefault || isDocumentDefault) "✓ Seçili" else "Bu yazıcıyı seç")
                            }
                        }
                        if (!terminalManaged) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            OutlinedButton(
                                onClick = {
                                    val issue = labelPrinterSelectionIssue(active, format)
                                    if (issue == null) {
                                        setDefaultPrinter(context, code, PRINTER_USAGE_LABEL)
                                        defaultLabelCode = code
                                        status = "TAMAM: $code etiket yazıcısı olarak seçildi."
                                    } else {
                                        status = "UYARI: $code seçilemedi. $issue"
                                    }
                                },
                            ) { Text(if (isLabelDefault) "✓ Etiket" else "Etiket", fontSize = 12.sp) }
                            OutlinedButton(
                                onClick = {
                                    if (active && format == "PDF") {
                                        setDefaultPrinter(context, code, PRINTER_USAGE_DOCUMENT)
                                        defaultDocumentCode = code
                                        status = "TAMAM: $code belge yazıcısı olarak seçildi."
                                    } else {
                                        val reason = if (!active) "Yazıcı pasif."
                                        else "Belge seçimi yalnızca PDF yazıcılarda kullanılabilir; bu yazıcının formatı $format."
                                        status = "UYARI: $code seçilemedi. $reason"
                                    }
                                },
                            ) { Text(if (isDocumentDefault) "✓ Belge" else "Belge", fontSize = 12.sp) }
                        }
                        if (!productionCustomer) {
                            Spacer(Modifier.height(6.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                OutlinedButton(onClick = {
                                    scope.launch {
                                        val r = BcApi.boundAction(context, "printers", code, "testPrint", "{}")
                                        status = if (r.ok) "Test yazdırma işi ${code} kuyruğa alındı." else "HATA: ${r.body.take(140)}"
                                    }
                                }, enabled = active && format == "ZPL") { Text("🧪 ZPL Test", fontSize = 12.sp) }
                            }
                        }
                    }
                }
            }
        }
    }
}

internal fun printerReadinessMessage(rows: List<org.json.JSONObject>): String {
    val activeCount = rows.count { it.optBoolean("active", true) }
    return if (activeCount == 0) "UYARI: ${rows.size} kayıtlı yazıcı var ancak aktif yazıcı yok. Yazıcı ayarlarını kontrol edin."
    else "TAMAM: $activeCount aktif yazıcı listelendi · ${rows.size - activeCount} pasif."
}

internal fun labelPrinterSelectionIssue(active: Boolean, format: String): String? = when {
    !active -> "Yazıcı pasif. Windows yazıcı ajanında etkinleştirip listeyi yenileyin."
    format.trim().uppercase() != "ZPL" ->
        "Etiket seçimi yalnızca ZPL yazıcılarda kullanılabilir; bu yazıcının formatı ${format.ifBlank { "bilinmiyor" }}."
    else -> null
}
