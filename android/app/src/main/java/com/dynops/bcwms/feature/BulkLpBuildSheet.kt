package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.StatusText
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

// Older clients/tests still use this empty-LP payload contract. The active
// BADE screen below uses the ledger-based contract.
internal data class BulkLpBuildDraft(val id: Int, val quantity: String)

internal data class LedgerBulkLpBuildResult(
    val createdLpNos: List<String>,
    val failedPrintLpNos: List<String>,
    val replayed: Boolean,
    val printSkippedOnReplay: Boolean,
)

internal data class PendingLedgerBulkLpRequest(
    val entryNo: Int,
    val expectedCount: Int,
    val printLabels: Boolean,
    val requestId: String,
    val body: String,
)

internal enum class LedgerBulkLpReplayState {
    FirstExecution,
    Replayed,
    ReplayedWithPrintSkipped,
    Invalid,
}

private const val DEFAULT_LEDGER_LP_COUNT = "10"
private const val DEFAULT_LEDGER_LP_QUANTITY = "100"
private const val LEDGER_ENTRY_DISPLAY_LIMIT = 50
internal const val LEDGER_BULK_LP_CREATE_ACTION = "createLicensePlatesIdempotent"
private const val LEDGER_BULK_LP_PENDING_PREFS = "bcwms_bulk_lp_pending"

private data class PendingLedgerBulkLpRestore(
    val request: PendingLedgerBulkLpRequest?,
    val blockedByUnreadableRecord: Boolean,
)

internal data class BulkLpLocationOption(val code: String, val displayName: String) {
    val label: String
        get() = if (displayName.isBlank() || displayName.equals(code, ignoreCase = true)) code
        else "$code · $displayName"
}

internal fun bulkLpLocationOptions(rows: List<JSONObject>): List<BulkLpLocationOption> =
    rows.mapNotNull { row ->
        val code = row.optString("code").trim()
        if (code.isBlank()) null
        else BulkLpLocationOption(
            code = code,
            displayName = row.optString("displayName").ifBlank { row.optString("name") }.trim(),
        )
    }.distinctBy { it.code.uppercase() }.sortedBy { it.code.uppercase() }

internal fun validBulkLpLocationSelection(
    locationCode: String,
    locationsComplete: Boolean,
    locations: List<BulkLpLocationOption>,
): Boolean = locationsComplete && locations.any { it.code.equals(locationCode.trim(), ignoreCase = true) }

internal fun commonLpQuantityDrafts(count: Int, quantity: String): List<BulkLpBuildDraft> =
    if (count !in 1..200) emptyList()
    else List(count) { index -> BulkLpBuildDraft(index + 1, quantity) }

internal fun bulkLpBuildPayload(locationCode: String, binCode: String, drafts: List<BulkLpBuildDraft>): String =
    JSONObject().apply {
        put("locationCode", locationCode.trim())
        put("binCode", binCode.trim())
        put("quantitiesJson", JSONArray().apply {
            drafts.forEach { put(it.quantity.toDoubleOrNull() ?: 0.0) }
        }.toString())
    }.toString()

internal fun validLedgerBulkLpPlan(
    lpCount: Int?,
    quantityPerLp: Double?,
    allocatableQuantity: Double,
    serialNo: String,
): Boolean {
    if (lpCount == null || lpCount !in 1..100) return false
    if (quantityPerLp == null || !quantityPerLp.isFinite() || quantityPerLp <= 0.0) return false
    if (lpCount * quantityPerLp > allocatableQuantity) return false
    return serialNo.isBlank() || (lpCount == 1 && quantityPerLp == 1.0)
}

internal fun itemLedgerLookupFilter(rawLookup: String): String {
    val value = rawLookup.trim()
    val safeValue = value.replace("'", "''")
    val entryNo = value.toIntOrNull()
    return if (entryNo == null) {
        "itemNo eq '$safeValue'"
    } else {
        "(entryNo eq $entryNo or itemNo eq '$safeValue')"
    }
}

