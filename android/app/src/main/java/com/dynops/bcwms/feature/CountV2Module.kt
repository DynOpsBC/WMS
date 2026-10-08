package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.ui.graphics.luminance
import com.dynops.bcwms.ui.WmsGlyph
import com.dynops.bcwms.ui.WmsIcon
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.BarcodeKind
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.DocHeaderCard
import com.dynops.bcwms.ui.DocSearchBar
import com.dynops.bcwms.ui.EmptyState
import com.dynops.bcwms.ui.QuantityDialogSheet
import com.dynops.bcwms.ui.StatusText
import com.dynops.bcwms.ui.WmsRefreshLabel
import com.dynops.bcwms.ui.buildODataFilter
import com.dynops.bcwms.ui.firstValue
import com.dynops.bcwms.ui.searchClause
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.UUID

private data class CompletedCountV2Scan(
    val scanId: String,
    val binCode: String,
    val label: CountV2Label,
)

/** LP okutması: LP içeriği sunucuda satırlara açıldı; geri alma LP bazında yapılır. */
private data class CompletedCountV2Lp(val lpNo: String, val binCode: String, val counterSlot: Int)

private object PendingCountV2Store {
    private fun prefs(context: android.content.Context) = context.getSharedPreferences("bcwms_pending_count_v2", android.content.Context.MODE_PRIVATE)
    private fun key(context: android.content.Context, sheetNo: String): String =
        org.json.JSONArray(listOf(BcApi.getTenant(context), BcApi.getEnvironment(context), BcApi.getCompanyId(context), sheetNo)).toString()

    fun load(context: android.content.Context, sheetNo: String): Result<PendingCountV2Scan?> = runCatching {
        prefs(context).getString(key(context, sheetNo), null)?.let(PendingCountV2Scan::fromStoredJson)
    }

    fun save(context: android.content.Context, sheetNo: String, pending: PendingCountV2Scan): Boolean = runCatching {
        val existing = load(context, sheetNo).getOrThrow()
        if (existing != null && existing != pending) return@runCatching false
        prefs(context).edit().putString(key(context, sheetNo), pending.storedJson()).commit()
    }.getOrDefault(false)

