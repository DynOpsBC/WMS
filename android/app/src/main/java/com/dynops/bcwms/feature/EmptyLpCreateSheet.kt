package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.BuildConfig
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.StatusText
import com.dynops.bcwms.ui.WmsActionLabel
import com.dynops.bcwms.ui.WmsGlyph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

// Kitoko (22 Eki 2026): "boş bir LP oluşturmak istiyorum". Taşıma Kabı ekranında
// lokasyon (+ isteğe bağlı raf), LP şablonu ve adet seçilir; BC'de mevcut
// POST licensePlates (LP Management.Build) ile boş LP'ler açılır, ardından
// tümünün LP etiketi etiket yazıcısına sırayla basılabilir.

internal const val EMPTY_LP_MAX = 50
private const val EMPTY_LP_PREFS = "dopswhs_empty_lp"
private const val EMPTY_LP_LAST_LOCATION = "lastLocation"
private const val EMPTY_LP_LAST_TEMPLATE = "lastTemplate"

/** Boş LP oluşturma düğmesi yalnız Kitoko'da; BADE/EMU LP ekranı aynen kalır. */
internal fun emptyLpCreateOffered(flavor: String = BuildConfig.FLAVOR): Boolean =
    flavor.equals("kitoko", ignoreCase = true)

/** Adet 1..50; geçersizse null. */
internal fun parseEmptyLpCount(text: String): Int? =
    text.trim().toIntOrNull()?.takeIf { it in 1..EMPTY_LP_MAX }

/** POST licensePlates gövdesi; raf boşsa gönderilmez (LP raf atanmadan açılır). */
internal fun emptyLpCreatePayload(templateCode: String, locationCode: String, binCode: String): String =
    JSONObject().apply {
        put("templateCode", templateCode.trim())
        put("locationCode", locationCode.trim())
        if (binCode.isNotBlank()) put("binCode", binCode.trim())
    }.toString()

/**
 * Varsayılan lokasyon: kullanıcının BC'deki varsayılanı → bu cihazda son seçilen →
 * tek lokasyon varsa o. Seçenek listesinde olmayan kod önerilmez.
 */
internal fun emptyLpDefaultLocation(userDefault: String, lastUsed: String, options: List<BulkLpLocationOption>): String {
    fun known(code: String) = options.firstOrNull { it.code.equals(code.trim(), ignoreCase = true) }?.code
    return known(userDefault) ?: known(lastUsed) ?: options.singleOrNull()?.code.orEmpty()
}

/** Varsayılan şablon: son seçilen (listede varsa) → PALLET politikası (resolveLpTemplate ile aynı). */
internal fun emptyLpDefaultTemplate(rows: List<Pair<String, String>>, lastUsed: String): String =
    rows.firstOrNull { it.first.equals(lastUsed.trim(), ignoreCase = true) && lastUsed.isNotBlank() }?.first
        ?: chooseLpTemplate(rows, LpPurpose.PALLET).orEmpty()

internal fun emptyLpCreateStatus(created: List<String>, requested: Int, error: String): String = when {
    error.isBlank() -> "TAMAM: ${created.size} boş LP oluşturuldu: ${created.joinToString(", ")}"
    created.isEmpty() -> "HATA: LP oluşturulamadı: $error"
    else -> "UYARI: $requested LP'den ${created.size} tanesi oluşturuldu (${created.joinToString(", ")}); kalanı oluşturulamadı: $error"
}

internal data class EmptyLpCreateResult(val created: List<String>, val error: String)