internal fun itemLedgerLookupPath(filter: String, includeLpAllocationFields: Boolean): String {
    val allocationFields = if (includeLpAllocationFields) ",allocatedLpQuantity,lpAllocatableQuantity" else ""
    return "itemLedgerEntries?\$filter=$filter&\$orderby=entryNo desc&\$top=100&" +
        "\$select=entryNo,itemNo,postingDate,documentNo,locationCode,quantity,remainingQuantity$allocationFields," +
        "baseUnitOfMeasure,variantCode,lotNo,serialNo"
}

internal fun ledgerLpAllocatableQuantity(row: JSONObject): Double =
    if (row.has("lpAllocatableQuantity") && !row.isNull("lpAllocatableQuantity")) {
        row.optDouble("lpAllocatableQuantity", row.optDouble("remainingQuantity"))
    } else {
        row.optDouble("remainingQuantity")
    }

internal fun validLedgerBulkLpResponse(
    expectedCount: Int,
    createdCount: Int,
    createdLpNos: List<String>,
): Boolean =
    expectedCount > 0 &&
        createdCount == expectedCount &&
        createdLpNos.size == expectedCount &&
        createdLpNos.all(String::isNotBlank) &&
        createdLpNos.distinctBy(String::uppercase).size == expectedCount

internal fun validFailedPrintLpResponse(
    expectedFailureCount: Int,
    createdLpNos: List<String>,
    failedPrintLpNos: List<String>,
): Boolean {
    if (expectedFailureCount < 0 || failedPrintLpNos.size != expectedFailureCount) return false
    val createdKeys = createdLpNos.map { it.trim().uppercase() }.toSet()
    val failedKeys = failedPrintLpNos.map { it.trim().uppercase() }
    return failedPrintLpNos.all(String::isNotBlank) &&
        failedKeys.distinct().size == failedKeys.size &&
        failedKeys.all(createdKeys::contains)
}

internal fun ledgerBulkLpReplayState(
    replayed: Boolean,
    printLabels: Boolean,
    printSkippedOnReplay: Boolean,
): LedgerBulkLpReplayState = when {
    !replayed && printSkippedOnReplay -> LedgerBulkLpReplayState.Invalid
    replayed && printLabels && !printSkippedOnReplay -> LedgerBulkLpReplayState.Invalid
    replayed && !printLabels && printSkippedOnReplay -> LedgerBulkLpReplayState.Invalid
    replayed && printSkippedOnReplay -> LedgerBulkLpReplayState.ReplayedWithPrintSkipped
    replayed -> LedgerBulkLpReplayState.Replayed
    else -> LedgerBulkLpReplayState.FirstExecution
}

internal fun ledgerBulkLpPayload(
    templateCode: String,
    binCode: String,
    lpCount: Int,
    quantityPerLp: Double,
    printerId: String,
    printLabels: Boolean,
    requestId: String,
): String = JSONObject().apply {
    put("templateCode", templateCode.trim())
    put("binCode", binCode.trim())
    put("lpCount", lpCount)
    put("quantityPerLp", quantityPerLp)
    put("printerId", printerId.trim())
    put("printLabels", printLabels)
    put("requestId", requestId)
}.toString()

internal fun pendingLedgerBulkLpRequestJson(request: PendingLedgerBulkLpRequest): String =
    JSONObject().apply {
        put("entryNo", request.entryNo)
        put("expectedCount", request.expectedCount)
        put("printLabels", request.printLabels)
        put("requestId", request.requestId)
        put("body", request.body)
    }.toString()

