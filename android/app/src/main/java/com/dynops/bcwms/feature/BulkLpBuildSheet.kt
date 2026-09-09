package com.dynops.bcwms.feature

import com.dynops.bcwms.ui.toFiniteDoubleOrNull

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
import com.dynops.bcwms.ui.operatorFacingApiError
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
    val printLabelsRequested: Boolean,
    val sourceEntryNo: Int,
)

internal data class PendingLedgerBulkLpRequest(
    val entryNo: Int,
    val expectedCount: Int,
    val printLabels: Boolean,
    val requestId: String,
    val body: String,
    // Tekrar denemede İLK çağrının ucu kullanılmalıdır. İki uç aynı işlem
    // kimliğini paylaşır ama gövdeleri farklıdır; uç adını saklamak, cihaz
    // yeniden açıldığında yanlış uca replay göndermeyi imkânsız kılar.
    val action: String = LEDGER_BULK_LP_CREATE_ACTION,
)

/**
 * Operatörün girdiği "LP başı miktar"dan üretilen palet planı.
 * 10.350 adet / 1.000 kapasite -> 10 tam palet + 350'lik bir artık palet.
 */
internal data class LedgerLpPlan(
    val fullCount: Int,
    val quantityPerLp: Double,
    val lastQuantity: Double,
) {
    val totalLpCount: Int get() = fullCount + if (lastQuantity > 0.0) 1 else 0
    val totalQuantity: Double get() = fullCount * quantityPerLp + lastQuantity
}

/**
 * LP'lenebilir kalan miktarı verilen palet kapasitesine böler. Kapasite ya da
 * kalan miktar geçersizse null döner; çağıran hiçbir plan göstermez.
 * Kalan miktar kapasiteden küçükse tek bir artık palet oluşur.
 */
internal fun planLedgerLps(allocatableQuantity: Double, quantityPerLp: Double?): LedgerLpPlan? {
    if (quantityPerLp == null || !quantityPerLp.isFinite() || quantityPerLp <= 0.0) return null
    if (!allocatableQuantity.isFinite() || allocatableQuantity <= 0.0) return null
    val tolerance = 0.00001
    val fullCount = Math.floor(allocatableQuantity / quantityPerLp + tolerance).toInt()
    if (fullCount < 0) return null
    val remainder = allocatableQuantity - fullCount * quantityPerLp
    val lastQuantity = if (remainder > tolerance) Math.round(remainder * 100000.0) / 100000.0 else 0.0
    if (fullCount == 0 && lastQuantity <= 0.0) return null
    return LedgerLpPlan(fullCount, quantityPerLp, lastQuantity)
}

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
internal const val LEDGER_BULK_LP_PLAN_ACTION = "createLicensePlatesFromPlanIdempotent"
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
    if (count !in 1..100) emptyList()
    else List(count) { index -> BulkLpBuildDraft(index + 1, quantity) }

internal fun bulkLpBuildPayload(locationCode: String, binCode: String, drafts: List<BulkLpBuildDraft>): String =
    JSONObject().apply {
        put("locationCode", locationCode.trim())
        put("binCode", binCode.trim())
        put("quantitiesJson", JSONArray().apply {
            drafts.forEach { put(it.quantity.toFiniteDoubleOrNull() ?: 0.0) }
        }.toString())
    }.toString()

internal fun validLedgerBulkLpPlan(
    lpCount: Int?,
    quantityPerLp: Double?,
    allocatableQuantity: Double,
    serialNo: String,
    quantityLastLp: Double = 0.0,
): Boolean {
    if (lpCount == null || lpCount !in 1..100) return false
    if (quantityPerLp == null || !quantityPerLp.isFinite() || quantityPerLp <= 0.0) return false
    if (!quantityLastLp.isFinite() || quantityLastLp < 0.0) return false
    val totalLpCount = lpCount + if (quantityLastLp > 0.0) 1 else 0
    if (totalLpCount !in 1..100) return false
    // Otomatik hesaplanan artık palet toplamı kullanılabilir miktara TAM
    // eşitleyebilir; ondalık gösterimden gelen milyarda bir fark yüzünden
    // geçerli bir plan reddedilmemeli.
    if (lpCount * quantityPerLp + quantityLastLp > allocatableQuantity + 0.00001) return false
    return serialNo.isBlank() || (totalLpCount == 1 && quantityPerLp == 1.0 && quantityLastLp == 0.0)
}