/** LP'leri sırayla açar; ilk hatada durur (kısmi sonuç geri döner, çift LP üretilmez). */
internal suspend fun createEmptyLps(
    context: Context,
    templateCode: String,
    locationCode: String,
    binCode: String,
    count: Int,
    onProgress: (done: Int) -> Unit = {},
): EmptyLpCreateResult {
    val created = mutableListOf<String>()
    val body = emptyLpCreatePayload(templateCode, locationCode, binCode)
    repeat(count) {
        val r = try {
            BcApi.post(context, "licensePlates", body)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            BcApi.ApiResult(false, -1, error.message.orEmpty())
        }
        if (!r.ok) {
            val message = if (r.httpCode == -1) r.body.ifBlank { "bağlantı hatası" }
                else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode).removePrefix("HATA: ")
            return EmptyLpCreateResult(created, message)
        }
        val no = runCatching { JSONObject(r.body).optString("no") }.getOrDefault("").trim()
        if (no.isBlank()) return EmptyLpCreateResult(created, "BC yanıtında LP numarası yok; LP listesini yenileyip kontrol edin.")
        created += no
        onProgress(created.size)
    }
    return EmptyLpCreateResult(created, "")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun EmptyLpCreateSheet(
    onDismiss: () -> Unit,
    onCreated: (created: List<String>, status: String) -> Unit,
    onPrint: (List<String>) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val prefs = remember { context.getSharedPreferences(EMPTY_LP_PREFS, Context.MODE_PRIVATE) }
    var locations by remember { mutableStateOf<List<BulkLpLocationOption>>(emptyList()) }
    var location by remember { mutableStateOf("") }
    var locationMenu by remember { mutableStateOf(false) }
    var templates by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var template by remember { mutableStateOf("") }
    var templateMenu by remember { mutableStateOf(false) }
    var bin by remember { mutableStateOf("") }
    var bins by remember { mutableStateOf<List<String>>(emptyList()) }
    var count by remember { mutableStateOf("1") }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var created by remember { mutableStateOf<List<String>>(emptyList()) }

    LaunchedEffect(Unit) {
        busy = true
        status = "Lokasyonlar ve LP şablonları yükleniyor..."
        val locPage = BcApi.getAllPagesWithStandardFallback(context, "locations?\$top=200&\$orderby=code")
        locations = if (locPage.complete) bulkLpLocationOptions(locPage.rows) else emptyList()
        val user = BcApi.getLocalUser(context).trim()
        val userDefault = if (user.isBlank()) "" else {
            val r = BcApi.get(context, "localUsers('${user.replace("'", "''")}')?\$select=defaultLocationCode,defaultBinCode")
            if (r.ok) runCatching { JSONObject(r.body).optString("defaultLocationCode") }.getOrDefault("") else ""
        }
        location = emptyLpDefaultLocation(userDefault, prefs.getString(EMPTY_LP_LAST_LOCATION, "").orEmpty(), locations)
        val tplPage = BcApi.getAllPages(context, "licensePlateTemplates?\$top=100&\$select=code,description")
        templates = if (tplPage.complete) tplPage.rows.map { it.optString("code").trim() to it.optString("description") }
            .filter { it.first.isNotBlank() } else emptyList()
        template = emptyLpDefaultTemplate(templates, prefs.getString(EMPTY_LP_LAST_TEMPLATE, "").orEmpty())
        busy = false
        status = when {
            !locPage.complete -> "HATA: Lokasyon listesi alınamadı. Kapatıp yeniden açın."
            !tplPage.complete -> "HATA: LP şablonları alınamadı. Kapatıp yeniden açın."
            templates.isEmpty() -> "HATA: BC'de LP şablonu yok. WMS Kurulum'dan şablon ekleyin."
            else -> ""
        }
    }

    fun loadBins() {
        val loc = location.trim()
        if (loc.isBlank()) { status = "Önce lokasyon seçin."; return }
        scope.launch {
            busy = true
            val page = BcApi.getAllPages(context, "bins?\$filter=locationCode eq '${loc.replace("'", "''")}'&\$top=200&\$select=code")
            busy = false
            bins = if (page.complete) page.rows.map { it.optString("code") }.filter { it.isNotBlank() }.sortedWith(warehouseBinCodeComparator) else emptyList()
            status = when {
                !page.complete -> "HATA: Raf listesi alınamadı."
                bins.isEmpty() -> "⚠️ $loc lokasyonunda raf yok — raf boş bırakılabilir."
                else -> ""
            }
        }
    }

    fun create() {
        val n = parseEmptyLpCount(count) ?: run { status = "HATA: Adet 1 ile $EMPTY_LP_MAX arasında olmalı."; return }
        if (location.isBlank()) { status = "HATA: Lokasyon seçin."; return }
        if (template.isBlank()) { status = "HATA: LP şablonu seçin."; return }
        if (busy) return
        busy = true
        scope.launch {
            try {
                val result = createEmptyLps(context, template, location, bin, n) { done -> status = "LP oluşturuluyor: $done/$n" }
                created = result.created
                prefs.edit().putString(EMPTY_LP_LAST_LOCATION, location).putString(EMPTY_LP_LAST_TEMPLATE, template).apply()
                status = emptyLpCreateStatus(result.created, n, result.error)
                if (result.created.isNotEmpty()) onCreated(result.created, status)
            } finally {
                busy = false
            }
        }
    }

    ModalBottomSheet(onDismissRequest = { if (!busy) onDismiss() }) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Boş LP Oluştur", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            if (created.isEmpty()) {
                Text(
                    "İçi boş LP açılır; ürün sonra eklenir ya da taşıma/ mal kabulde kullanılır.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                // Lokasyon
                Box {
                    OutlinedButton(
                        onClick = { locationMenu = true },
                        enabled = !busy && locations.isNotEmpty(),
                        modifier = Modifier.fillMaxWidth().testTag("empty-lp-location"),
                    ) {
                        Text("Lokasyon: " + (locations.firstOrNull { it.code == location }?.label ?: location.ifBlank { "seçin" }))
                    }
                    DropdownMenu(expanded = locationMenu, onDismissRequest = { locationMenu = false }) {
                        locations.forEach { option ->
                            DropdownMenuItem(text = { Text(option.label) }, onClick = {
                                locationMenu = false
                                if (option.code != location) { location = option.code; bin = ""; bins = emptyList() }
                            })
                        }
                    }
                }
                // Raf (isteğe bağlı): okut ya da listeden seç
                ScanField(
                    label = "Raf (isteğe bağlı) — okutun ya da listeden seçin",
                    value = bin,
                    onValueChange = { bin = it },
                    modifier = Modifier.fillMaxWidth(),
                    onScanned = { bin = BarcodeIntentResolver.resolve(it).value },
                    enabled = !busy,
                    okButton = false,
                    autoFocus = true,
                    onClear = { bin = "" },
                )
                OutlinedButton(onClick = { loadBins() }, enabled = !busy && location.isNotBlank(), modifier = Modifier.fillMaxWidth()) {
                    Text("📋 $location raflarını listele")
                }
                if (bins.isNotEmpty()) Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    bins.take(100).forEach { code ->
                        FilterChip(selected = code.equals(bin, true), onClick = { bin = code }, label = { Text(code) })
                    }
                }
                // Şablon
                Box {
                    OutlinedButton(
                        onClick = { templateMenu = true },
                        enabled = !busy && templates.isNotEmpty(),
                        modifier = Modifier.fillMaxWidth().testTag("empty-lp-template"),
                    ) {
                        val desc = templates.firstOrNull { it.first == template }?.second.orEmpty()
                        Text("LP şablonu: " + template.ifBlank { "seçin" } + if (desc.isNotBlank()) " · $desc" else "")
                    }
                    DropdownMenu(expanded = templateMenu, onDismissRequest = { templateMenu = false }) {
                        templates.forEach { (code, description) ->
                            DropdownMenuItem(
                                text = { Text(if (description.isBlank()) code else "$code · $description") },
                                onClick = { templateMenu = false; template = code },
                            )
                        }
                    }
                }
                // Adet
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Adet (1–$EMPTY_LP_MAX)", modifier = Modifier.weight(1f))
                    IconButton(enabled = !busy && (parseEmptyLpCount(count) ?: 1) > 1, onClick = {
                        count = ((parseEmptyLpCount(count) ?: 1) - 1).coerceAtLeast(1).toString()
                    }) { Text("−", fontSize = 22.sp, fontWeight = FontWeight.Bold) }
                    OutlinedTextField(
                        value = count,
                        onValueChange = { v -> count = v.filter(Char::isDigit).take(2) },
                        singleLine = true,
                        enabled = !busy,
                        modifier = Modifier.width(72.dp).testTag("empty-lp-count"),
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                            keyboardType = androidx.compose.ui.text.input.KeyboardType.Number,
                        ),
                    )
                    IconButton(enabled = !busy && (parseEmptyLpCount(count) ?: 0) < EMPTY_LP_MAX, onClick = {
                        count = ((parseEmptyLpCount(count) ?: 0) + 1).coerceAtMost(EMPTY_LP_MAX).toString()
                    }) { Text("+", fontSize = 22.sp, fontWeight = FontWeight.Bold) }
                }
                StatusText(status)
                Button(
                    onClick = { create() },
                    enabled = !busy && location.isNotBlank() && template.isNotBlank() && parseEmptyLpCount(count) != null,
                    modifier = Modifier.fillMaxWidth().height(54.dp).testTag("empty-lp-create"),
                    shape = RoundedCornerShape(14.dp),
                ) {
                    WmsActionLabel(WmsGlyph.LICENSE_PLATE,
                        if (busy) "Oluşturuluyor..." else "${parseEmptyLpCount(count) ?: ""} Boş LP Oluştur")
                }
                TextButton(onClick = onDismiss, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Vazgeç") }
            } else {
                // Sonuç: oluşan LP numaraları + hemen etiket
                StatusText(status)
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text("Oluşturulan LP'ler (${created.size})", fontWeight = FontWeight.SemiBold)
                        Spacer(Modifier.height(4.dp))
                        Text(created.joinToString("  ·  "), fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        Text("$location${if (bin.isNotBlank()) " / $bin" else ""} · $template", fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                Button(
                    onClick = { onPrint(created) },
                    modifier = Modifier.fillMaxWidth().height(54.dp).testTag("empty-lp-print"),
                    shape = RoundedCornerShape(14.dp),
                ) { WmsActionLabel(WmsGlyph.PRINTER, "LP Etiketi Yazdır (${created.size})") }
                OutlinedButton(onClick = { created = emptyList(); status = "" }, modifier = Modifier.fillMaxWidth()) {
                    Text("Yeni Boş LP Oluştur")
                }
                TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text("Kapat") }
            }
        }
    }
}