internal fun pendingLedgerBulkLpRequestFromJson(raw: String): PendingLedgerBulkLpRequest? = runCatching {
    val json = JSONObject(raw)
    val request = PendingLedgerBulkLpRequest(
        entryNo = json.getInt("entryNo"),
        expectedCount = json.getInt("expectedCount"),
        printLabels = json.getBoolean("printLabels"),
        requestId = json.getString("requestId"),
        body = json.getString("body"),
    )
    val canonicalRequestId = UUID.fromString(request.requestId).toString()
    val body = JSONObject(request.body)
    require(request.entryNo > 0)
    require(request.expectedCount in 1..100)
    require(canonicalRequestId.equals(request.requestId, ignoreCase = true))
    require(body.getString("requestId").equals(request.requestId, ignoreCase = true))
    require(body.getInt("lpCount") == request.expectedCount)
    require(body.getBoolean("printLabels") == request.printLabels)
    require(body.getString("templateCode").isNotBlank())
    require(body.getString("binCode").isNotBlank())
    require(body.getDouble("quantityPerLp").let { it.isFinite() && it > 0.0 })
    request
}.getOrNull()

private object PendingLedgerBulkLpStore {
    private fun key(context: Context): String = listOf(
        BcApi.getTenant(context).trim().lowercase(),
        BcApi.getEnvironment(context).trim().lowercase(),
        BcApi.getCompanyId(context).trim().lowercase(),
    ).joinToString(separator = "|") { it }

    fun load(context: Context): PendingLedgerBulkLpRestore = runCatching {
        val prefs = context.getSharedPreferences(LEDGER_BULK_LP_PENDING_PREFS, Context.MODE_PRIVATE)
        val key = key(context)
        if (!prefs.contains(key)) return@runCatching PendingLedgerBulkLpRestore(null, false)
        val request = prefs.getString(key, null)?.let(::pendingLedgerBulkLpRequestFromJson)
        PendingLedgerBulkLpRestore(request, request == null)
    }.getOrElse { PendingLedgerBulkLpRestore(null, true) }