internal fun itemLedgerLookupFilter(rawLookup: String): String {
    val value = rawLookup.trim()
    val safeValue = value.replace("'", "''")
    val entryNo = value.toIntOrNull()
    return if (entryNo == null) {
        "itemNo eq '$safeValue'"
    } else {
        "entryNo eq $entryNo"
    }
}

internal fun itemLedgerLookupFilters(rawLookup: String): List<String> {
    val value = rawLookup.trim()
    val primary = itemLedgerLookupFilter(value)
    // BC rejects OR across different fields (HTTP 501). Search each field
    // separately and merge by entry number, including numeric lot numbers.
    val safeValue = value.replace("'", "''")
    return buildList {
        add(primary)
        if (value.toIntOrNull() != null) add("itemNo eq '$safeValue'")
        add("lotNo eq '$safeValue'")
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

/** Read back the actual LP lines; a successful create response alone is not a source link. */
internal fun ledgerLpSourceLinksMatch(
    entryNo: Int,
    createdLpNos: List<String>,
    lines: List<JSONObject>,
    complete: Boolean,
): Boolean {
    if (!complete || entryNo <= 0 || createdLpNos.isEmpty() || lines.isEmpty()) return false
    val expected = createdLpNos.map { it.trim().uppercase() }.toSet()
    val actual = lines.map { it.optString("lpNo").trim().uppercase() }.toSet()
    return expected == actual && lines.all {
        it.optInt("sourceItemLedgerEntryNo") == entryNo && it.optDouble("quantity", 0.0) > 0.0
    }
}

/** ILE display fields must also reflect the allocation, not just the LP-side link. */
internal fun ledgerLpEntryReferenceMatches(
    entryNo: Int,
    createdLpNos: List<String>,
    entries: List<JSONObject>,
    complete: Boolean,
): Boolean {
    if (!complete || createdLpNos.isEmpty() || entries.size != 1) return false
    val entry = entries.single()
    if (entry.optInt("entryNo") != entryNo) return false
    val lpNo = entry.optString("lpNo").trim().uppercase()
    val lpNos = entry.optString("lpNos").uppercase()
    val references = (listOf(lpNo) + lpNos.split(',')).map(String::trim).filter(String::isNotBlank).toSet()
    if (references.isEmpty()) return false
    // BC's summary is Text[250]. Full identity verification is performed on
    // all LP lines above; a truncated display cannot list every allocated LP.
    if (lpNos.length >= 250) return true
    return createdLpNos.all { it.trim().uppercase() in references }
}

internal fun ledgerLpSourceLookupPath(lpNos: List<String>): String {
    require(lpNos.isNotEmpty())
    val filter = lpNos.joinToString(" or ") { "lpNo eq '${it.replace("'", "''")}'" }
    return "licensePlateLines?\$filter=($filter)&\$select=lpNo,sourceItemLedgerEntryNo,quantity&\$top=200"
}

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
    quantityLastLp: Double = 0.0,
): String = JSONObject().apply {
    put("templateCode", templateCode.trim())
    put("binCode", binCode.trim())
    put("lpCount", lpCount)
    put("quantityPerLp", quantityPerLp)
    // Artık palet yalnız yeni uçta anlamlıdır; sıfırken alan hiç gönderilmez ve
    // gövde eski uçla birebir aynı kalır.
    if (quantityLastLp > 0.0) put("quantityLastLp", quantityLastLp)
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
        put("action", request.action)
    }.toString()

internal fun pendingLedgerBulkLpRequestFromJson(raw: String): PendingLedgerBulkLpRequest? = runCatching {
    val json = JSONObject(raw)
    val request = PendingLedgerBulkLpRequest(
        entryNo = json.getInt("entryNo"),
        expectedCount = json.getInt("expectedCount"),
        printLabels = json.getBoolean("printLabels"),
        requestId = json.getString("requestId"),
        body = json.getString("body"),
        action = json.optString("action").trim().ifBlank { LEDGER_BULK_LP_CREATE_ACTION },
    )
    val canonicalRequestId = UUID.fromString(request.requestId).toString()
    val body = JSONObject(request.body)
    require(request.entryNo > 0)
    require(request.expectedCount in 1..100)
    require(canonicalRequestId.equals(request.requestId, ignoreCase = true))
    require(body.getString("requestId").equals(request.requestId, ignoreCase = true))
    require(request.action == LEDGER_BULK_LP_CREATE_ACTION || request.action == LEDGER_BULK_LP_PLAN_ACTION)
    val storedLastQty = body.optDouble("quantityLastLp", 0.0)
    require(storedLastQty.isFinite() && storedLastQty >= 0.0)
    // Artık palet varsa toplam palet adedi tam palet sayısından bir fazladır.
    require(body.getInt("lpCount") + (if (storedLastQty > 0.0) 1 else 0) == request.expectedCount)
    require(storedLastQty == 0.0 || request.action == LEDGER_BULK_LP_PLAN_ACTION)
    require(body.getBoolean("printLabels") == request.printLabels)
    require(body.getString("templateCode").isNotBlank())
    // Blank bin means the server will distribute complete LPs across the
    // matching loose-stock bins. Explicit-bin requests remain supported.
    body.getString("binCode")
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

/** Converts stock-allocation errors into a short instruction the operator can act on. */
internal fun ledgerBulkLpFriendlyError(raw: String, httpCode: Int = 0): String = when {
    raw.contains("izlemeli serbest stoku yetersizdir", ignoreCase = true) ||
        raw.contains("LP'ye atanmamış serbest stoku yetersizdir", ignoreCase = true) ->
        "HATA: Seçtiğiniz ürün veya lot bu rafta yeterli miktarda yok. " +
            "Ürünün gerçekten bulunduğu rafı okutun. Ürün zaten bir LP içindeyse yeni LP oluşturmayın."

    raw.contains("LP'ye ayrılabilir miktar", ignoreCase = true) ->
        "HATA: Bu stok kaydında seçtiğiniz toplam kadar kullanılabilir ürün yok. " +
            "LP adedini veya LP başı miktarı azaltın."

    raw.contains("raflara dağılmış", ignoreCase = true) ->
        "HATA: Raflardaki stok toplamı yeterli görünse de seçtiğiniz LP miktarıyla tam paletlere ayrılamıyor. " +
            "LP başı miktarı azaltın veya belirli bir raf okutarak o raftaki stoğu ayrı işlemde LP'leyin."

    raw.contains("kullanılabilir miktar yoktur", ignoreCase = true) ->
        "HATA: Bu stok kaydında LP yapılabilecek ürün kalmamış. Başka bir stok kaydı seçin."

    raw.contains("seri takipli", ignoreCase = true) ->
        "HATA: Seri numaralı ürünlerde her LP yalnızca 1 adet olabilir."

    raw.contains("varyantlı stok için toplu LP oluşturma desteklenmiyor", ignoreCase = true) ->
        "HATA: Varyantlı ürünler bu ekrandan toplu LP'ye ayrılamıyor."

    else -> operatorFacingApiError(raw, httpCode)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BulkLpBuildSheet(
    singleLpMode: Boolean = false,
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
    var lpCountText by remember(singleLpMode) {
        mutableStateOf(if (singleLpMode) "1" else DEFAULT_LEDGER_LP_COUNT)
    }
    var quantityText by remember { mutableStateOf(DEFAULT_LEDGER_LP_QUANTITY) }
    var printLabels by remember { mutableStateOf(true) }
    // Artık palet ucu yayındaki BC paketinde var mı? Yoksa ekran yalnız tam
    // paletler önerir ve eski uca gider; yeni APK eski sunucuya tanımadığı bir
    // action göndermez.
    var planSupported by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var status by remember {
        mutableStateOf(
            when {
                restoredPending.blockedByUnreadableRecord ->
                    "HATA: Önceki LP oluşturma denemesinin sonucu kontrol edilemiyor. " +
                        "Yeni LP oluşturmayın; yöneticinizden işlemi kontrol etmesini isteyin."
                restoredPending.request != null ->
                    "UYARI: Önceki LP oluşturma denemesinin sonucu alınamadı. " +
                        "Yeni işlem başlatmayın; aşağıdaki Önceki İşlemi Kontrol Et düğmesine basın."
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
    var completedPrintLabelsRequested by remember { mutableStateOf(false) }
    var completedSourceEntryNo by remember { mutableStateOf(0) }

    fun buildResult() = LedgerBulkLpBuildResult(
        createdLpNos, failedPrintLpNos, replayed, printSkippedOnReplay,
        completedPrintLabelsRequested, completedSourceEntryNo,
    )

    LaunchedEffect(Unit) {
        planSupported = BcApi.getLpScanCapabilities(context).bulkLpPlan
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
            onBuilt(buildResult())
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
        lpCountText = if (singleLpMode) "1" else DEFAULT_LEDGER_LP_COUNT
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
            status = "HATA: Ürün numarası, stok kayıt numarası veya lot numarası girin."
            return
        }
        scope.launch {
            busy = true
            selectedEntry = null
            status = "Stok kayıtları aranıyor..."
            var usingLegacyQuantityFallback = false
            var complete = true
            val foundRows = mutableListOf<JSONObject>()
            for (filter in itemLedgerLookupFilters(value)) {
                var page = BcApi.getAllPages(context, itemLedgerLookupPath(filter, includeLpAllocationFields = true))
                // 1.14.1.14 ve öncesinde yeni allocation alanları metadata'da yoktur;
                // bilinmeyen $select alanı BC'den 400 döndürür. Eski pakette salt-okunur
                // sorguyu ham Remaining Quantity ile çalıştırmaya devam et.
                if (!page.complete && page.error?.httpCode == 400) {
                    usingLegacyQuantityFallback = true
                    page = BcApi.getAllPages(context, itemLedgerLookupPath(filter, includeLpAllocationFields = false))
                }
                if (!page.complete) {
                    complete = false
                    break
                }
                foundRows += page.rows
            }
            busy = false
            // Operatör istek sürerken arama değerini değiştirdiyse eski sorgunun
            // sonucu yeni değer altında gösterilmemeli/seçilememeli.
            if (lookup.trim() != value) return@launch
            entries = if (complete) {
                val availableRows = foundRows.distinctBy { it.optInt("entryNo") }
                    .filter { ledgerLpAllocatableQuantity(it) > 0.0 }
                val exactEntryNo = value.toIntOrNull()
                if (exactEntryNo == null) availableRows
                else availableRows.sortedWith(
                    compareByDescending<JSONObject> { it.optInt("entryNo") == exactEntryNo }
                        .thenByDescending { it.optInt("entryNo") },
                )
            } else emptyList()
            status = when {
                !complete -> "HATA: Stok kayıtları alınamadı. Bağlantıyı kontrol edip tekrar deneyin."
                entries.isEmpty() -> "BOŞ: LP yapılabilecek miktarı olan stok bulunamadı."
                usingLegacyQuantityFallback ->
                    "${entries.size} stok kaydı bulundu. Kullanacağınız kaydı seçin."
                else -> "${entries.size} stok kaydı bulundu. Kullanacağınız kaydı seçin."
            }
        }
    }

    val entry = selectedEntry
    val lpCount = lpCountText.toIntOrNull()
    val quantityPerLp = quantityText.toFiniteDoubleOrNull()
    val allocatableQuantity = entry?.let(::ledgerLpAllocatableQuantity) ?: 0.0
    // Müşteri isteği: operatör yalnız palet kapasitesini girer, tam palet
    // adedini ve son paletteki artığı sistem hesaplar.
    val autoPlan = if (singleLpMode) null else planLedgerLps(allocatableQuantity, quantityPerLp)
    // Artık palet yalnız operatör TÜM kalan miktarı paletlerken eklenir. Adedi
    // elle düşürdüyse bilerek bir kısmını paletliyor demektir; ona istemediği
    // bir palet daha üretilmez.
    val remainderQuantity =
        if (planSupported && autoPlan != null && lpCount == autoPlan.fullCount) autoPlan.lastQuantity else 0.0
    val totalLpCount = (lpCount ?: 0) + if (remainderQuantity > 0.0) 1 else 0
    val requestedQuantity = (lpCount ?: 0) * (quantityPerLp ?: 0.0) + remainderQuantity
    val planValid = validLedgerBulkLpPlan(
        lpCount,
        quantityPerLp,
        allocatableQuantity,
        entry?.optString("serialNo").orEmpty(),
        remainderQuantity,
    )
    val inputsEnabled = !busy && !uncertainOutcome

    // Palet kapasitesi ya da seçili stok kaydı değiştiğinde tam palet adedini
    // otomatik doldur. Alan düzenlenebilir kalır: operatör daha az palet
    // yapmak isterse adedi elle düşürebilir.
    LaunchedEffect(autoPlan?.fullCount, autoPlan?.quantityPerLp, singleLpMode) {
        val suggested = autoPlan?.fullCount ?: return@LaunchedEffect
        if (suggested > 0) lpCountText = suggested.toString()
    }

    fun submitBulkLp(requestToReplay: PendingLedgerBulkLpRequest? = null) {
        if (busy) return
        val sourceEntry = entry
        val count = lpCount
        val perLp = quantityPerLp
        // Ekranda gösterilen planla gönderilen plan aynı olmalı: artık palet
        // burada tekrar hesaplanmaz, ekrandaki değer taşınır.
        val lastQty = remainderQuantity
        val templateCode = template
        val binCode = bin
        val shouldPrint = printLabels
        val printerId = getDefaultPrinter(context, PRINTER_USAGE_LABEL)
        if (requestToReplay == null &&
            (sourceEntry == null || count == null || perLp == null || templateCode.isBlank())
        ) return

        busy = true
        scope.launch {
            val operation = if (requestToReplay != null) {
                status = "Önceki işlem kontrol ediliyor..."
                requestToReplay
            } else {
                status = "LP'ler oluşturuluyor${if (shouldPrint) " ve etiketleniyor" else ""}..."
                if (binCode.isNotBlank()) {
                    val safeLocation = sourceEntry!!.optString("locationCode").replace("'", "''")
                    val safeBin = binCode.trim().replace("'", "''")
                    val binPage = BcApi.getAllPages(
                        context,
                        "bins?\$filter=locationCode eq '$safeLocation' and code eq '$safeBin'&\$select=code&\$top=1",
                    )
                    if (!binPage.complete || binPage.rows.isEmpty()) {
                        busy = false
                        status = "HATA: Okuttuğunuz raf bu depoya ait değil. Doğru raf etiketini okutun."
                        return@launch
                    }
                }

                val requestId = UUID.randomUUID().toString()
                PendingLedgerBulkLpRequest(
                    entryNo = sourceEntry!!.optInt("entryNo"),
                    // Beklenen kayıt sayısı artık paleti de kapsar; sunucudan
                    // dönen createdCount bununla karşılaştırılır.
                    expectedCount = count!! + if (lastQty > 0.0) 1 else 0,
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
                        lastQty,
                    ),
                    action = if (lastQty > 0.0) LEDGER_BULK_LP_PLAN_ACTION else LEDGER_BULK_LP_CREATE_ACTION,
                )
            }
            if (!PendingLedgerBulkLpStore.save(context, operation)) {
                busy = false
                pendingRequest = if (requestToReplay == null) null else operation
                uncertainOutcome = requestToReplay != null
                status = "HATA: İşlem bilgisi cihazda kaydedilemedi ve LP oluşturulmadı. " +
                    "Uygulamayı kapatmadan tekrar deneyin; sorun sürerse yöneticinize bildirin."
                return@launch
            }
            pendingRequest = operation

            val result = BcApi.boundActionLongRunning(
                context,
                "itemLedgerEntries",
                "entryNo=${operation.entryNo}",
                // Tekrar denemede ilk çağrının ucu kullanılır; aynı işlem
                // kimliği farklı bir uca gitmez.
                operation.action,
                operation.body,
            )
            busy = false
            if (!result.ok) {
                if (BcApi.isAmbiguousMutationFailure(result)) {
                    uncertainOutcome = true
                    status = "UYARI: LP'lerin oluşup oluşmadığı kontrol edilemedi. " +
                        "Yeni işlem başlatmayın; Önceki İşlemi Kontrol Et düğmesine basın."
                } else {
                    PendingLedgerBulkLpStore.clear(context)
                    pendingRequest = null
                    uncertainOutcome = false
                    status = if (result.httpCode == 404 || result.httpCode == 405) {
                        "HATA: Bu özellik BC tarafında henüz hazır değil. Yöneticinizden sistemi güncellemesini isteyin."
                    } else {
                        ledgerBulkLpFriendlyError(BcApi.errorMessage(result.body), result.httpCode)
                    }
                }
                return@launch
            }

            val response = runCatching { JSONObject(BcApi.scalarValue(result.body)) }.getOrNull()
            if (response == null) {
                status = "UYARI: LP'lerin oluşup oluşmadığı kontrol edilemedi. " +
                    "Yeni işlem başlatmayın; Önceki İşlemi Kontrol Et düğmesine basın."
                uncertainOutcome = true
                return@launch
            }
            val array = response.optJSONArray("createdLpNos") ?: JSONArray()
            createdLpNos = List(array.length()) { index -> array.optString(index).trim() }.filter(String::isNotBlank)
            val created = response.optInt("createdCount")
            if (!validLedgerBulkLpResponse(operation.expectedCount, created, createdLpNos)) {
                status = "UYARI: Oluşan LP listesi eksik görünüyor. " +
                    "Yeni işlem başlatmayın; Önceki İşlemi Kontrol Et düğmesine basın."
                uncertainOutcome = true
                return@launch
            }

            val printed = response.optInt("printedCount")
            val failed = response.optInt("printFailureCount")
            val failedArray = response.optJSONArray("failedPrintLpNos") ?: JSONArray()
            failedPrintLpNos = List(failedArray.length()) { index -> failedArray.optString(index).trim() }
                .filter(String::isNotBlank)
            if (!validFailedPrintLpResponse(failed, createdLpNos, failedPrintLpNos)) {
                status = "UYARI: LP'ler oluştu ancak bazı etiketlerin durumu kontrol edilemedi. " +
                    "Yeni işlem başlatmayın; Önceki İşlemi Kontrol Et düğmesine basın."
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
                status = "UYARI: Etiketlerin durumu kontrol edilemedi. " +
                    "LP listesini ve yazdırma sırasını kontrol edin."
                uncertainOutcome = true
                return@launch
            }

            // The old single-LP path returned an LP number without linking an
            // ILE. Do not report success until the persisted lines prove the link.
            busy = true
            status = "LP kaynak giriş bağlantısı kontrol ediliyor..."
            val sourceLines = mutableListOf<JSONObject>()
            var sourceReadComplete = response.optInt("sourceItemLedgerEntryNo") == operation.entryNo
            if (sourceReadComplete) {
                for (batch in createdLpNos.chunked(20)) {
                    val page = BcApi.getAllPages(context, ledgerLpSourceLookupPath(batch))
                    if (!page.complete) {
                        sourceReadComplete = false
                        break
                    }
                    sourceLines += page.rows
                }
            }
            val linesLinked = ledgerLpSourceLinksMatch(operation.entryNo, createdLpNos, sourceLines, sourceReadComplete)
            var entryLinked = false
            if (linesLinked) {
                val sourcePage = BcApi.getAllPages(
                    context,
                    "itemLedgerEntries?\$filter=entryNo eq ${operation.entryNo}&\$select=entryNo,lpNo,lpNos&\$top=1",
                )
                entryLinked = ledgerLpEntryReferenceMatches(
                    operation.entryNo, createdLpNos, sourcePage.rows, sourcePage.complete,
                )
            }
            busy = false
            if (!linesLinked || !entryLinked) {
                uncertainOutcome = true
                status = "UYARI: LP oluşturuldu ancak #${operation.entryNo} kaynak giriş bağlantısı doğrulanamadı. " +
                    "Yeni LP oluşturmayın; Önceki İşlemi Kontrol Et düğmesine basın. " +
                    "Sorun devam ederse bu LP numaralarını yöneticinize iletin: ${createdLpNos.joinToString()}."
                return@launch
            }

            replayed = responseReplayed
            printSkippedOnReplay = responsePrintSkipped
            PendingLedgerBulkLpStore.clear(context)
            pendingRequest = null
            uncertainOutcome = false
            status = when (replayState) {
                LedgerBulkLpReplayState.ReplayedWithPrintSkipped ->
                    "TAMAM: Daha önce oluşturulan $created LP bulundu. " +
                        "Aynı etiketi iki kez basmamak için etiketler yeniden gönderilmedi. Yalnızca eksik etiketleri LP listesinden yazdırın."
                LedgerBulkLpReplayState.Replayed ->
                    "TAMAM: Daha önce oluşturulan $created LP bulundu."
                LedgerBulkLpReplayState.FirstExecution -> when {
                    operation.printLabels && failed > 0 ->
                        "UYARI: $created LP oluşturuldu; $printed etiket kuyruğa alındı, $failed etiket gönderilemedi. " +
                            "LP listesine dönün; yalnız başarısız LP'ler seçili gelecektir."
                    operation.printLabels -> "TAMAM: $created LP oluşturuldu ve her LP için ayrı etiket kuyruğa alındı."
                    else -> "TAMAM: $created LP oluşturuldu."
                }
                LedgerBulkLpReplayState.Invalid -> error("Invalid replay state handled above")
            }
            completedPrintLabelsRequested = operation.printLabels
            completedSourceEntryNo = operation.entryNo
            completed = true
        }
    }

    com.dynops.bcwms.ui.SheetScaffold(onDismiss = { if (!busy) finish() }) {
        Text(
            if (singleLpMode) "Stoktan Tekli LP Oluştur" else "Mevcut Stoktan LP Oluştur",
            fontSize = 21.sp,
            fontWeight = FontWeight.Bold,
        )
        Text(
            "LP, seçtiğiniz kaynak madde defter girişine bağlanır. Toplam stok değişmez. Ürün birden fazla raftaysa sistem LP'yi doldurmak için gerekli raf hareketini birlikte kaydeder.",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(10.dp))

        if (completed) {
            StatusText(status)
            Spacer(Modifier.height(12.dp))
            Text("Kaynak giriş: #$completedSourceEntryNo", fontWeight = FontWeight.Bold)
            Text("Oluşan LP'ler", fontWeight = FontWeight.Bold)
            createdLpNos.forEach { no ->
                Text(no, fontSize = 13.sp)
            }
            Spacer(Modifier.height(12.dp))
            val readyToPrint = ledgerLpPrintSelection(buildResult())
            if (readyToPrint.isNotEmpty()) {
                Text(
                    "Listeye döndüğünüzde ${readyToPrint.size} LP seçili gelecek. " +
                        "Etiket almak için Seçilenleri Yazdır düğmesine basın.",
                    fontSize = 12.sp,
                )
            }
            Button(onClick = { onBuilt(buildResult()) }, modifier = Modifier.fillMaxWidth()) {
                Text(if (readyToPrint.isEmpty()) "LP Listesine Dön" else "Etiket Seçimine Geç (${readyToPrint.size})")
            }
            Spacer(Modifier.height(24.dp))
            return@SheetScaffold
        }

        ScanField(
            "Ürün No / Stok Kayıt No / Lot No",
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
        ) { Text(if (busy) "Aranıyor..." else "Stokları Getir") }

        if (entries.isNotEmpty()) {
            Spacer(Modifier.height(10.dp))
            Text("Kullanılacak Stok Kaydı", fontWeight = FontWeight.Bold, fontSize = 13.sp)
            if (entries.size > LEDGER_ENTRY_DISPLAY_LIMIT) {
                Text(
                        "Çok fazla kayıt bulundu; yalnızca en yeni $LEDGER_ENTRY_DISPLAY_LIMIT kayıt gösteriliyor. " +
                            "Daha eski bir kayıt için stok kayıt numarasıyla arayın.",
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
                            lpCountText = if (singleLpMode) "1" else DEFAULT_LEDGER_LP_COUNT
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
                            "LP yapılabilecek: ${formatLpQuantity(rowAllocatableQuantity)} " +
                                "${row.optString("baseUnitOfMeasure")} · ${row.optString("locationCode")}",
                            fontSize = 12.sp,
                        )
                        val detail = listOfNotNull(
                            row.optDouble("allocatedLpQuantity", 0.0)
                                .takeIf { row.has("allocatedLpQuantity") && it > 0.0 }
                                ?.let { "Daha önce LP yapılan ${formatLpQuantity(it)}" },
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
                "Raf (isteğe bağlı)",
                bin,
                { bin = it.uppercase() },
                modifier = Modifier.fillMaxWidth(),
                enabled = inputsEnabled,
            )
            Text(
                "Boş bırakırsanız sistem aynı ürün ve lotun bulunduğu rafları kod sırasıyla kullanır ve her LP'yi gerçek hedef rafına kaydeder. " +
                    "Yalnız tek raftaki stoğu kullanmak isterseniz raf etiketini okutun.",
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = lpCountText,
                    onValueChange = { lpCountText = it.filter(Char::isDigit).take(3) },
                    label = { Text("LP adedi") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    enabled = inputsEnabled && !singleLpMode,
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
            val uomLabel = entry.optString("baseUnitOfMeasure")
            Text(
                buildString {
                    append("Plan: ")
                    append("${lpCount ?: 0} × ${formatLpQuantity(quantityPerLp ?: 0.0)}")
                    if (remainderQuantity > 0.0)
                        append(" + 1 × ${formatLpQuantity(remainderQuantity)}")
                    append(" = ${formatLpQuantity(requestedQuantity)} $uomLabel")
                    append(" ($totalLpCount LP)")
                },
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (requestedQuantity > allocatableQuantity + 0.00001) MaterialTheme.colorScheme.error
                else MaterialTheme.colorScheme.onSurface,
            )
            Text(
                "LP'lenebilir kalan: ${formatLpQuantity(allocatableQuantity)} $uomLabel" +
                    (if (!planSupported && autoPlan != null && autoPlan.lastQuantity > 0.0)
                        " · Artık palet için BC güncellemesi gerekiyor; şimdilik yalnız tam paletler oluşturulur."
                    else ""),
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (lpCount != null && lpCount !in 1..100) {
                Text(
                    "Tek işlemde en fazla 100 LP oluşturabilirsiniz.",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.error,
                )
            }
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
            ) { Text(if (busy) "Kontrol ediliyor..." else "Önceki İşlemi Kontrol Et") }
        } else {
            Button(
                enabled = inputsEnabled && entry != null && template.isNotBlank() && planValid,
                modifier = Modifier.fillMaxWidth(),
                onClick = { submitBulkLp() },
            ) { Text(if (busy) "İşleniyor..." else if (singleLpMode) "Tekli LP'yi Oluştur" else "LP'leri Oluştur") }
        }
        Spacer(Modifier.height(24.dp))
    }
}
