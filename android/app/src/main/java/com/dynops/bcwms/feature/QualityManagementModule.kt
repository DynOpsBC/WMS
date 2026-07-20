package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
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
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Microsoft Quality Management (BC v28+ first-party extension).
 *
 * Hits api/microsoft/qualityManagement/v1.0/qualityInspections directly with
 * the same AAD token as the rest of the app. Key is SystemId (GUID); all
 * bound actions follow `qualityInspections(<GUID>)/Microsoft.NAV.<Action>`.
 *
 * Supported actions: FinishInspection, ReopenInspection, CreateReinspection,
 * SetTestValue(testCode, testValue), AssignTo(user), BlockLot/UnBlockLot,
 * BlockSerial/UnBlockSerial, BlockPackage/UnBlockPackage, CreateMovement,
 * CreateWarehouseInternalPutaway, CreateWarehousePutAway.
 *
 * Lives alongside DOPSWHS Quality Order (custom, simple pass/fail) which is
 * still exposed via QualityModule. MS QM covers templated multi-test flows.
 */

private fun qmBase(context: android.content.Context): String =
    "${BcApi.BC_RESOURCE}/v2.0/${BcApi.getTenant(context)}/${BcApi.getEnvironment(context)}/api/microsoft/qualityManagement/v1.0/companies(${BcApi.getCompanyId(context)})"