    fun save(context: Context, request: PendingLedgerBulkLpRequest): Boolean = runCatching {
        context.getSharedPreferences(LEDGER_BULK_LP_PENDING_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(key(context), pendingLedgerBulkLpRequestJson(request))
            // Mutasyondan önce diske yazılmış olmalı; process ölürse aynı UUID
            // geri yüklenmeden yeni toplu LP isteğine izin veremeyiz.
            .commit()
    }.getOrDefault(false)

    fun clear(context: Context): Boolean = runCatching {
        context.getSharedPreferences(LEDGER_BULK_LP_PENDING_PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(key(context))
            .commit()
    }.getOrDefault(false)
}

private fun lpQuantityText(value: String): String {
    var decimalSeen = false
    return buildString {
        value.replace(',', '.').forEach { char ->
            when {
                char.isDigit() -> append(char)
                char == '.' && !decimalSeen -> {
                    append(char)
                    decimalSeen = true
                }
            }
        }
    }
}

private fun formatLpQuantity(value: Double): String =
    if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BulkLpBuildSheet(
    onDismiss: () -> Unit,
    onBuilt: (LedgerBulkLpBuildResult) -> Unit,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    val restoredPending = remember(context) { PendingLedgerBulkLpStore.load(context) }
    var lookup by remember { mutableStateOf("") }
    var entries by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var selectedEntry by remember { mutableStateOf<JSONObject?>(null) }
    var template by remember { mutableStateOf("") }
    var templates by remember { mutableStateOf<List<String>>(emptyList()) }
    var templateExpanded by remember { mutableStateOf(false) }
    var bin by remember { mutableStateOf("") }
    var lpCountText by remember { mutableStateOf(DEFAULT_LEDGER_LP_COUNT) }
    var quantityText by remember { mutableStateOf(DEFAULT_LEDGER_LP_QUANTITY) }
    var printLabels by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var status by remember {
        mutableStateOf(
            when {
                restoredPending.blockedByUnreadableRecord ->
                    "HATA: Önceki güvenli toplu LP isteğinin cihaz kaydı okunamadı. " +
                        "Mükerrer LP oluşturmamak için yeni işlem engellendi; uygulama yöneticinize başvurun."
                restoredPending.request != null ->
                    "UYARI: Son toplu LP isteğinin sonucu uygulama kapanmadan önce doğrulanamamış. " +
                        "Aynı işlem kimliğiyle güvenli tekrar düğmesini kullanın."
                else -> ""
            },
        )
    }
    var completed by remember { mutableStateOf(false) }
    var uncertainOutcome by remember {
        mutableStateOf(restoredPending.request != null || restoredPending.blockedByUnreadableRecord)
    }
    var createdLpNos by remember { mutableStateOf<List<String>>(emptyList()) }
    var failedPrintLpNos by remember { mutableStateOf<List<String>>(emptyList()) }
    var replayed by remember { mutableStateOf(false) }
    var printSkippedOnReplay by remember { mutableStateOf(false) }
    var pendingRequest by remember { mutableStateOf(restoredPending.request) }

    LaunchedEffect(Unit) {
        val page = BcApi.getAllPages(context, "licensePlateTemplates?\$top=50&\$select=code,description")
        templates = if (page.complete) {
            page.rows.map { it.optString("code") }.filter(String::isNotBlank)
        } else {
            status = "HATA: LP şablonları alınamadı."
            emptyList()
        }
    }

    fun finish() {
        if (completed) {
            onBuilt(LedgerBulkLpBuildResult(createdLpNos, failedPrintLpNos, replayed, printSkippedOnReplay))
        } else {
            onDismiss()
        }
    }

    fun clearLedgerSelectionAndPlan() {
        entries = emptyList()
        selectedEntry = null
        template = ""
        templateExpanded = false
        bin = ""
        lpCountText = DEFAULT_LEDGER_LP_COUNT
        quantityText = DEFAULT_LEDGER_LP_QUANTITY
        printLabels = true
        completed = false
        uncertainOutcome = false
        createdLpNos = emptyList()
        failedPrintLpNos = emptyList()
        replayed = false
        printSkippedOnReplay = false
        pendingRequest = null
        status = ""
    }

    fun findLedgerEntries() {
        val value = lookup.trim()
        if (value.isBlank()) {
            status = "HATA: Madde numarası veya Madde Defter Giriş No girin."
            return
        }
        scope.launch {
            busy = true
            selectedEntry = null
            status = "Madde Defter Girişleri aranıyor..."
            val filter = itemLedgerLookupFilter(value)
            var usingLegacyQuantityFallback = false
            var page = BcApi.getAllPages(context, itemLedgerLookupPath(filter, includeLpAllocationFields = true))
            // 1.14.1.14 ve öncesinde yeni allocation alanları metadata'da yoktur;
            // bilinmeyen $select alanı BC'den 400 döndürür. Eski pakette salt-okunur
            // sorguyu ham Remaining Quantity ile çalıştırmaya devam et.
            if (!page.complete && page.error?.httpCode == 400) {
                usingLegacyQuantityFallback = true
                page = BcApi.getAllPages(context, itemLedgerLookupPath(filter, includeLpAllocationFields = false))
            }
            busy = false
            // Operatör istek sürerken arama değerini değiştirdiyse eski sorgunun
            // sonucu yeni değer altında gösterilmemeli/seçilememeli.
            if (lookup.trim() != value) return@launch
            entries = if (page.complete) {
                val availableRows = page.rows.filter { ledgerLpAllocatableQuantity(it) > 0.0 }
                val exactEntryNo = value.toIntOrNull()
                if (exactEntryNo == null) availableRows
                else availableRows.sortedWith(
                    compareByDescending<JSONObject> { it.optInt("entryNo") == exactEntryNo }
                        .thenByDescending { it.optInt("entryNo") },
                )
            } else emptyList()
            status = when {
                !page.complete -> "HATA: Madde Defter Girişlerinin tamamı alınamadı."
                entries.isEmpty() -> "BOŞ: Kullanılabilir miktarı olan giriş bulunamadı."
                usingLegacyQuantityFallback ->
                    "${entries.size} uygun giriş bulundu; kaynağı seçin. Eski BC paketi nedeniyle LP'ye ayrılabilir miktar ham kalan miktardan gösteriliyor."
                else -> "${entries.size} uygun giriş bulundu; kaynağı seçin."
            }
        }
    }

    val entry = selectedEntry
    val lpCount = lpCountText.toIntOrNull()
    val quantityPerLp = quantityText.toDoubleOrNull()
    val allocatableQuantity = entry?.let(::ledgerLpAllocatableQuantity) ?: 0.0
    val requestedQuantity = (lpCount ?: 0) * (quantityPerLp ?: 0.0)
    val planValid = validLedgerBulkLpPlan(
        lpCount,
        quantityPerLp,
        allocatableQuantity,
        entry?.optString("serialNo").orEmpty(),
    )
    val inputsEnabled = !busy && !uncertainOutcome

    fun submitBulkLp(requestToReplay: PendingLedgerBulkLpRequest? = null) {
        if (busy) return
        val sourceEntry = entry
        val count = lpCount
        val perLp = quantityPerLp
        val templateCode = template
        val binCode = bin
        val shouldPrint = printLabels
        val printerId = getDefaultPrinter(context, PRINTER_USAGE_LABEL)
        if (requestToReplay == null &&
            (sourceEntry == null || count == null || perLp == null || templateCode.isBlank() || binCode.isBlank())
        ) return

        busy = true
        scope.launch {
            val operation = if (requestToReplay != null) {
                status = "Aynı işlem kimliğiyle sonuç güvenle doğrulanıyor..."
                requestToReplay
            } else {
                status = "LP'ler oluşturuluyor${if (shouldPrint) " ve etiketleniyor" else ""}..."
                val safeLocation = sourceEntry!!.optString("locationCode").replace("'", "''")
                val safeBin = binCode.trim().replace("'", "''")
                val binPage = BcApi.getAllPages(
                    context,
                    "bins?\$filter=locationCode eq '$safeLocation' and code eq '$safeBin'&\$select=code&\$top=1",
                )
                if (!binPage.complete || binPage.rows.isEmpty()) {
                    busy = false
                    status = "HATA: Lokasyon ve stok rafı eşleşmiyor."
                    return@launch
                }

                val requestId = UUID.randomUUID().toString()
                PendingLedgerBulkLpRequest(
                    entryNo = sourceEntry.optInt("entryNo"),
                    expectedCount = count!!,
                    printLabels = shouldPrint,
                    requestId = requestId,
                    body = ledgerBulkLpPayload(
                        templateCode,
                        binCode,
                        count,
                        perLp!!,
                        printerId,
                        shouldPrint,
                        requestId,
                    ),
                )
            }
            if (!PendingLedgerBulkLpStore.save(context, operation)) {
                busy = false
                pendingRequest = if (requestToReplay == null) null else operation
                uncertainOutcome = requestToReplay != null
                status = "HATA: Güvenli işlem kimliği cihazda saklanamadı; sunucuya LP isteği gönderilmedi. " +
                    "Cihaz depolamasını kontrol edip tekrar deneyin."
                return@launch
            }
            pendingRequest = operation

            val result = BcApi.boundActionLongRunning(
                context,
                "itemLedgerEntries",
                "entryNo=${operation.entryNo}",
                LEDGER_BULK_LP_CREATE_ACTION,
                operation.body,
            )
            busy = false
            if (!result.ok) {
                if (BcApi.isAmbiguousMutationFailure(result)) {
                    uncertainOutcome = true
                    status = "UYARI: Sunucu cevabı alınamadı; LP'ler oluşturulmuş olabilir. " +
                        "Yeni işlem göndermeyin. Aynı işlem kimliğiyle güvenli tekrar düğmesini kullanın."
                } else {
                    PendingLedgerBulkLpStore.clear(context)
                    pendingRequest = null
                    uncertainOutcome = false
                    status = if (result.httpCode == 404 || result.httpCode == 405) {
                        "HATA: Güvenli toplu LP servisi BC'ye henüz yayımlanmamış. Güncel AL paketini yayınlayın; eski servise dönüş yapılmadı."
                    } else {
                        "HATA: ${BcApi.errorMessage(result.body)} (HTTP ${result.httpCode})"
                    }
                }
                return@launch
            }

            val response = runCatching { JSONObject(BcApi.scalarValue(result.body)) }.getOrNull()
            if (response == null) {
                status = "UYARI: Sunucu başarılı yanıt verdi ancak LP sonuçları okunamadı. " +
                    "Yeni işlem göndermeyin; aynı işlem kimliğiyle güvenli tekrar düğmesini kullanın."
                uncertainOutcome = true
                return@launch
            }
            val array = response.optJSONArray("createdLpNos") ?: JSONArray()
            createdLpNos = List(array.length()) { index -> array.optString(index).trim() }.filter(String::isNotBlank)
            val created = response.optInt("createdCount")
            if (!validLedgerBulkLpResponse(operation.expectedCount, created, createdLpNos)) {
                status = "UYARI: Sunucu $created LP bildirdi; yanıtta ${createdLpNos.size}/${operation.expectedCount} LP numarası var ancak liste doğrulanamadı. " +
                    "Yeni işlem göndermeyin; aynı işlem kimliğiyle güvenli tekrar düğmesini kullanın."
                uncertainOutcome = true
                return@launch
            }

            val printed = response.optInt("printedCount")
            val failed = response.optInt("printFailureCount")
            val failedArray = response.optJSONArray("failedPrintLpNos") ?: JSONArray()
            failedPrintLpNos = List(failedArray.length()) { index -> failedArray.optString(index).trim() }
                .filter(String::isNotBlank)
            if (!validFailedPrintLpResponse(failed, createdLpNos, failedPrintLpNos)) {
                status = "UYARI: $created LP oluşturuldu ancak başarısız etiketlerin LP listesi doğrulanamadı. " +
                    "Yeni işlem veya toplu baskı göndermeyin; aynı işlem kimliğiyle güvenli tekrar düğmesini kullanın."
                uncertainOutcome = true
                return@launch
            }

            val responseReplayed = response.optBoolean("replayed", false)
            val responsePrintSkipped = response.optBoolean("printSkippedOnReplay", false)
            val replayState = ledgerBulkLpReplayState(
                replayed = responseReplayed,
                printLabels = operation.printLabels,
                printSkippedOnReplay = responsePrintSkipped,
            )
            if (replayState == LedgerBulkLpReplayState.Invalid) {
                status = "UYARI: LP sonucu alındı ancak tekrar/baskı durumu doğrulanamadı. " +
                    "Yeni işlem göndermeyin; LP listesini ve yazdırma kuyruğunu kontrol edin."
                uncertainOutcome = true
                return@launch
            }

            replayed = responseReplayed
            printSkippedOnReplay = responsePrintSkipped
            PendingLedgerBulkLpStore.clear(context)
            pendingRequest = null
            uncertainOutcome = false
            status = when (replayState) {
                LedgerBulkLpReplayState.ReplayedWithPrintSkipped ->
                    "TAMAM: Daha önce oluşturulan $created LP aynı işlem kimliğiyle doğrulandı. " +
                        "Çift baskıyı önlemek için etiketler yeniden kuyruğa alınmadı; fiziksel etiketleri kontrol edip yalnız eksikleri listeden seçin."
                LedgerBulkLpReplayState.Replayed ->
                    "TAMAM: Daha önce oluşturulan $created LP aynı işlem kimliğiyle güvenle doğrulandı."
                LedgerBulkLpReplayState.FirstExecution -> when {
                    operation.printLabels && failed > 0 ->
                        "UYARI: $created LP oluşturuldu; $printed etiket kuyruğa alındı, $failed etiket gönderilemedi. " +
                            "LP listesine dönün; yalnız başarısız LP'ler seçili gelecektir."
                    operation.printLabels -> "TAMAM: $created LP oluşturuldu ve her LP için ayrı etiket kuyruğa alındı."
                    else -> "TAMAM: $created LP oluşturuldu."
                }
                LedgerBulkLpReplayState.Invalid -> error("Invalid replay state handled above")
            }
            completed = true
        }
    }

    com.dynops.bcwms.ui.SheetScaffold(onDismiss = { if (!busy) finish() }) {
        Text("Mevcut Stoktan Toplu LP", fontSize = 21.sp, fontWeight = FontWeight.Bold)
        Text(
            "Madde Defter Girişi tek satır kalır; LP'ler ayrı kayıtlarda aynı girişe bağlanır.",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(10.dp))

        if (completed) {
            StatusText(status)
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = {
                    onBuilt(
                        LedgerBulkLpBuildResult(
                            createdLpNos,
                            failedPrintLpNos,
                            replayed,
                            printSkippedOnReplay,
                        ),
                    )
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("LP Listesine Dön")
            }
            Spacer(Modifier.height(24.dp))
            return@SheetScaffold
        }

        ScanField(
            "Madde No / Madde Defter Giriş No",
            lookup,
            { raw ->
                val nextLookup = raw.trimStart()
                if (nextLookup != lookup) {
                    lookup = nextLookup
                    clearLedgerSelectionAndPlan()
                }
            },
            modifier = Modifier.fillMaxWidth(),
            enabled = inputsEnabled,
        )
        Spacer(Modifier.height(8.dp))
        OutlinedButton(
            onClick = { findLedgerEntries() },
            enabled = !busy && !uncertainOutcome && lookup.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        ) { Text(if (busy) "Aranıyor..." else "Girişleri Getir") }

        if (entries.isNotEmpty()) {
            Spacer(Modifier.height(10.dp))
            Text("Kaynak Madde Defter Girişi", fontWeight = FontWeight.Bold, fontSize = 13.sp)
            if (entries.size > LEDGER_ENTRY_DISPLAY_LIMIT) {
                Text(
                    "Toplam ${entries.size} giriş bulundu; en yeni $LEDGER_ENTRY_DISPLAY_LIMIT giriş gösteriliyor. " +
                        "Daha eski bir kayıt için Madde Defter Giriş No ile arayın.",
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.tertiary,
                )
            }
            entries.take(LEDGER_ENTRY_DISPLAY_LIMIT).forEach { row ->
                val selected = selectedEntry?.optInt("entryNo") == row.optInt("entryNo")
                Card(
                    onClick = {
                        if (!selected) {
                            template = ""
                            templateExpanded = false
                            bin = ""
                            lpCountText = DEFAULT_LEDGER_LP_COUNT
                            quantityText = DEFAULT_LEDGER_LP_QUANTITY
                            printLabels = true
                        }
                        selectedEntry = row
                        status = ""
                    },
                    modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
                    enabled = inputsEnabled,
                    colors = CardDefaults.cardColors(
                        containerColor = if (selected) MaterialTheme.colorScheme.primaryContainer
                        else MaterialTheme.colorScheme.surface,
                    ),
                    border = androidx.compose.foundation.BorderStroke(
                        1.dp,
                        if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
                    ),
                ) {
                    Column(Modifier.padding(12.dp)) {
                        Text("#${row.optInt("entryNo")} · ${row.optString("itemNo")}", fontWeight = FontWeight.Bold)
                        val rowAllocatableQuantity = ledgerLpAllocatableQuantity(row)
                        Text(
                            "LP'ye ayrılabilir: ${formatLpQuantity(rowAllocatableQuantity)} " +
                                "${row.optString("baseUnitOfMeasure")} · ${row.optString("locationCode")}",
                            fontSize = 12.sp,
                        )
                        val detail = listOfNotNull(
                            row.optDouble("allocatedLpQuantity", 0.0)
                                .takeIf { row.has("allocatedLpQuantity") && it > 0.0 }
                                ?.let { "LP'lere ayrılmış ${formatLpQuantity(it)}" },
                            row.optString("postingDate").takeIf(String::isNotBlank)?.let { "Tarih $it" },
                            row.optString("lotNo").takeIf(String::isNotBlank)?.let { "Lot $it" },
                            row.optString("serialNo").takeIf(String::isNotBlank)?.let { "Seri $it" },
                            row.optString("documentNo").takeIf(String::isNotBlank)?.let { "Belge $it" },
                        ).joinToString(" · ")
                        if (detail.isNotBlank())
                            Text(detail, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }

        if (entry != null) {
            Spacer(Modifier.height(12.dp))
            ExposedDropdownMenuBox(
                expanded = templateExpanded,
                onExpandedChange = { if (inputsEnabled) templateExpanded = !templateExpanded },
            ) {
                OutlinedTextField(
                    value = template,
                    onValueChange = { template = it },
                    readOnly = templates.isNotEmpty(),
                    label = { Text("LP Şablonu") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(templateExpanded) },
                    singleLine = true,
                    enabled = inputsEnabled,
                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                )
                ExposedDropdownMenu(expanded = templateExpanded, onDismissRequest = { templateExpanded = false }) {
                    templates.forEach { code ->
                        DropdownMenuItem(
                            text = { Text(code) },
                            onClick = { template = code; templateExpanded = false },
                            enabled = inputsEnabled,
                        )
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = entry.optString("locationCode"),
                onValueChange = {},
                readOnly = true,
                label = { Text("Lokasyon") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(8.dp))
            ScanField(
                "Stok Rafı (Bin)",
                bin,
                { bin = it.uppercase() },
                modifier = Modifier.fillMaxWidth(),
                enabled = inputsEnabled,
            )
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = lpCountText,
                    onValueChange = { lpCountText = it.filter(Char::isDigit).take(3) },
                    label = { Text("LP adedi") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    enabled = inputsEnabled,
                    modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    value = quantityText,
                    onValueChange = { quantityText = lpQuantityText(it) },
                    label = { Text("LP başı miktar") },
                    suffix = { Text(entry.optString("baseUnitOfMeasure")) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    enabled = inputsEnabled,
                    modifier = Modifier.weight(1f),
                )
            }
            Text(
                "Toplam: ${formatLpQuantity(requestedQuantity)} / ${formatLpQuantity(allocatableQuantity)} " +
                    entry.optString("baseUnitOfMeasure"),
                fontSize = 12.sp,
                color = if (requestedQuantity > allocatableQuantity) MaterialTheme.colorScheme.error
                else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(
                    checked = printLabels,
                    onCheckedChange = { printLabels = it },
                    enabled = inputsEnabled,
                )
                Text("Her LP için ayrı etiket yazdır")
            }
        }

        if (status.isNotBlank()) StatusText(status)
        Spacer(Modifier.height(8.dp))
        if (uncertainOutcome && pendingRequest != null) {
            Button(
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
                onClick = { pendingRequest?.let { submitBulkLp(it) } },
            ) { Text(if (busy) "Doğrulanıyor..." else "Aynı İşlem Kimliğiyle Güvenle Tekrar Dene") }
        } else {
            Button(
                enabled = inputsEnabled && entry != null && template.isNotBlank() && bin.isNotBlank() && planValid,
                modifier = Modifier.fillMaxWidth(),
                onClick = { submitBulkLp() },
            ) { Text(if (busy) "İşleniyor..." else "LP'leri Oluştur") }
        }
        Spacer(Modifier.height(24.dp))
    }
}