    fun clear(context: android.content.Context, sheetNo: String): Boolean = runCatching {
        prefs(context).edit().remove(key(context, sheetNo)).commit()
    }.getOrDefault(false)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CountV2Module() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selected by remember { mutableStateOf<String?>(null) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var search by remember { mutableStateOf("") }
    var backendReady by remember { mutableStateOf(false) }
    var showCreate by remember { mutableStateOf(false) }
    var newLocation by remember { mutableStateOf("") }
    var newZone by remember { mutableStateOf("") }
    var zones by remember { mutableStateOf<List<String>>(emptyList()) }
    var zoneExpanded by remember { mutableStateOf(false) }
    var creating by remember { mutableStateOf(false) }
    val visibleRows = remember(rows, search) {
        val query = search.trim()
        if (query.isBlank()) rows
        else rows.filter { sheet ->
            sheet.optString("no").contains(query, ignoreCase = true) ||
                sheet.optString("roundRootNo").contains(query, ignoreCase = true) ||
                sheet.optString("locationCode").contains(query, ignoreCase = true) ||
                sheet.optString("zoneFilter").contains(query, ignoreCase = true) ||
                sheet.optString("status").contains(query, ignoreCase = true)
        }
    }

    fun loadZones() {
        val location = newLocation.trim()
        if (location.isBlank()) { zones = emptyList(); newZone = ""; return }
        scope.launch {
            val safe = location.replace("'", "''")
            val page = BcApi.getAllPages(context, "bins?\$filter=locationCode eq '$safe'&\$select=zoneCode&\$top=1000")
            zones = if (page.complete) page.rows.map { it.optString("zoneCode") }.filter(String::isNotBlank).distinct().sorted() else emptyList()
            if (newZone.isNotBlank() && newZone !in zones) newZone = ""
        }
    }

    fun load() {
        scope.launch {
            loading = true
            status = "Sayım sayfaları yükleniyor..."
            val filter = ""
            // Select kullanmamak eski/yeni AL paketleriyle listeyi uyumlu tutar;
            // V2 alanı yayınlandıysa aynı response içinde ayrıca gelir.
            val page = BcApi.getAllPages(
                context,
                "countSheets?\$top=100&\$orderby=createdDateTime desc$filter",
            )
            val capabilities = BcApi.getCountCapabilities(context)
            backendReady = capabilities.v2Ready
            rows = if (page.complete) page.rows.filter { it.optString("nextRoundNo").isBlank() } else emptyList()
            if (newLocation.isBlank())
                newLocation = rows.firstNotNullOfOrNull {
                    it.optString("locationCode").trim().takeIf(String::isNotBlank)
                }.orEmpty()
            loading = false
            status = when {
                !page.complete -> "HATA: Sayım listesinin tamamı alınamadı. Yenileyin."
                !capabilities.metadataLoaded -> "HATA: BC sayım özellikleri doğrulanamadı; bağlantıyı kontrol edin."
                !capabilities.v2Ready -> "HATA: Sayım V2 sunucu aksiyonları hazır değil — BCWMS AL 1.14.0.52 paketini yayınlayın."
                rows.isEmpty() -> "BOŞ: Sayım sayfası yok"
                else -> "TAMAM: ${rows.size} sayfa — yeni sayım için Yeni V2 Sayımı'na basın"
            }
        }
    }

    fun createV2() {
        val location = newLocation.trim()
        if (location.isBlank() || creating) return
        scope.launch {
            creating = true
            status = "$location lokasyonunda boş Sayım V2 oluşturuluyor..."
            val userId = BcApi.currentUserId(context).trim()
            if (userId.isBlank()) {
                creating = false
                status = "HATA: Terminal kullanıcı kimliği alınamadı. Yeniden giriş yapın."
                return@launch
            }

            val actionBody = JSONObject().apply {
                put("locationCode", location)
                put("userId", userId)
                if (newZone.isNotBlank()) put("zoneCode", newZone.trim())
            }.toString()
            var result = BcApi.boundAction(
                context,
                "countOps",
                "",
                if (newZone.isBlank()) "createV2" else "createV2Filtered",
                actionBody,
            )

            // AL 1.14.0.52 ile geriye uyumluluk: yeni atomik createV2 aksiyonu
            // henüz yayınlanmamışsa boş başlığı mevcut Count API üzerinden
            // oluştur. Belge ekranı idempotent prepareV2 çağrısıyla V2'ye geçirir.
            if ((result.httpCode == 404 || result.httpCode == 405) && newZone.isBlank()) {
                val legacyBody = JSONObject().apply {
                    put("locationCode", location)
                    put("mode", "Visible")
                }.toString()
                result = BcApi.post(context, "countSheets", legacyBody)
            }

            creating = false
            if (result.ok) {
                val createdNo = runCatching { JSONObject(result.body).optString("no") }
                    .getOrDefault("")
                    .ifBlank { BcApi.scalarValue(result.body).trim() }
                showCreate = false
                if (createdNo.isNotBlank()) selected = createdNo
                else {
                    status = "TAMAM: Boş Sayım V2 oluşturuldu. Listeden en yeni sayfayı açın."
                    load()
                }
            } else if (BcApi.isAmbiguousMutationFailure(result)) {
                showCreate = false
                status = "UYARI: Sunucu cevabı alınamadı. Mükerrer belge oluşturmamak için tekrar basmadan listeyi yenileyin."
                load()
            } else {
                // Diyalog açık kalırsa hata arkada kalır ve "hiçbir şey olmadı"
                // gibi görünür; kapat ki mesaj listede görünsün.
                showCreate = false
                status = "HATA: Sayım V2 oluşturulamadı — ${BcApi.errorMessage(result.body)}"
            }
        }
    }

    // Klasik Sayım ekranından "Sayım V2'de Aç" ile gelen belge doğrudan açılır.
    LaunchedEffect(Unit) {
        com.dynops.bcwms.CountV2Handoff.consume()?.let { selected = it }
        load()
    }
    selected?.let { no ->
        key(no) { CountV2Document(no = no, onBack = { selected = null; load() }, onRoundChanged = { selected = it }) }
        return
    }

    CountV2ErrorDialog(status, onDismiss = { status = "" })

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Card(
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)),
            shape = RoundedCornerShape(12.dp),
        ) {
            Column(Modifier.fillMaxWidth().padding(12.dp)) {
                Text("Sayım V2 — sadece okut", fontWeight = FontWeight.Bold)
                Text(
                    "Yeni V2 Sayımı Oluştur'a basın. Rafı okutun; sonra LP (MTE etiketi) okutunca LP içeriği, ürün/lot barkodu okutunca o rafın BC stoku olduğu gibi sayılır. Fark varsa satıra dokunup düzeltin.",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { load() }, enabled = !loading) { WmsRefreshLabel(loading) }
            Button(
                onClick = { showCreate = true; loadZones() },
                enabled = backendReady && !loading && !creating,
            ) { Text(if (creating) "Oluşturuluyor..." else "➕ Yeni V2 Sayımı") }
        }
        Spacer(Modifier.height(8.dp))
        DocSearchBar(value = search, onValueChange = { search = it }, onSearch = { load() }, label = "Sayım no ile ara")
        Spacer(Modifier.height(6.dp))
        if (!status.startsWith("HATA:")) StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(visibleRows) { sheet ->
                val posted = sheet.optString("status").equals("Posted", ignoreCase = true)
                val v2 = sheet.optBoolean("v2ScanMode", false)
                Card(
                    onClick = { selected = sheet.optString("no") },
                    enabled = !posted && backendReady,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(10.dp),
                ) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("${sheet.optString("roundRootNo").ifBlank { sheet.optString("no") }} · ${sheet.optInt("roundNo", 1)}. tur", fontWeight = FontWeight.Bold)
                            Text(
                                when {
                                    posted -> "Kapalı"
                                    v2 -> "V2 devam ediyor"
                                    else -> "Klasik veya boş belge"
                                },
                                fontSize = 12.sp,
                                color = if (v2) Color(0xFF15803D) else Color.Gray,
                            )
                        }
                        Text(
                            "Lokasyon: ${sheet.optString("locationCode")}" +
                                sheet.optString("zoneFilter").takeIf(String::isNotBlank)?.let { " · Alan: $it" }.orEmpty() +
                                " · ${sheet.optString("status")}",
                            fontSize = 12.sp,
                            color = Color.Gray,
                        )
                    }
                }
            }
            if (visibleRows.isEmpty() && !loading) {
                item {
                    EmptyState(
                        if (search.isBlank()) "Sayım sayfası yok."
                        else "Aramayla eşleşen sayım sayfası yok.",
                    )
                }
            }
        }
    }

    if (showCreate) {
        AlertDialog(
            onDismissRequest = { if (!creating) showCreate = false },
            title = { Text("Yeni V2 Sayımı Oluştur") },
            text = {
                Column {
                    Text("Sayım yapılacak Business Central lokasyon kodunu girin.")
                    Spacer(Modifier.height(10.dp))
                    OutlinedTextField(
                        value = newLocation,
                        onValueChange = { newLocation = it.uppercase(); newZone = "" },
                        label = { Text("Lokasyon Kodu") },
                        singleLine = true,
                        enabled = !creating,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    TextButton(onClick = { loadZones() }, enabled = newLocation.isNotBlank() && !creating) { Text("Alanları Getir") }
                    ExposedDropdownMenuBox(expanded = zoneExpanded, onExpandedChange = { zoneExpanded = !zoneExpanded }) {
                        OutlinedTextField(
                            value = newZone,
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("Alan filtresi (opsiyonel)") },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(zoneExpanded) },
                            modifier = Modifier.fillMaxWidth().menuAnchor(),
                        )
                        ExposedDropdownMenu(expanded = zoneExpanded, onDismissRequest = { zoneExpanded = false }) {
                            DropdownMenuItem(text = { Text("Tüm alanlar") }, onClick = { newZone = ""; zoneExpanded = false })
                            zones.forEach { zone ->
                                DropdownMenuItem(text = { Text(zone) }, onClick = { newZone = zone; zoneExpanded = false })
                            }
                        }
                    }
                    Text(
                        "Boş V2 belgesi otomatik oluşturulur; klasik satır üretmeniz gerekmez.",
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = { createV2() },
                    enabled = newLocation.isNotBlank() && !creating,
                ) { Text(if (creating) "Oluşturuluyor..." else "Oluştur ve Aç") }
            },
            dismissButton = {
                TextButton(onClick = { showCreate = false }, enabled = !creating) { Text("Vazgeç") }
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CountV2Document(no: String, onBack: () -> Unit, onRoundChanged: (String) -> Unit) {
    androidx.activity.compose.BackHandler { onBack() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var header by remember(no) { mutableStateOf<JSONObject?>(null) }
    var lines by remember(no) { mutableStateOf<List<JSONObject>>(emptyList()) }
    var linesComplete by remember(no) { mutableStateOf(false) }
    var busy by remember(no) { mutableStateOf(false) }
    var status by remember(no) { mutableStateOf("Sayım V2 hazırlanıyor...") }
    var prepared by remember(no) { mutableStateOf(false) }
    var myUserId by remember(no) { mutableStateOf("") }
    var adminTestSession by remember(no) { mutableStateOf(false) }
    var slot by remember(no) { mutableIntStateOf(1) }
    var activeBin by remember(no) { mutableStateOf("") }
    var binScan by remember(no) { mutableStateOf("") }
    var labelScan by remember(no) { mutableStateOf("") }
    var previousRaw by remember(no) { mutableStateOf("") }
    var previousAt by remember(no) { mutableLongStateOf(0L) }
    var pendingRetry by remember(no) { mutableStateOf<PendingCountV2Scan?>(null) }
    var pendingRestoreFailed by remember(no) { mutableStateOf(false) }
    var lastCompleted by remember(no) { mutableStateOf<CompletedCountV2Scan?>(null) }
    // Ürün/lot okutması raf stokundaki her lot için ayrı okutma üretir; geri alma hepsini kapsar.
    var lastBatch by remember(no) { mutableStateOf<List<CompletedCountV2Scan>>(emptyList()) }
    var lastCompletedLp by remember(no) { mutableStateOf<CompletedCountV2Lp?>(null) }
    // Satıra dokunarak sayılan miktarı düzeltme (fark varsa).
    var adjustLine by remember(no) { mutableStateOf<JSONObject?>(null) }
    // Sadece-okut: raf seçilince 2. alan, raf yokken 1. alan odaklı olsun ki
    // donanım tarayıcı okutması alana dokunmadan işlensin.
    val binFocus = remember { androidx.compose.ui.focus.FocusRequester() }
    val labelFocus = remember { androidx.compose.ui.focus.FocusRequester() }
    // Aynı raf + aynı miktarlı etiket (ham içerik) bu oturumda bir kez sayılır.
    var scannedQtyLabels by remember(no) { mutableStateOf(setOf<String>()) }
    var showPostConfirm by remember(no) { mutableStateOf(false) }
    var showNextRound by remember(no) { mutableStateOf(false) }
    var showComparison by remember(no) { mutableStateOf(false) }
    var history by remember(no) { mutableStateOf<List<Pair<JSONObject, List<JSONObject>>>>(emptyList()) }
    var comparisonLoading by remember(no) { mutableStateOf(false) }
    var comparisonError by remember(no) { mutableStateOf("") }
    var comparisonIndex by remember(no) { mutableIntStateOf(0) }
    var showFinishBin by remember(no) { mutableStateOf(false) }
    var unexpectedLabel by remember(no) { mutableStateOf<CountV2Label?>(null) }

    fun assignments(h: JSONObject?): List<CountSlotAssignment> = listOf(
        CountSlotAssignment(1, h?.optString("counter1UserId").orEmpty()),
        CountSlotAssignment(2, h?.optString("counter2UserId").orEmpty()),
        CountSlotAssignment(3, h?.optString("counter3UserId").orEmpty()),
    )

    fun configuredSlots(h: JSONObject?): List<Int> = assignments(h)
        .filter { it.userId.isNotBlank() }
        .map { it.slot }
        .ifEmpty { listOf(1) }

    fun operatorSlots(h: JSONObject?): List<Int> = assignedCountSlotsForOperator(
        assignments = assignments(h),
        currentUserId = myUserId,
        adminTestSession = adminTestSession,
    )

    // Başlık $select olmadan okunur; terminalPostAllowed alanı AL paketi
    // yayınladığında aynı cevapta gelir, eski paketlerde hiç gelmez (= izinli).
    fun terminalPostAllowed(h: JSONObject?): Boolean = terminalCountPostAllowed(
        hasFlag = h?.has("terminalPostAllowed") == true,
        flag = h?.optBoolean("terminalPostAllowed", false) == true,
    )

    suspend fun loadDocument(): Boolean {
        val safeNo = no.replace("'", "''")
        val headerResult = BcApi.get(context, "countSheets('$safeNo')")
        val loadedHeader = if (headerResult.ok) runCatching { JSONObject(headerResult.body) }.getOrNull() else null
        val page = BcApi.getAllPages(
            context,
            "countSheetLines?\$filter=sheetNo eq '$safeNo'&\$top=200",
        )
        if (loadedHeader?.optString("nextRoundNo").orEmpty().isNotBlank()) {
            onRoundChanged(loadedHeader!!.optString("nextRoundNo"))
            return false
        }
        header = loadedHeader
        lines = if (page.complete) page.rows else emptyList()
        linesComplete = loadedHeader != null && page.complete
        prepared = loadedHeader?.optBoolean("v2ScanMode", false) == true
        val allowed = operatorSlots(loadedHeader)
        if (allowed.isNotEmpty() && slot !in allowed) slot = allowed.first()
        if (!linesComplete) {
            status = "HATA: Belge ve tüm satırlar alınamadı; okutma kapatıldı."
            return false
        }
        return true
    }

    fun reload(successMessage: String = "") {
        scope.launch {
            busy = true
            val loaded = loadDocument()
            busy = false
            if (loaded && successMessage.isNotBlank()) status = successMessage
        }
    }

    LaunchedEffect(no) {
        busy = true
        myUserId = BcApi.currentUserId(context).trim()
        adminTestSession = BcApi.isAdminTestSession(context)
        val capabilities = BcApi.getCountCapabilities(context)
        if (!capabilities.v2Ready) {
            status = if (!capabilities.metadataLoaded)
                "HATA: BC sayım özellikleri doğrulanamadı; bağlantıyı kontrol edin."
            else
                "HATA: Sayım V2 sunucu aksiyonları hazır değil — BCWMS AL 1.14.0.52 paketini yayınlayın."
            busy = false
            return@LaunchedEffect
        }
        if (!loadDocument()) {
            busy = false
            return@LaunchedEffect
        }
        val h = header
        if (h?.optString("status").equals("Posted", ignoreCase = true)) {
            status = "Bu sayım kaydedilmiş ve kapatılmıştır."
            busy = false
            return@LaunchedEffect
        }
        if (!prepared && lines.isNotEmpty()) {
            // The guidance card below is the single source of truth.  Keeping
            // status empty avoids showing the same long explanation twice.
            status = ""
            busy = false
            return@LaunchedEffect
        }
        if (!prepared) {
            val result = BcApi.boundAction(context, "countSheets", no, "prepareV2", "{}")
            if (!result.ok) {
                status = "HATA: ${BcApi.errorMessage(result.body)} (HTTP ${result.httpCode})" +
                    if (result.httpCode == 404 || result.httpCode == 405) " — güncel BCWMS AL paketini yayınlayın" else ""
                busy = false
                return@LaunchedEffect
            }
            loadDocument()
        }
        val restored = PendingCountV2Store.load(context, no)
        pendingRestoreFailed = restored.isFailure
        pendingRetry = restored.getOrNull()
        pendingRetry?.let { pending ->
            activeBin = pending.binCode
            if (pending.counterSlot in operatorSlots(header)) slot = pending.counterSlot
        }
        status = when {
            pendingRestoreFailed -> "HATA: Cihazdaki bekleyen sayım işlemi okunamadı · yeni işlem başlatmadan destek isteyin"
            pendingRetry != null -> "UYARI: Önceki okutmanın sonucu bekleniyor · aynı işlem kimliğiyle tekrar kontrol edin"
            prepared -> "TAMAM: V2 hazır — önce rafı, sonra LP / ürün / lot barkodunu okutun"
            else -> status
        }
        busy = false
    }

    fun selectBin(raw: String) {
        if (countV2HasBlockingError(status)) return
        val value = BarcodeIntentResolver.resolve(raw).value.trim().ifBlank { raw.trim() }
        binScan = ""
        if (value.isBlank() || !prepared || busy || pendingRetry != null || pendingRestoreFailed) return
        if (header?.optBoolean("binReviewSupported", false) != true) {
            status = "Raf tamamlama için Business Central sayım güncellemesi gerekli."
            return
        }
        scope.launch {
            busy = true
            status = "$value rafı doğrulanıyor..."
            val safeBin = value.replace("'", "''")
            val safeLocation = header?.optString("locationCode").orEmpty().replace("'", "''")
            val safeZone = header?.optString("zoneFilter").orEmpty().replace("'", "''")
            val filters = buildList {
                add("code eq '$safeBin'")
                if (safeLocation.isNotBlank()) add("locationCode eq '$safeLocation'")
                if (safeZone.isNotBlank()) add("zoneCode eq '$safeZone'")
            }.joinToString(" and ")
            val result = BcApi.get(context, "bins?\$filter=$filters&\$select=code,locationCode,zoneCode&\$top=1")
            val row = if (result.ok) BcApi.parseValueArray(result.body).firstOrNull() else null
            if (row == null) {
                status = "HATA: $value rafı bu sayımın lokasyon/alan filtresinde bulunamadı"
            } else {
                val bin = row.optString("code").ifBlank { value }
                val prepare = BcApi.boundAction(context, "countSheets", no, "prepareV2Bin", JSONObject().put("binCode", bin).toString())
                if (!prepare.ok) {
                    status = "HATA: ${BcApi.errorMessage(prepare.body)}"
                    busy = false
                    return@launch
                }
                if (!loadDocument()) { busy = false; return@launch }
                activeBin = row.optString("code").ifBlank { value }
                labelScan = ""
                previousRaw = ""
                previousAt = 0L
                pendingRetry = null
                lastCompleted = null
                lastBatch = emptyList()
                lastCompletedLp = null
                status = "TAMAM: 📍 $activeBin — şimdi LP / ürün / lot barkodunu okutun"
            }
            busy = false
        }
    }

    suspend fun postScan(pending: PendingCountV2Scan, reloadAfter: Boolean = true): Boolean {
        if (pending.counterSlot !in operatorSlots(header)) {
            status = "HATA: Bekleyen işlem ${pending.counterSlot} sayıcısına ait · bu sayıcıyla giriş yapın"
            return false
        }
        if (!PendingCountV2Store.save(context, no, pending)) {
            status = "HATA: Okutma cihazda güvenle saklanamadı · işlem gönderilmedi"
            pendingRestoreFailed = true
            return false
        }
        pendingRetry = null
        status = "${pending.label.itemNo} · ${formatCountV2Qty(pending.label.quantity)} kaydediliyor..."
        val body = pending.payload()
        val result = BcApi.boundAction(context, "countSheets", no, "scanV2Label", body)
        if (result.ok) {
            if (!PendingCountV2Store.clear(context, no)) {
                pendingRetry = pending
                status = "UYARI: Sayım kaydedildi · cihazdaki bekleyen işlem temizlenemedi · aynı işlemi tekrar kontrol edin"
                return false
            }
            lastCompleted = CompletedCountV2Scan(pending.scanId, pending.binCode, pending.label)
            lastBatch = emptyList()
            lastCompletedLp = null
            labelScan = ""
            if (reloadAfter) reload(
                "TAMAM: ${pending.label.itemNo}" +
                    pending.label.lotNo.takeIf { it.isNotBlank() }?.let { " · Lot $it" }.orEmpty() +
                    " · ${formatCountV2Qty(pending.label.quantity)} ${pending.label.unitOfMeasureCode} → ${pending.binCode} eklendi"
            )
            return true
        }
        if (BcApi.isAmbiguousMutationFailure(result)) {
            pendingRetry = pending
            status = "UYARI: Sunucu cevabı alınamadı; kayıt ulaşmış olabilir. Aynı işlem kimliğiyle güvenli tekrar deneyin — QR'ı yeniden okutmayın."
        } else {
            pendingRestoreFailed = !PendingCountV2Store.clear(context, no)
            scannedQtyLabels = scannedQtyLabels - "${pending.binCode}|${pending.label.raw.trim()}"
            status = "HATA: ${BcApi.errorMessage(result.body)} (HTTP ${result.httpCode})" +
                if (result.httpCode == 404 || result.httpCode == 405) " — güncel BCWMS AL paketini yayınlayın" else ""
        }
        return false
    }

    fun sendScan(pending: PendingCountV2Scan) {
        if (countV2HasBlockingError(status)) return
        if (busy || pendingRestoreFailed) return
        scope.launch {
            busy = true
            postScan(pending)
            busy = false
        }
    }

    /**
     * MTE/LP etiketi: LP içeriği sunucuda olduğu gibi sayılır (ürün, lot, seri,
     * birim, miktar). Operatör hiçbir şey girmez; tekrar okutma miktarı toplamaz.
     */
    fun scanLp(lpNo: String) {
        if (countV2HasBlockingError(status)) return
        scope.launch {
            busy = true
            status = "$lpNo LP içeriği $activeBin rafında sayılıyor..."
            val body = JSONObject().apply {
                put("scanId", UUID.randomUUID().toString())
                put("lpNo", lpNo)
                put("binCode", activeBin)
                put("counterSlot", slot)
            }.toString()
            val result = BcApi.boundAction(context, "countSheets", no, "scanV2Lp", body)
            busy = false
            when {
                result.ok -> {
                    val n = BcApi.scalarValue(result.body).toIntOrNull() ?: 0
                    lastCompleted = null
                    lastBatch = emptyList()
                    lastCompletedLp = CompletedCountV2Lp(lpNo, activeBin, slot)
                    labelScan = ""
                    busy = true
                    if (loadDocument()) {
                        val finding = lines.firstOrNull { it.optString("lpNo") == lpNo &&
                            it.optString("binCode") == activeBin && it.optString("foundFromBin").isNotBlank() }
                        status = if (finding != null)
                            "UYARI: LP $lpNo · sistem rafı ${finding.optString("foundFromBin")} → bulunan raf $activeBin · raf farkı kaydedildi, taşıma yapılmadı"
                        else "TAMAM: LP $lpNo → $n satır $activeBin rafında sayıldı"
                    }
                    busy = false
                }
                result.httpCode == 404 || result.httpCode == 405 ||
                    BcApi.errorMessage(result.body).contains("scanV2Lp", ignoreCase = true) ->
                    status = "HATA: LP okutma için güncel BCWMS AL paketi (scanV2Lp) yayınlanmalı."
                else -> status = "HATA: ${BcApi.errorMessage(result.body)} (HTTP ${result.httpCode})"
            }
        }
    }

    /**
     * Miktarsız ürün/lot barkodu: okutulan rafın BC stoku (lot ve birim bazında)
     * "burada" diye teyit edilir; her lot ayrı satır olur. Operatör yalnız fark
     * varsa satıra dokunup düzeltir. Rafta stok yoksa lotun/ürünün lokasyondaki
     * BC miktarı bu rafa yazılır; hiç yoksa yalnız uyarı (pencere açılmaz).
     */
    fun autoCountFromStock(candidate: CountV2ManualCandidate) {
        scope.launch {
            busy = true
            val loc = header?.optString("locationCode").orEmpty()
            fun safe(v: String) = v.replace("'", "''")
            val what = candidate.itemNo.ifBlank { "Lot ${candidate.lotNo}" }
            status = "$what için $activeBin raf stoku okunuyor..."
            val lotFilters = buildList {
                add("locationCode eq '${safe(loc)}'")
                add("binCode eq '${safe(activeBin)}'")
                if (candidate.itemNo.isNotBlank()) add("itemNo eq '${safe(candidate.itemNo)}'")
                if (candidate.lotNo.isNotBlank()) add("lotNo eq '${safe(candidate.lotNo)}'")
            }.joinToString(" and ")
            val lotPage = BcApi.getAllPages(context, "availableLots?\$filter=$lotFilters&\$top=200")
            var complete = lotPage.complete
            var rows = if (lotPage.complete) lotPage.rows.filter { it.optDouble("quantityBase", 0.0) > 0.0 } else emptyList()
            if (rows.isEmpty() && candidate.itemNo.isNotBlank() && candidate.lotNo.isBlank()) {
                val page = BcApi.getAllPages(
                    context,
                    "binContents?\$filter=locationCode eq '${safe(loc)}' and binCode eq '${safe(activeBin)}' and itemNo eq '${safe(candidate.itemNo)}'&\$top=50",
                )
                if (page.complete) rows = page.rows.filter { it.optDouble("quantity", 0.0) > 0.0 } else complete = false

                // Düz metin barkodu madde numarası da yalnız lot numarası da
                // olabilir. Önce gerçek maddeyi tercih et; BC'de bu madde hiç
                // yoksa aynı değeri lot olarak ara. Lot etiketi böylece manuel
                // miktar/UOM ekranına düşmeden ürününü ve raf bakiyesini çözer.
                if (rows.isEmpty() && complete) {
                    val itemPage = BcApi.getAllPages(
                        context,
                        "items?\$filter=no eq '${safe(candidate.itemNo)}'&\$select=no&\$top=1",
                    )
                    if (!itemPage.complete) {
                        complete = false
                    } else if (itemPage.rows.none { it.optString("no").equals(candidate.itemNo, ignoreCase = true) }) {
                        val byLotPage = BcApi.getAllPages(
                            context,
                            "availableLots?\$filter=locationCode eq '${safe(loc)}' and binCode eq '${safe(activeBin)}' and lotNo eq '${safe(candidate.itemNo)}'&\$top=200",
                        )
                        if (byLotPage.complete)
                            rows = byLotPage.rows.filter { it.optDouble("quantityBase", 0.0) > 0.0 }
                        else
                            complete = false
                    }
                }
            }
            // Another bin can resolve the label identity, never the physical quantity.
            var fromOtherBin = false
            // Yalnız LOT okutmasında (tek lot, fiziksel etiket elde) lokasyon
            // genelinden yedek okuma yapılır. Düz ürün okutmasında lokasyon
            // toplamını rafa yazmak mükerrer stok üretir (K.K03.11'e 500 ADET
            // gibi) — o yolda satır açılmaz, operatör lot/LP okutur.
            if (rows.isEmpty() && complete && candidate.lotNo.isNotBlank()) {
                val locPage = BcApi.getAllPages(
                    context,
                    "availableLots?\$filter=locationCode eq '${safe(loc)}' and lotNo eq '${safe(candidate.lotNo)}'" +
                        (if (candidate.itemNo.isNotBlank()) " and itemNo eq '${safe(candidate.itemNo)}'" else "") + "&\$top=200",
                )
                if (!locPage.complete) complete = false
                rows = if (locPage.complete) locPage.rows
                    .filter { it.optDouble("quantityBase", 0.0) > 0.0 }
                    .groupBy { row -> listOf("itemNo", "variantCode", "lotNo", "serialNo", "unitOfMeasureCode").map { row.optString(it) } }
                    .map { (_, group) ->
                        JSONObject(group.first().toString()).apply {
                            put("quantity", group.sumOf { it.optDouble("quantity", 0.0) })
                            put("quantityBase", group.sumOf { it.optDouble("quantityBase", 0.0) })
                            put("sourceBins", group.joinToString(", ") { it.optString("binCode") })
                        }
                    } else emptyList()
                fromOtherBin = rows.isNotEmpty()
            }
            if (rows.isEmpty()) {
                if (complete && candidate.itemNo.isNotBlank()) {
                    val item = BcApi.get(context, "items?\$filter=no eq '${safe(candidate.itemNo)}'&\$top=1")
                    val itemRow = if (item.ok) BcApi.parseValueArray(item.body).firstOrNull() else null
                    if (itemRow != null) {
                        // BADE (16 Eyl 2026): ürün BC'de başka rafta kayıtlıysa operatör
                        // bunu görsün; kayıtta stok oradan bu rafa taşınır.
                        val otherBins = BcApi.getAllPages(
                            context,
                            "binContents?\$filter=locationCode eq '${safe(loc)}' and itemNo eq '${safe(candidate.itemNo)}'&\$top=50",
                        )
                        unexpectedLabel = CountV2Label(candidate.itemNo, "", itemRow.optString("baseUnitOfMeasure"),
                            candidate.lotNo, candidate.serialNo, 1.0, candidate.raw)
                        busy = false
                        status = if (otherBins.complete) unexpectedStockHint(activeBin, otherBins.rows)
                            else "Bu rafta fiziksel olarak bulduğunuz miktarı girin"
                        return@launch
                    }
                }
                busy = false
                status = when {
                    !complete -> "HATA: Stok okunamadı. Yenileyip tekrar okutun."
                    candidate.lotNo.isNotBlank() -> "HATA: ${candidate.lotNo} lotu $loc lokasyonunda BC stokunda yok. LP okutun veya BC'de kontrol edin."
                    else -> "HATA: '${candidate.itemNo}' BC'de madde numarası olarak bulunamadı. Ürünün BCWMS etiketini (madde no) ya da LP/lot etiketini okutun; barkod GTIN ise BC'de madde referansı tanımlı olmalı."
                }
                return@launch
            }
            if (fromOtherBin) {
                busy = false
                if (rows.size != 1) {
                    status = "Etiket birden fazla stok kaydıyla eşleşiyor · ürün ve lot içeren etiketi okutun"
                    return@launch
                }
                val row = rows.single()
                unexpectedLabel = CountV2Label(row.optString("itemNo"), row.optString("variantCode"),
                    row.optString("unitOfMeasureCode"), row.optString("lotNo"), row.optString("serialNo"), 1.0, candidate.raw)
                status = "Ürün başka rafta kayıtlı · burada bulduğunuz miktarı girin"
                return@launch
            }
            val batch = mutableListOf<CompletedCountV2Scan>()
            var skipped = 0
            var total = 0.0
            for (row in rows) {
                val itemNo = row.optString("itemNo").ifBlank { candidate.itemNo }
                val lotNo = row.optString("lotNo")
                val uom = row.optString("unitOfMeasureCode")
                val variantCode = row.optString("variantCode")
                val serialNo = row.optString("serialNo")
                val expected = lines.filter { it.optString("binCode") == activeBin &&
                    it.optString("itemNo") == itemNo && it.optString("lotNo") == lotNo &&
                    it.optString("variantCode") == variantCode && it.optString("serialNo") == serialNo && it.optString("unitOfMeasureCode") == uom }
                if (expected.any { it.optString("lpNo").isNotBlank() } && expected.none { it.optString("lpNo").isBlank() }) {
                    busy = false
                    status = "Bu stok LP içinde kayıtlı · LP etiketini okutun"
                    if (batch.isNotEmpty()) { lastBatch = batch.toList(); reload() }
                    return@launch
                }
                val qty = expected.filter { it.optString("lpNo").isBlank() }.sumOf { it.optDouble("systemQty", 0.0) }
                    .takeIf { it > 0.0 } ?: (row.optDouble("quantity", 0.0).takeIf { it > 0.0 } ?: row.optDouble("quantityBase", 0.0))
                // Aynı raf/ürün/lot bu sayıcı için zaten sayıldıysa ikinci okutma
                // miktarı toplamasın; düzeltme satıra dokunarak yapılır.
                val already = lines.any { l ->
                    l.optString("binCode") == activeBin && l.optString("itemNo") == itemNo &&
                    l.optString("lotNo") == lotNo && l.optString("unitOfMeasureCode") == uom &&
                        l.optString("variantCode") == variantCode && l.optString("serialNo") == serialNo &&
                        l.optString("lpNo").isBlank() &&
                        isCountRecorded(l.has("counted$slot"), l.optBoolean("counted$slot"), l.optDouble("countedQty$slot", 0.0))
                }
                if (already) { skipped++; continue }
                val pending = PendingCountV2Scan(
                    scanId = UUID.randomUUID().toString(),
                    counterSlot = slot,
                    binCode = activeBin,
                    label = CountV2Label(
                        itemNo = itemNo,
                        variantCode = variantCode,
                        unitOfMeasureCode = uom,
                        lotNo = lotNo,
                        serialNo = serialNo,
                        quantity = qty,
                        raw = candidate.raw,
                    ),
                )
                if (!postScan(pending, reloadAfter = false)) {
                    busy = false
                    if (batch.isNotEmpty()) { lastBatch = batch.toList(); lastCompletedLp = null; reload() }
                    return@launch
                }
                batch += CompletedCountV2Scan(pending.scanId, activeBin, pending.label)
                total += qty
            }
            busy = false
            if (batch.isEmpty()) {
                status = "ℹ️ $what bu rafta zaten sayıldı. Farklıysa satıra dokunup düzeltin."
                return@launch
            }
            lastCompleted = null
            lastBatch = batch.toList()
            lastCompletedLp = null
            labelScan = ""
            val first = batch.first().label
            reload(
                (if (fromOtherBin) "UYARI: " else "TAMAM: ") + "${first.itemNo} · ${batch.size} satır · toplam ${formatCountV2Qty(total)} ${first.unitOfMeasureCode} " +
                    (if (fromOtherBin) "$activeBin rafına yazıldı — DİKKAT: BC bu lotu ${batch.firstOrNull()?.let { rows.firstOrNull()?.optString("sourceBins") }.orEmpty().ifBlank { "başka rafta" }} rafında biliyor; o rafı da sayın" else "$activeBin rafında teyit edildi") +
                    (if (skipped > 0) " ($skipped satır zaten sayılıydı)" else "") +
                    " — farklıysa satıra dokunup düzeltin"
            )
        }
    }

    fun recordLineCount(line: JSONObject, qty: Double) {
        if (countV2HasBlockingError(status)) return
        if (busy || pendingRetry != null || pendingRestoreFailed) return
        if (!qty.isFinite() || qty < 0.0) { status = "HATA: Geçerli bir sayım miktarı girin."; return }
        scope.launch {
            busy = true
            status = "${line.optString("itemNo")} → ${formatCountV2Qty(qty)} kaydediliyor..."
            val key = "sheetNo='${no.replace("'", "''")}',lineNo=${line.optInt("lineNo")}"
            val body = JSONObject().apply { put("counterSlot", slot); put("qty", qty) }.toString()
            val r = BcApi.boundAction(context, "countSheetLines", key, "recordCount", body)
            busy = false
            if (r.ok) {
                lastCompleted = null; lastBatch = emptyList(); lastCompletedLp = null
                reload("TAMAM: ${line.optString("itemNo")} → ${formatCountV2Qty(qty)} ${line.optString("unitOfMeasureCode")} olarak düzeltildi")
            } else status = "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
        }
    }

    fun scanLabel(raw: String) {
        if (countV2HasBlockingError(status)) return
        labelScan = ""
        if (activeBin.isBlank()) {
            status = "HATA: Önce raf barkodunu okutun."
            return
        }
        if (!prepared || busy || pendingRetry != null || pendingRestoreFailed) return
        val now = System.currentTimeMillis()
        if (isRapidCountV2Duplicate(previousRaw, previousAt, raw, now)) {
            status = "ℹ️ Aynı tarayıcı olayı ikinci kez geldi; mükerrer miktar eklenmedi."
            return
        }
        val resolved = BarcodeIntentResolver.resolve(raw)
        if (resolved.kind == BarcodeKind.Lp) {
            previousRaw = raw
            previousAt = now
            scanLp(resolved.value.trim())
            return
        }
        countV2ManualCandidate(resolved)?.let { candidate ->
            previousRaw = raw
            previousAt = now
            autoCountFromStock(candidate)
            return
        }
        when (val validation = validateCountV2Label(resolved)) {
            is CountV2LabelResult.Invalid -> status = "HATA: ${validation.message}"
            is CountV2LabelResult.Valid -> {
                val labelKey = "$activeBin|${raw.trim()}"
                if (labelKey in scannedQtyLabels) {
                    status = "ℹ️ Bu etiket $activeBin rafında zaten okutuldu; miktar ikinci kez eklenmedi. Farklıysa satıra dokunup düzeltin."
                    return
                }
                scannedQtyLabels = scannedQtyLabels + labelKey
                previousRaw = raw
                previousAt = now
                sendScan(
                    PendingCountV2Scan(
                        scanId = UUID.randomUUID().toString(),
                        counterSlot = slot,
                        binCode = activeBin,
                        label = validation.label,
                    )
                )
            }
        }
    }

    fun undoLastScan() {
        if (countV2HasBlockingError(status)) return
        lastCompletedLp?.let { lp ->
            scope.launch {
                busy = true
                status = "${lp.lpNo} LP okutması geri alınıyor..."
                val body = JSONObject().apply {
                    put("lpNo", lp.lpNo); put("binCode", lp.binCode); put("counterSlot", lp.counterSlot)
                }.toString()
                val r = BcApi.boundAction(context, "countSheets", no, "undoV2Lp", body)
                busy = false
                if (r.ok) { lastCompletedLp = null; reload("TAMAM: ${lp.lpNo} LP okutması geri alındı") }
                else status = "HATA: ${BcApi.errorMessage(r.body)} (HTTP ${r.httpCode})"
            }
            return
        }
        val batch = lastBatch.ifEmpty { listOfNotNull(lastCompleted) }
        if (batch.isEmpty()) return
        scope.launch {
            busy = true
            status = "Son okutma geri alınıyor..."
            var failed: BcApi.ApiResult? = null
            for (completed in batch.asReversed()) {
                val body = JSONObject().apply { put("scanId", completed.scanId) }.toString()
                val result = BcApi.boundAction(context, "countSheets", no, "undoV2Scan", body)
                if (!result.ok) { failed = result; break }
            }
            busy = false
            val f = failed
            if (f == null) {
                // Geri alınan etiketler yeniden okutulabilmeli.
                scannedQtyLabels = scannedQtyLabels - batch.map { "${it.binCode}|${it.label.raw.trim()}" }.toSet()
                lastCompleted = null
                lastBatch = emptyList()
                reload("TAMAM: Son okutma geri alındı; miktar ikinci kez düşülmez")
            } else {
                status = if (BcApi.isAmbiguousMutationFailure(f))
                    "UYARI: Geri alma cevabı belirsiz. Aynı 'Son okutmayı geri al' düğmesine tekrar basmak güvenlidir."
                else
                    "HATA: ${BcApi.errorMessage(f.body)} (HTTP ${f.httpCode})"
            }
        }
    }

    fun startNextRound() {
        if (busy || pendingRetry != null || pendingRestoreFailed) return
        showNextRound = false
        scope.launch {
            busy = true
            val result = BcApi.boundActionLongRunning(context, "countSheets", no, "startNextRound", "{}")
            busy = false
            val nextNo = if (result.ok) BcApi.scalarValue(result.body).trim().trim('"') else ""
            if (nextNo.isNotBlank()) onRoundChanged(nextNo)
            else status = if (BcApi.isAmbiguousMutationFailure(result))
                "UYARI: Yeni tur yanıtı alınamadı. Yeni Tur Başlat'ı tekrar kullanabilirsiniz; ikinci bir tur oluşturulmaz."
            else "HATA: ${BcApi.errorMessage(result.body)}"
        }
    }

    fun loadComparison() {
        showComparison = true
        comparisonLoading = true
        comparisonError = ""
        history = emptyList()
        comparisonIndex = 0
        scope.launch {
            // Refresh current quantities as well; comparing old cached values
            // against another operator's latest round would be misleading.
            if (!loadDocument()) {
                comparisonLoading = false
                comparisonError = "Güncel tur alınamadı. Yenileyin."
                return@launch
            }
            var previousNo = header?.optString("previousRoundNo").orEmpty()
            val seen = mutableSetOf(no)
            val loaded = mutableListOf<Pair<JSONObject, List<JSONObject>>>()
            while (previousNo.isNotBlank()) {
                if (!seen.add(previousNo)) { comparisonError = "Tur geçmişi tutarsız; yeniden yükleyin."; break }
                val safe = previousNo.replace("'", "''")
                val result = BcApi.get(context, "countSheets('$safe')")
                val oldHeader = if (result.ok) runCatching { JSONObject(result.body) }.getOrNull() else null
                val page = BcApi.getAllPages(context, "countSheetLines?\$filter=sheetNo eq '$safe'&\$top=200")
                if (oldHeader == null || !page.complete) { comparisonError = "Tur geçmişinin tamamı alınamadı. Yeniden deneyin."; break }
                loaded += oldHeader to page.rows
                previousNo = oldHeader.optString("previousRoundNo")
            }
            if (comparisonError.isBlank()) history = loaded
            comparisonLoading = false
        }
    }

    fun postSheet() {
        if (countV2HasBlockingError(status)) return
        if (countV2HasBinFindings(lines)) {
            showPostConfirm = false
            status = countV2BinFindingsNote(header?.optBoolean("countRoundSupported") == true)
            return
        }
        if (!terminalPostAllowed(header)) {
            showPostConfirm = false
            status = COUNT_POSTED_IN_BC_NOTE
            return
        }
        scope.launch {
            busy = true
            status = "Sayım onaylanıyor ve stok hareketleri oluşturuluyor..."
            val result = BcApi.boundActionLongRunning(context, "countSheets", no, "postSheet", "{}")
            busy = false
            showPostConfirm = false
            if (result.ok) reload("TAMAM: Sayım onaylandı; stok farkları işlendi ve belge kapatıldı")
            else {
                status = "HATA: ${BcApi.errorMessage(result.body)} (HTTP ${result.httpCode})"
                reload()
            }
        }
    }

    fun completeCounter() {
        if (countV2HasBlockingError(status)) return
        scope.launch {
            busy = true
            status = "$slot. sayım turu kaydedilip kilitleniyor..."
            val body = JSONObject().apply { put("counterSlot", slot) }.toString()
            val result = BcApi.boundAction(context, "countSheets", no, "completeCounter", body)
            busy = false
            if (result.ok) {
                loadDocument()
                if (linesComplete) status = if (countV2HasBinFindings(lines))
                    "TAMAM: $slot. sayım turu kaydedildi. $COUNT_V2_BIN_FINDINGS_NOTE"
                else countRoundSavedMessage(slot, terminalPostAllowed(header))
            } else status = "HATA: ${BcApi.errorMessage(result.body)} (HTTP ${result.httpCode})"
        }
    }

    fun finishBin() {
        if (countV2HasBlockingError(status)) return
        scope.launch {
            busy = true
            val bin = activeBin
            val result = BcApi.boundAction(context, "countSheets", no, "completeV2Bin",
                JSONObject().put("binCode", bin).put("counterSlot", slot).toString())
            showFinishBin = false
            if (result.ok) {
                activeBin = ""
                lastCompleted = null; lastBatch = emptyList(); lastCompletedLp = null
                if (loadDocument()) status = "TAMAM: $bin tamamlandı · sayılmayanlar $slot sayımında 0 · bekleyen rafları da sayın"
            } else status = "HATA: ${BcApi.errorMessage(result.body)}"
            busy = false
        }
    }

    val h = header
    val allowedSlots = operatorSlots(h)
    val requiredSlots = configuredSlots(h)
    val allRequiredComplete = requiredSlots.all { requiredSlot ->
        allRequiredCountLinesExplicitlyCompleted(lines.map { line ->
            CountSlotLineState(
                hasExplicitFlag = line.has("counted$requiredSlot"),
                explicitlyCounted = line.optBoolean("counted$requiredSlot"),
                quantity = line.optDouble("countedQty$requiredSlot", Double.NaN),
            )
        })
    }
    val currentSlotLinesComplete = allRequiredCountLinesExplicitlyCompleted(lines.map { line ->
        CountSlotLineState(
            hasExplicitFlag = line.has("counted$slot"),
            explicitlyCounted = line.optBoolean("counted$slot"),
            quantity = line.optDouble("countedQty$slot", Double.NaN),
        )
    })
    val currentSlotSaved = h?.optBoolean("counter${slot}Completed", false) == true
    val allRequiredSaved = requiredSlots.all { h?.optBoolean("counter${it}Completed", false) == true }
    val binReviewSupported = h?.optBoolean("binReviewSupported", false) == true
    val varianceGroups = countV2VarianceGroups(lines, slot, allRequiredSaved)
    val varianceReview = countV2VarianceReviewText(varianceGroups)
    // Başlık yüklenmeden düğme hiç çizilmez (null başlık = izinli sayılmaz); yüklenen
    // eski AL paketi başlığında bayrak yoksa "izinli" kuralı korunur.
    val postAllowed = countV2PostButtonVisible(headerLoaded = h != null, terminalPostAllowed = terminalPostAllowed(h))
    val hasBinFindings = countV2HasBinFindings(lines)
    val blockingError = countV2HasBlockingError(status)
    val canSave = !blockingError && !pendingRestoreFailed && pendingRetry == null && binReviewSupported && prepared && linesComplete && lines.isNotEmpty() && !busy && slot in allowedSlots &&
        currentSlotLinesComplete && !currentSlotSaved && countDocumentIsMutable(h?.optString("status").orEmpty())
    val canPost = !blockingError && !hasBinFindings && !pendingRestoreFailed && pendingRetry == null && binReviewSupported && postAllowed && prepared && linesComplete && lines.isNotEmpty() && !busy &&
        allRequiredComplete && allRequiredSaved &&
        lines.none { it.optBoolean("recountRequired") } &&
        countDocumentIsMutable(h?.optString("status").orEmpty())

    // Keep the dialog outside LazyColumn so errors remain visible even when the header is off-screen.
    CountV2ErrorDialog(status, onDismiss = { status = "" })

    Column(Modifier.fillMaxSize()) {
        // Tek kaydırma alanı: başlık ve okutma kontrolleri yukarı
        // kaydığında otomatik oluşan satırlar terminal ekranının
        // tamamına yakınını kullanır. Alt kayıt çubuğu listeyi
        // kapatmadan sabit kalır.
        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = 8.dp, bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            item {
                Column {
                    TextButton(onClick = onBack, enabled = !busy) { Text("‹ Sayfa Listesi") }
                    DocHeaderCard(
                        title = "${h?.optString("roundRootNo").orEmpty().ifBlank { no }} · ${h?.optInt("roundNo", 1) ?: 1}. tur",
                        subtitle = "Lokasyon: ${h?.optString("locationCode").orEmpty()}" +
                            h?.optString("zoneFilter").orEmpty().takeIf(String::isNotBlank)?.let { " · Alan: $it" }.orEmpty() +
                            " · ${h?.optString("status").orEmpty()}",
                    )
                    Spacer(Modifier.height(8.dp))
                    if (!status.startsWith("HATA:")) StatusText(status)
                    if (h?.optBoolean("countRoundSupported") == true) {
                        OutlinedButton(
                            onClick = { showNextRound = true },
                            enabled = !busy && !comparisonLoading && linesComplete && lines.isNotEmpty() && allRequiredComplete && allRequiredSaved &&
                                pendingRetry == null && !pendingRestoreFailed && allowedSlots.isNotEmpty() && countDocumentIsMutable(h.optString("status")),
                            modifier = Modifier.fillMaxWidth(),
                        ) { Text("Ad-hoc Sonrası Yeni Tur Başlat") }
                        if (h.optString("previousRoundNo").isNotBlank()) {
                            TextButton(onClick = { loadComparison() }, enabled = !busy && !comparisonLoading) { Text("Turları Yan Yana Karşılaştır") }
                        }
                    }
                    if (prepared && !binReviewSupported) Text("Raf tamamlama için Business Central sayım güncellemesi gerekli.")
                    Spacer(Modifier.height(8.dp))

                    if (h != null && allowedSlots.isEmpty()) {
                        StatusText("Bu belge için $myUserId kullanıcısına sayıcı slotu atanmamış.")
                    } else if (allowedSlots.size > 1) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Sayıcı", fontSize = 12.sp, color = Color.Gray)
                            Spacer(Modifier.width(8.dp))
                            allowedSlots.forEach { candidate ->
                                FilterChip(
                                    selected = slot == candidate,
                                    onClick = {
                                        slot = candidate
                                        lastCompleted = null; lastBatch = emptyList(); lastCompletedLp = null
                                        scannedQtyLabels = emptySet(); previousRaw = ""; previousAt = 0L
                                    },
                                    enabled = !busy && pendingRetry == null && !pendingRestoreFailed,
                                    label = { Text("$candidate${if (h?.optBoolean("counter${candidate}Completed", false) == true) " ✓" else ""}") },
                                )
                                Spacer(Modifier.width(4.dp))
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                    }

                    if (!prepared) {
                        if (busy) {
                            LinearProgressIndicator(Modifier.fillMaxWidth())
                        } else {
                            Card(colors = CardDefaults.cardColors(containerColor = Color(0xFFFFE4E6))) {
                                Text(
                                    if (lines.isNotEmpty()) classicCountSheetV2Message(lines.size)
                                    else "Bu belge henüz V2 için hazırlanmadı. Sayfa Listesi'ne dönüp Yeni V2 Sayımı Oluştur'u kullanın.",
                                    Modifier.fillMaxWidth().padding(12.dp),
                                    color = Color(0xFF9F1239),
                                )
                            }
                        }
                    } else {
                        ScanField(
                            label = "1. Raf adresini okut",
                            value = binScan,
                            onValueChange = { binScan = it },
                            onScanned = { selectBin(it) },
                            enabled = !busy && pendingRetry == null && !pendingRestoreFailed && !currentSlotSaved,
                            modifier = Modifier.fillMaxWidth(),
                            focusRequester = binFocus,
                        )
                        LaunchedEffect(prepared, activeBin, busy) {
                            if (!prepared || busy) return@LaunchedEffect
                            runCatching { if (activeBin.isBlank()) binFocus.requestFocus() else labelFocus.requestFocus() }
                        }
                        if (activeBin.isNotBlank()) {
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                Text("📍 $activeBin", fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                TextButton(
                                    onClick = {
                                        activeBin = ""; lastCompleted = null; lastBatch = emptyList(); lastCompletedLp = null; pendingRetry = null
                                        status = "Raf seçin: raf barkodunu okutun."
                                    },
                                    enabled = !busy && pendingRetry == null && !pendingRestoreFailed,
                                ) { Text("Rafı değiştir") }
                            }
                            ScanField(
                                label = "2. LP / ürün / lot barkodunu okut",
                                value = labelScan,
                                onValueChange = { labelScan = it },
                                onScanned = { scanLabel(it) },
                                enabled = !busy && pendingRetry == null && !pendingRestoreFailed && slot in allowedSlots && !currentSlotSaved,
                                modifier = Modifier.fillMaxWidth(),
                                focusRequester = labelFocus,
                            )
                            OutlinedButton(
                                onClick = { showFinishBin = true },
                                enabled = binReviewSupported && !busy && pendingRetry == null && !pendingRestoreFailed && slot in allowedSlots && !currentSlotSaved,
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text("Rafı bitir · sayılmayanları 0 yaz") }
                        }
                    }

                    pendingRetry?.let { pending ->
                        Spacer(Modifier.height(8.dp))
                        Button(
                            onClick = { sendScan(pending) },
                            enabled = !busy,
                            modifier = Modifier.fillMaxWidth(),
                        ) { Text("🔁 Aynı işlemi güvenle tekrar dene", fontWeight = FontWeight.Bold) }
                    }
                    if (lastCompleted != null || lastBatch.isNotEmpty() || lastCompletedLp != null) {
                        Spacer(Modifier.height(6.dp))
                        OutlinedButton(
                            onClick = { undoLastScan() },
                            enabled = !busy && pendingRetry == null && !pendingRestoreFailed && !currentSlotSaved,
                            modifier = Modifier.fillMaxWidth(),
                        ) { Text("↩ Son okutmayı geri al") }
                    }

                    Spacer(Modifier.height(10.dp))
                    if (binReviewSupported && lines.isNotEmpty()) {
                        Text("Raf farkları · $slot sayımı", fontWeight = FontWeight.Bold)
                        Text(varianceReview, fontSize = 12.sp)
                        Text(if (hasBinFindings) countV2BinFindingsNote(h?.optBoolean("countRoundSupported") == true) else "Diğer raftan otomatik düşülmez · stok farkları onaydan sonra işlenir", fontSize = 11.sp)
                    }
                    Text("Yeşil: doğru · Kırmızı: miktar farkı · Sarı: farklı rafta bulunan LP", fontSize = 12.sp)
                    if (hasBinFindings) Text(countV2BinFindingsNote(h?.optBoolean("countRoundSupported") == true), fontSize = 12.sp, color = Color(0xFF92400E))
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            if (prepared) "Otomatik oluşan satırlar (${lines.size})" else "Belgedeki klasik satırlar (${lines.size})",
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = { reload("TAMAM: Satırlar yenilendi") }, enabled = !busy) { Text("Yenile") }
                    }
                }
            }
            items(lines.sortedByDescending { it.optInt("lineNo") }) { line ->
                CountV2LineCard(line, slot,
                    enabled = prepared && !blockingError && !busy && !currentSlotSaved && pendingRetry == null && !pendingRestoreFailed,
                    onClick = { adjustLine = line })
            }
            if (lines.isEmpty() && prepared && !busy) item {
                EmptyState("Ekran boş. Rafı okutun, sonra LP / ürün / lot barkodunu okutun.")
            }
        }
        Surface(tonalElevation = 3.dp, shadowElevation = 4.dp) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp)) {
                Button(
                    onClick = { completeCounter() },
                    enabled = canSave,
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                ) { Text(if (currentSlotSaved) "✓ Sayım Turu Kaydedildi" else "✅ Sayım Turunu Kaydet", fontWeight = FontWeight.Bold) }
                if (hasBinFindings) Text(countV2BinFindingsNote(h?.optBoolean("countRoundSupported") == true), fontSize = 12.sp, color = Color(0xFF92400E))
                if (postAllowed) {
                    Spacer(Modifier.height(6.dp))
                    OutlinedButton(
                        onClick = { showPostConfirm = true },
                        enabled = canPost,
                        modifier = Modifier.fillMaxWidth().height(48.dp),
                    ) { Text("Onayla ve Stoklara İşle") }
                }
                when {
                    lines.isNotEmpty() && !currentSlotLinesComplete -> Text(
                        "Bu sayım turundaki bütün satırları tamamlayın.",
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    // Terminalden işleme kapalı: düğme yerine nerede işleneceğini söyle.
                    showsCountPostedInBcNote(postAllowed, currentSlotSaved, h?.optString("status").orEmpty(), status) -> Text(
                        COUNT_POSTED_IN_BC_NOTE,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    postAllowed && !allRequiredSaved ->
                        Text("Stok hareketinden önce atanmış bütün sayıcı turları kaydedilmelidir.", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }

    if (showNextRound) AlertDialog(
        onDismissRequest = { showNextRound = false },
        title = { Text("Yeni sayım turu") },
        text = { Text("Bu turun bütün sonuçları korunup kilitlenecek. Ad-hoc sonrası güncel stok ve raf bilgileriyle yeni tur açılacak. Stok düzeltmesi yalnız son turdan yapılabilir.") },
        confirmButton = { Button(onClick = { startNextRound() }) { Text("Yeni Turu Başlat") } },
        dismissButton = { TextButton(onClick = { showNextRound = false }) { Text("Vazgeç") } },
    )
    if (showComparison) AlertDialog(
        onDismissRequest = { showComparison = false },
        title = { Text("Sayım turları · Sayıcı $slot") },
        text = {
            Column {
                if (comparisonLoading) Text("Tur geçmişi yükleniyor...")
                if (comparisonError.isNotBlank()) Text(comparisonError)
                if (history.isNotEmpty()) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        TextButton(onClick = { comparisonIndex = (comparisonIndex + 1) % history.size }) {
                            Text("${history[comparisonIndex].first.optInt("roundNo", 1)}. tur ▾")
                        }
                        Text("${h?.optInt("roundNo", 1)}. tur (son)")
                    }
                    LazyColumn(Modifier.heightIn(max = 420.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(compareCountRounds(history[comparisonIndex].second, lines, slot)) { comparison ->
                            CountRoundComparisonCard(comparison)
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = { showComparison = false }) { Text("Kapat") } },
        dismissButton = { if (comparisonError.isNotBlank()) TextButton(onClick = { loadComparison() }) { Text("Yeniden Dene") } },
    )

    adjustLine?.let { line ->
        QuantityDialogSheet(
            title = "Miktarı düzelt — ${line.optString("binCode")}",
            itemNo = line.optString("itemNo") +
                line.optString("lpNo").takeIf { it.isNotBlank() }?.let { " · LP: $it" }.orEmpty() +
                line.optString("lotNo").takeIf { it.isNotBlank() }?.let { " · Lot $it" }.orEmpty(),
            initialQty = if (line.optBoolean("counted$slot")) line.optDouble("countedQty$slot", 0.0)
                else line.optDouble("systemQty", 0.0).coerceAtLeast(0.0),
            initialUom = line.optString("unitOfMeasureCode"),
            showLotSerial = false,
            // Boş palet / eksik ürün: fiziksel 0 geçerli bir sayımdır.
            allowZeroQuantity = true,
            onDismiss = { adjustLine = null },
            onConfirm = { res ->
                adjustLine = null
                recordLineCount(line, res.quantity)
            },
        )
    }

    if (showPostConfirm && postAllowed) {
        AlertDialog(
            onDismissRequest = { if (!busy) showPostConfirm = false },
            title = { Text("Sayım stoklara işlensin mi?") },
            text = { Column(Modifier.verticalScroll(rememberScrollState())) {
                Text(varianceReview)
                Text("Bu farklar stoklara işlenecek ve belge kapanacak.")
            } },
            confirmButton = {
                TextButton(onClick = { postSheet() }, enabled = canPost) { Text("Onayla ve İşle") }
            },
            dismissButton = {
                TextButton(onClick = { showPostConfirm = false }, enabled = !busy) { Text("Vazgeç") }
            },
        )
    }
    if (showFinishBin) AlertDialog(
        onDismissRequest = { if (!busy) showFinishBin = false },
        title = { Text("$activeBin sayımı tamamlandı mı?") },
        text = { Text("Bu rafta saymadığınız kayıtlı ürünler yalnız sizin $slot sayımınıza 0 yazılacak · diğer rafların miktarı değişmeyecek") },
        confirmButton = { TextButton(onClick = { finishBin() }, enabled = !busy) { Text("Rafı bitir") } },
        dismissButton = { TextButton(onClick = { showFinishBin = false }, enabled = !busy) { Text("Devam et") } },
    )
    unexpectedLabel?.let { label ->
        QuantityDialogSheet(
            title = "Bu rafta bulduğunuz miktar — $activeBin",
            itemNo = label.itemNo,
            initialQty = 1.0,
            initialUom = label.unitOfMeasureCode,
            initialLot = label.lotNo,
            initialSerial = label.serialNo,
            showLotSerial = true,
            onDismiss = { unexpectedLabel = null },
            onConfirm = { result ->
                unexpectedLabel = null
                sendScan(PendingCountV2Scan(UUID.randomUUID().toString(), activeBin,
                    label.copy(quantity = result.quantity, unitOfMeasureCode = result.uom, lotNo = result.lotNo, serialNo = result.serialNo), slot))
            },
        )
    }
}

private fun formatCountV2Qty(value: Double): String =
    if (value.isFinite() && value == value.toLong().toDouble()) value.toLong().toString() else value.toString()

/** Acknowledgement clears only the message, never the pending scan/retry state. */
@Composable
internal fun CountV2ErrorDialog(status: String, onDismiss: () -> Unit) {
    if (!status.startsWith("HATA:")) return
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    LaunchedEffect(status) { keyboard?.hide() }
    AlertDialog(
        onDismissRequest = onDismiss,
        properties = androidx.compose.ui.window.DialogProperties(dismissOnClickOutside = false),
        title = { Text("Sayım hatası") },
        text = { Text(status.removePrefix("HATA:").trim(), Modifier.verticalScroll(rememberScrollState())) },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Tamam") } },
    )
}

@Composable
internal fun CountV2LpIdentity(lpNo: String) {
    Text(
        if (lpNo.isNotBlank()) "LP: $lpNo" else "LP: Yok (LP’siz stok)",
        fontSize = 13.sp,
        fontWeight = FontWeight.SemiBold,
    )
}

@Composable
private fun countV2StatusColor(result: CountV2LineResult): Color {
    val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    return when (result) {
        CountV2LineResult.Match -> if (dark) Color(0xFF6EE7B7) else Color(0xFF16724D)
        CountV2LineResult.QuantityDifference -> if (dark) Color(0xFFFCA5A5) else Color(0xFFB42338)
        CountV2LineResult.BinFinding -> if (dark) Color(0xFFFCD34D) else Color(0xFF946200)
        CountV2LineResult.Pending -> MaterialTheme.colorScheme.onSurfaceVariant
    }
}

@Composable
internal fun CountV2BinFindingDetails(line: JSONObject, slot: Int) {
    val source = line.optString("foundFromBin")
    if (source.isBlank()) return
    val accent = countV2StatusColor(CountV2LineResult.BinFinding)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Surface(color = accent.copy(alpha = 0.07f), shape = RoundedCornerShape(10.dp)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Sayımda sistem rafı", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(source, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
                WmsIcon(WmsGlyph.CHEVRON, accent, Modifier.padding(horizontal = 8.dp).size(16.dp))
                Column(Modifier.weight(1f)) {
                    Text("Bulunan raf", fontSize = 11.sp, color = accent)
                    Text(line.optString("binCode"), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = accent)
                }
            }
        }
        val expected = line.optDouble("foundLpQty", Double.NaN)
        val counted = line.optDouble("countedQty$slot", Double.NaN)
        if (line.optBoolean("counted$slot") && expected.isFinite() && counted.isFinite() && kotlin.math.abs(counted - expected) >= 0.00001) {
            Text("LP miktar farkı: ${formatCountV2Qty(counted - expected)} · Kayıtlı LP miktarı: ${formatCountV2Qty(expected)}",
                color = countV2StatusColor(CountV2LineResult.QuantityDifference), fontSize = 12.sp)
        }
    }
}

@Composable
internal fun CountV2LineCard(line: JSONObject, slot: Int, enabled: Boolean = false, onClick: () -> Unit = {}) {
    val counted = isCountRecorded(
        hasExplicitFlag = line.has("counted$slot"),
        explicitFlag = line.optBoolean("counted$slot"),
        quantity = line.optDouble("countedQty$slot", 0.0),
    )
    val result = countV2LineResult(line, slot)
    val accent = countV2StatusColor(result)
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val systemQty = line.optDouble("systemQty")
    val difference = line.optDouble("countedQty$slot") - systemQty
    Card(
        Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.65f)),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface,
            contentColor = MaterialTheme.colorScheme.onSurface),
    ) {
        Row(Modifier.height(IntrinsicSize.Min)) {
            Box(Modifier.width(4.dp).fillMaxHeight().background(accent))
            Column(Modifier.weight(1f).padding(horizontal = 14.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Surface(color = accent.copy(alpha = 0.09f), contentColor = accent, shape = RoundedCornerShape(50)) {
                    Row(Modifier.padding(horizontal = 9.dp, vertical = 3.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Box(Modifier.size(5.dp).background(accent, RoundedCornerShape(50)))
                        Text(when (result) {
                            CountV2LineResult.Match -> "Raf ve miktar doğru"
                            CountV2LineResult.QuantityDifference -> "Miktar farkı"
                            CountV2LineResult.BinFinding -> "Farklı rafta bulunan LP"
                            CountV2LineResult.Pending -> "Sayım bekliyor"
                        }, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(line.optString("itemNo"), fontWeight = FontWeight.Bold, fontSize = 20.sp)
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            WmsIcon(WmsGlyph.LICENSE_PLATE, secondary, Modifier.size(17.dp))
                            CountV2LpIdentity(line.optString("lpNo"))
                        }
                    }
                    Column(Modifier.widthIn(max = 130.dp), horizontalAlignment = Alignment.End) {
                        Text(if (counted) formatCountV2Qty(line.optDouble("countedQty$slot")) else "—",
                            fontWeight = FontWeight.Bold, fontSize = 26.sp, color = accent)
                        Text(if (counted) firstValue(line, "unitOfMeasureCode") else "Henüz sayılmadı",
                            fontSize = 10.sp, fontWeight = FontWeight.Medium, color = secondary)
                    }
                }
                if (line.optString("foundFromBin").isNotBlank()) {
                    CountV2BinFindingDetails(line, slot)
                } else {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        WmsIcon(WmsGlyph.BIN_SEARCH, secondary, Modifier.size(16.dp))
                        Text("Raf", fontSize = 12.sp, color = secondary)
                        Text(line.optString("binCode"), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
                val tracking = listOfNotNull(
                    line.optString("lotNo").takeIf { it.isNotBlank() }?.let { "Lot: $it" },
                    line.optString("serialNo").takeIf { it.isNotBlank() }?.let { "Seri: $it" },
                ).joinToString(" · ")
                if (tracking.isNotBlank()) Text(tracking, fontSize = 11.sp, color = secondary)
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Bu rafta sistem: ${formatCountV2Qty(systemQty)}", Modifier.weight(1f), fontSize = 11.sp, color = secondary)
                    Text("Fark: " + if (counted) formatCountV2Qty(difference) else "—",
                        fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = accent)
                }
            }
        }
    }
}

@Composable
internal fun CountRoundComparisonCard(comparison: CountRoundComparison) {
    Column {
        Text(comparison.label, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            listOf(comparison.previous, comparison.current).forEach { values ->
                Column(Modifier.weight(1f)) {
                    if (values == null) Text("Bu turda satır yok", fontSize = 12.sp)
                    else {
                        Text("Sistem rafı: ${values.systemBins}", fontSize = 12.sp)
                        Text("Sayılan raf: ${values.countedBins}", fontSize = 12.sp)
                        Text("Sayım rafı: ${values.scopeBins}", fontSize = 12.sp)
                        Text("Raf stoku: ${formatCountV2Qty(values.systemQty)}", fontSize = 12.sp)
                        values.recordedLpQty?.let { Text("Kayıtlı LP: ${formatCountV2Qty(it)}", fontSize = 12.sp) }
                        Text("Sayılan: ${values.countedQty?.let { formatCountV2Qty(it) } ?: "Tamamlanmadı"}", fontSize = 12.sp)
                        Text("Stok farkı: ${values.variance?.let { formatCountV2Qty(it) } ?: "—"}", fontSize = 12.sp)
                    }
                }
            }
        }
        comparison.change?.let { Text("Turlar arası miktar farkı: ${formatCountV2Qty(it)}", fontSize = 12.sp) }
        HorizontalDivider()
    }
}