private fun inspectionKey(systemId: String): String =
    "'${systemId.replace("'", "''")}'"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QualityManagementModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val qmBaseUrl = remember(context) { qmBase(context) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var openOnly by remember { mutableStateOf(true) }
    var selected by remember { mutableStateOf<JSONObject?>(null) }

    fun load() {
        scope.launch {
            loading = true; status = "Yükleniyor..."
            val filter = if (openOnly) "&\$filter=status eq 'Open'" else ""
            val r = BcApi.get(context, "$qmBaseUrl/qualityInspections?\$top=50$filter&\$orderby=systemCreatedAt desc")
            loading = false
            rows = if (r.ok) BcApi.parseValueArray(r.body) else emptyList()
            status = if (!r.ok) "HATA: MS QM listesi alınamadı (HTTP ${r.httpCode})"
                else if (rows.isEmpty()) "EMPTY: ${if (openOnly) "Açık" else ""} inspection yok (HTTP ${r.httpCode})"
                else "PASS: ${rows.size} inspection (HTTP ${r.httpCode})"
        }
    }
    LaunchedEffect(openOnly) { load() }

    val sel = selected
    if (sel != null) { InspectionDetail(insp = sel, onBack = { selected = null; load() }); return }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { load() }, enabled = !loading) { Text(if (loading) "..." else "🔄 Yenile") }
            Spacer(Modifier.width(12.dp))
            FilterChip(
                selected = openOnly,
                onClick = { openOnly = !openOnly },
                label = { Text(if (openOnly) "Sadece Açık" else "Tümü", fontSize = 12.sp) }
            )
        }
        Spacer(Modifier.height(4.dp))
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            items(rows) { d ->
                Card(onClick = { selected = d }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("${d.optString("inspectionNo")} · ${firstValue(d, "templateCode").ifBlank { "—" }}", fontWeight = FontWeight.Bold)
                            Text(firstValue(d, "status").ifBlank { "Open" }, fontSize = 12.sp, color = Color.Gray)
                        }
                        Text(firstValue(d, "description"), fontSize = 12.sp, color = Color.Gray)
                        val parts = mutableListOf<String>()
                        parts.add("Item: ${firstValue(d, "sourceItemNo").ifBlank { "—" }}")
                        firstValue(d, "sourceLotNo").takeIf { it.isNotBlank() }?.let { parts.add("Lot: $it") }
                        firstValue(d, "sourceSerialNo").takeIf { it.isNotBlank() }?.let { parts.add("SN: $it") }
                        firstValue(d, "resultCode").takeIf { it.isNotBlank() }?.let { parts.add("Sonuç: $it") }
                        Text(parts.joinToString(" · "), fontSize = 12.sp, color = Color.Gray)
                    }
                }
            }
            if (rows.isEmpty() && !loading) item {
                EmptyState(if (openOnly) "Açık quality inspection yok." else "Hiç quality inspection yok.")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InspectionDetail(insp: JSONObject, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val qmBaseUrl = remember(context) { qmBase(context) }
    var current by remember { mutableStateOf(insp) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var showTest by remember { mutableStateOf(false) }
    var showFinish by remember { mutableStateOf(false) }

    val systemId = current.optString("systemIDOfInspection")
    val sval = current.optString("status")
    val isOpen = sval == "Open" || sval == "InProgress" || sval.isBlank()
    val lot = firstValue(current, "sourceLotNo")
    val serial = firstValue(current, "sourceSerialNo")
    val pkg = firstValue(current, "sourcePackageNo")

    fun reload() {
        scope.launch {
            busy = true
            val r = BcApi.get(context, "$qmBaseUrl/qualityInspections(${inspectionKey(systemId)})")
            busy = false
            if (r.ok) try { current = JSONObject(r.body) } catch (_: Exception) {}
        }
    }

    fun action(name: String, body: String, okMsg: String) {
        scope.launch {
            busy = true; status = "$name..."
            val r = BcApi.post(context, "$qmBaseUrl/qualityInspections(${inspectionKey(systemId)})/Microsoft.NAV.$name", body)
            busy = false
            status = if (r.ok) "PASS: $okMsg (HTTP ${r.httpCode})"
                else QcErrorParser.friendlyStatus(BcApi.errorMessage(r.body), r.httpCode)
            if (r.ok) reload()
        }
    }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).padding(12.dp)) {
            TextButton(onClick = onBack) { Text("‹ Inspection Listesi") }
            DocHeaderCard(
                title = "${current.optString("inspectionNo")} · ${firstValue(current, "templateCode").ifBlank { "—" }}",
                subtitle = buildString {
                    append(firstValue(current, "description"))
                    append("\nItem: ").append(firstValue(current, "sourceItemNo").ifBlank { "—" })
                    if (lot.isNotBlank()) append(" · Lot: ").append(lot)
                    if (serial.isNotBlank()) append(" · SN: ").append(serial)
                    if (pkg.isNotBlank()) append(" · Pkg: ").append(pkg)
                    append("\nDurum: ").append(sval.ifBlank { "Open" })
                    append(" · Sonuç: ").append(firstValue(current, "resultCode").ifBlank { "—" })
                },
            )
            Spacer(Modifier.height(6.dp))
            StatusText(status)
        }
        BottomActionBar {
            OutlinedButton(
                onClick = { showTest = true },
                enabled = !busy && isOpen,
                modifier = Modifier.weight(1f),
            ) { Text("➕ Test Değeri") }
            Button(
                onClick = { showFinish = true },
                enabled = !busy && isOpen,
                modifier = Modifier.weight(1f),
            ) { Text("✅ Bitir", fontWeight = FontWeight.Bold) }
        }
        BottomActionBar {
            OutlinedButton(
                onClick = { action("BlockLot", "{}", "Lot $lot bloklandı") },
                enabled = !busy && lot.isNotBlank(),
                modifier = Modifier.weight(1f),
            ) { Text("🔒 Block Lot") }
            OutlinedButton(
                onClick = { action("UnBlockLot", "{}", "Lot $lot açıldı") },
                enabled = !busy && lot.isNotBlank(),
                modifier = Modifier.weight(1f),
            ) { Text("🔓 Unblock Lot") }
            OutlinedButton(
                onClick = { action("ReopenInspection", "{}", "Yeniden açıldı") },
                enabled = !busy && !isOpen,
                modifier = Modifier.weight(1f),
            ) { Text("↩️ Reopen") }
        }
    }

    if (showTest) {
        SetTestValueSheet(
            onDismiss = { showTest = false },
            onConfirm = { code, value ->
                showTest = false
                val body = JSONObject().apply { put("testCode", code); put("testValue", value) }.toString()
                action("SetTestValue", body, "Test $code = $value kaydedildi")
            }
        )
    }
    if (showFinish) {
        FinishSheet(
            onDismiss = { showFinish = false },
            onConfirm = {
                showFinish = false
                action("FinishInspection", "{}", "Inspection bitirildi")
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SetTestValueSheet(onDismiss: () -> Unit, onConfirm: (code: String, value: String) -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var code by remember { mutableStateOf("") }
    var value by remember { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().padding(20.dp)) {
            Text("Test Değeri Gir", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(code, { code = it }, label = { Text("Test Code") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(value, { value = it }, label = { Text("Test Value") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(16.dp))
            Button(
                enabled = code.isNotBlank() && value.isNotBlank(),
                modifier = Modifier.fillMaxWidth().height(50.dp),
                onClick = { onConfirm(code.trim(), value.trim()) }
            ) { Text("Kaydet", fontWeight = FontWeight.Bold) }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FinishSheet(onDismiss: () -> Unit, onConfirm: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().padding(20.dp)) {
            Text("Inspection'ı Bitir", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Spacer(Modifier.height(8.dp))
            Text(
                "Template kurallarına göre BC otomatik resultCode atayacak. " +
                    "Lot/Serial/Package blok ayarları sonuca göre tetiklenebilir. Devam?",
                fontSize = 13.sp, color = Color.Gray,
            )
            Spacer(Modifier.height(16.dp))
            Button(
                modifier = Modifier.fillMaxWidth().height(50.dp),
                onClick = onConfirm,
            ) { Text("Bitir", fontWeight = FontWeight.Bold) }
            Spacer(Modifier.height(24.dp))
        }
    }
}
