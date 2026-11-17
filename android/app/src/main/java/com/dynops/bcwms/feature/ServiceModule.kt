package com.dynops.bcwms.feature

import android.content.Intent
import android.net.Uri
import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.ui.*
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.time.LocalDate
import android.graphics.BitmapFactory
import android.graphics.Matrix
import java.time.LocalDateTime

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ServiceModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var setup by remember { mutableStateOf(ServiceSetup()) }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var order by remember { mutableStateOf<JSONObject?>(null) }
    var itemLines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var lines by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var comments by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var attachments by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var selectedLine by remember { mutableIntStateOf(0) }
    var all by remember { mutableStateOf(false) }
    var finished by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var detailReady by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var dialog by remember { mutableStateOf("") }
    var deleteLine by remember { mutableStateOf<JSONObject?>(null) }
    var catalog by remember { mutableStateOf<Map<String, List<JSONObject>>>(emptyMap()) }
    var values by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var laborSaved by remember { mutableStateOf(false) }
    var confirmLeaveFinish by remember { mutableStateOf(false) }
    var customers by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var customerItems by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var customerSalesOrders by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var logEntries by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var historyOpen by remember { mutableStateOf(false) }
    fun value(key: String) = values[key].orEmpty()
    suspend fun fetch(path: String): List<JSONObject> {
        val r = BcApi.getAllPages(context, path)
        check(r.complete) { BcApi.errorMessage(r.error?.body.orEmpty()) }
        return r.rows
    }
    suspend fun reload() {
        val current = order
        if (current == null) {
            val allocations = fetch(if(all) "serviceOrders?\$orderby=orderDate%20desc&\$filter=" + Uri.encode("status ne 'Finished'") else "myServiceAllocations?\$filter=" + Uri.encode("status eq '${if(finished) "Finished" else "Active"}'"))
            // Finished + not posted: the technician still has to post (Servisi Kaydet).
            // Technicians see urgent work first; the dispatcher list keeps newest-first.
            rows = if (all) allocations else allocations.sortedWith(compareBy({ servicePriorityRank(it.optString("priority")) }, { it.optString("allocationDate") }))
        } else {
            detailReady = false
            val r = BcApi.get(context, "serviceOrders(${current.optString("id")})")
            check(r.ok) { BcApi.errorMessage(r.body) }
            order = JSONObject(r.body)
            val filter = "?\$filter=" + Uri.encode("documentNo eq '${serviceODataText(current.optString("no"))}'")
            itemLines = fetch("serviceItemLines$filter")
            lines = fetch("serviceLines$filter")
            comments = fetch("serviceComments?\$filter=" + Uri.encode("no eq '${serviceODataText(current.optString("no"))}'"))
            attachments = fetch("serviceAttachments?\$filter=" + Uri.encode("no eq '${serviceODataText(current.optString("no"))}'"))
            // Service history (BC 1.14.0.8+); an older BC has no log and the notes list is shown instead.
            logEntries = runCatching {
                fetch("serviceLogEntries?\$orderby=entryNo&\$filter=" + Uri.encode("serviceOrderNo eq '${serviceODataText(current.optString("no"))}'"))
            }.getOrDefault(emptyList())
            if(itemLines.none { it.optInt("lineNo") == selectedLine }) selectedLine = itemLines.firstOrNull()?.optInt("lineNo") ?: 0
            detailReady = true
        }
    }
    suspend fun refreshAfterAction() {
        // A refresh failure must not replace an action failure or erase entered values.
        try { reload() } catch (e: Exception) {
            message += "\nYenileme başarısız: ${e.message.orEmpty()}"
        }
    }
    fun dismissForm() {
        if (busy) return
        if (laborSaved) confirmLeaveFinish = true else dialog = ""
    }
    fun runJob(job: suspend () -> Unit) {
        if(busy) return
        busy = true
        scope.launch {
            try { job() } catch(e: Exception) { message = e.message ?: "İşlem başarısız" }
            finally { busy = false }
        }
    }
    suspend fun action(name: String, vararg fields: Pair<String, Any>): String {
        val r = BcApi.post(context, "serviceOrders(${order!!.optString("id")})/Microsoft.NAV.$name", serviceActionBody(*fields))
        check(r.ok) { BcApi.errorMessage(r.body) }
        return r.body
    }
    fun execute(name: String, vararg fields: Pair<String, Any>) = runJob {
        try { action(name, *fields); dialog = ""; message = "İşlem tamamlandı." } finally { refreshAfterAction() }
    }
    fun attach(bitmap: Bitmap, signature: Boolean) {
        if (busy) { message = "Önceki işlem sürüyor; birkaç saniye sonra tekrar deneyin."; return }
        runJob {
            val bytes = withContext(Dispatchers.Default) {
                val size = serviceBitmapSize(bitmap.width, bitmap.height)
                val scaled = Bitmap.createScaledBitmap(bitmap, size.first, size.second, true)
                ByteArrayOutputStream().use { output ->
                    scaled.compress(if(signature) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG, 80, output)
                    output.toByteArray()
                }
            }
            try {
                action("addAttachment", "fileName" to serviceFileName(order!!.optString("no"), signature, LocalDateTime.now()),
                    "base64Content" to serviceBase64(bytes), "kind" to if(signature) "signature" else "photo")
                dialog = ""; message = "Ek kaydedildi."
            } finally { refreshAfterAction() }
        }
    }
    // Full-resolution photo through a FileProvider file (TakePicturePreview only returns a thumbnail).
    var pendingPhoto by remember { mutableStateOf<java.io.File?>(null) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val file = pendingPhoto
        pendingPhoto = null
        if (ok && file != null && file.length() > 0) {
            scope.launch {
                val bitmap = withContext(Dispatchers.IO) { runCatching { serviceDecodePhoto(file.absolutePath) }.getOrNull() }
                file.delete()
                if (bitmap == null) message = "Fotoğraf okunamadı." else attach(bitmap, false)
            }
        } else file?.delete()
    }
    fun launchCamera() {
        runCatching {
            val dir = java.io.File(context.cacheDir, "service_photos").apply { mkdirs() }
            val file = java.io.File(dir, "foto-${System.currentTimeMillis()}.jpg")
            val uri = androidx.core.content.FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file)
            pendingPhoto = file
            camera.launch(uri)
        }.onFailure { pendingPhoto = null; message = "Kamera açılamadı." }
    }
    // The existing barcode scanner declares CAMERA. Android requires its grant
    // even for an external camera intent when that permission is declared.
    val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) launchCamera() else message = "Fotoğraf için kamera izni verilmedi."
    }
    LaunchedEffect(Unit) {
        runJob {
            val r = BcApi.get(context, "serviceSetups")
            check(r.ok) { BcApi.errorMessage(r.body) }
            setup = parseServiceSetup(r.body)
            reload()
        }
    }
    LaunchedEffect(all, finished) { if(setup.enabled) runJob { reload() } }
    androidx.activity.compose.BackHandler(order != null && !busy) { dialog = ""; laborSaved = false; message = ""; order = null; runJob { reload() } }
    fun open(name: String) {
        values = mapOf("commentType" to "General", "hours" to "1", "quantity" to "1", "allocationDate" to LocalDate.now().toString(), "workTypeCode" to setup.defaultWorkTypeCode)
        laborSaved = false
        message = ""
        if(name == "İşi Bitir") {
            val line = itemLines.firstOrNull { it.optInt("lineNo") == selectedLine }
            val start = runCatching {
                val date = line?.optString("startingDate").orEmpty()
                if (date.isBlank() || date == "0001-01-01") null
                else LocalDateTime.parse("${date}T${line?.optString("startingTime")?.removeSuffix("Z")}")
            }.getOrNull()
            // Labor already entered for this item (an earlier attempt, or "İşçilik Ekle") is not asked for again.
            // Only the technician's own lines: a colleague's hours on the same item are not his.
            val already = lines.filter { serviceEnumName(it.optString("type")) == "Resource" && it.optInt("serviceItemLineNo") == selectedLine &&
                setup.myResourceNo.isNotBlank() && it.optString("no") == setup.myResourceNo }
                .sumOf { it.optDouble("quantity", 0.0) }
            val elapsed = serviceElapsedHours(start, LocalDateTime.now(), setup.laborRoundingHours)
            values = values + ("hours" to serviceQtyText(serviceRemainingHours(elapsed, already))) + ("laborAlready" to if(already > 0) serviceQtyText(already) else "")
            // The elapsed time is replaced by a zero suggestion only when labor was really entered before.
        }
        catalog = emptyMap()
        dialog = name
        runJob {
            val names = when(name) {
                "Beklet" -> listOf("serviceRepairStatuses")
                "İşi Bitir" -> listOf("serviceFaultAreas", "serviceSymptomCodes", "serviceFaultCodes", "serviceResolutionCodes", "serviceWorkTypes")
                "İşçilik Ekle" -> listOf("serviceWorkTypes")
                "Teknisyen Ata" -> listOf("serviceTechnicians")
                else -> emptyList()
            }
            catalog = names.associateWith { fetch(it) }
        }
    }
    fun openNewService() {
        values = mapOf("priority" to "Medium", "assignToMe" to "true")
        customerItems = emptyList()
        customerSalesOrders = emptyList()
        message = ""
        dialog = "Yeni Servis"
        if (customers.isEmpty()) runJob {
            customers = fetch("serviceCustomers?\$select=no,name,city,blocked")
                .filter { serviceEnumName(it.optString("blocked")) != "All" }
        }
    }
    fun selectCustomer(c: JSONObject) {
        values = values + ("customerNo" to c.optString("no")) + ("customerName" to c.optString("name")) +
            ("customerCity" to c.optString("city")) + ("serviceItemNo" to "") + ("salesOrderNo" to "")
        customerItems = emptyList()
        customerSalesOrders = emptyList()
        runJob {
            val filter = "\$filter=" + Uri.encode("customerNo eq '${serviceODataText(c.optString("no"))}'")
            customerItems = fetch("serviceItems?$filter")
            // Optional: the customer's open sales orders (BC 1.14.0.8+).
            customerSalesOrders = runCatching { fetch("serviceSalesOrders?\$orderby=orderDate%20desc&$filter") }.getOrDefault(emptyList())
        }
    }
    val status = bcwmsStatus()
    @Composable fun priorityColor(value: String): Color = when(servicePriorityColor(value)) {
        "danger" -> status.danger; "warning" -> status.warning; "success" -> status.success; else -> MaterialTheme.colorScheme.outline
    }
    @Composable fun statusPill(value: String) {
        val c = when(serviceStatusColor(value)) {
            "success" -> status.success; "warning" -> status.warning; "primary" -> MaterialTheme.colorScheme.primary; else -> MaterialTheme.colorScheme.onSurfaceVariant
        }
        InfoPill(serviceStatusLabel(value), c.copy(alpha = 0.12f), c)
    }
    @Composable fun sectionTitle(text: String) {
        Text(text, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.padding(top = 6.dp))
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if(busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        StatusText(message)
        if(order == null) {
            if(setup.isTechnician) Button({ openNewService() }, enabled = !busy, modifier = Modifier.fillMaxWidth().height(52.dp)) {
                Text("+ Yeni Servis", fontWeight = FontWeight.Bold)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                FilterChip(!all, { if(!busy && all) { rows = emptyList(); all = false } }, label = { Text("İşlerim") }, enabled = !busy)
                if(setup.isDispatcher) FilterChip(all, { if(!busy && !all) { rows = emptyList(); all = true } }, label = { Text("Tüm İşler") }, enabled = !busy)
                if(!all) FilterChip(finished, { rows = emptyList(); finished = !finished }, label = { Text("Kayıt bekleyen") }, enabled = !busy)
            }
            OutlinedButton({ runJob { reload() } }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { WmsRefreshLabel(busy) }
            if(rows.isNotEmpty()) Text(
                "${rows.size} " + if(all) "açık servis siparişi" else if(finished) "kayıt bekleyen iş" else "açık iş",
                style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if(rows.isEmpty() && !busy) EmptyState(if(all) "Açık servis siparişi yok." else if(finished) "Kaydedilmeyi bekleyen bitmiş iş yok." else "Size atanmış açık servis işi yok.")
            rows.forEach { row ->
                val priority = row.optString("priority")
                Card(onClick = {
                    detailReady = false
                    order = if(all) row else JSONObject().put("id", row.optString("orderSystemId")).put("no", row.optString("documentNo"))
                    selectedLine = row.optInt("serviceItemLineNo"); runJob { reload() }
                }, enabled = !busy, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
                    Row(Modifier.height(IntrinsicSize.Min)) {
                        Box(Modifier.width(6.dp).fillMaxHeight().background(priorityColor(priority)))
                        Column(Modifier.padding(12.dp).weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(if(all) row.optString("no") else row.optString("documentNo"), style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                InfoPill(servicePriorityLabel(priority), priorityColor(priority).copy(alpha = 0.14f), priorityColor(priority))
                            }
                            Text(row.optString(if(all) "name" else "customerName"), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold,
                                maxLines = 2, overflow = TextOverflow.Ellipsis)
                            row.optString(if(all) "description" else "orderDescription").takeIf { it.isNotBlank() }?.let {
                                Text(it, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            }
                            Text(listOf(row.optString("city"), if(all) "" else row.optString("serviceItemDescription")).filter { it.isNotBlank() }.joinToString(" · "),
                                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                statusPill(row.optString(if(all) "status" else "orderStatus"))
                                // The repair status is shown only when it says more than the order status ("Parça sipariş edildi").
                                val repairText = row.optString("repairStatusText").ifBlank { row.optString("repairStatus").let { if(it.isBlank()) "" else "Onarım: $it" } }
                                if(!all && repairText.isNotBlank() && repairText != serviceStatusLabel(row.optString("orderStatus"))) InfoPill(repairText)
                                if(row.optString("salesOrderNo").isNotBlank()) InfoPill(row.optString("salesOrderNo"), MaterialTheme.colorScheme.primary.copy(alpha = 0.10f), MaterialTheme.colorScheme.primary)
                                if(all && row.optString("technicianNames").isNotBlank()) InfoPill(row.optString("technicianNames"))
                            }
                            val when_ = if(all) listOf(serviceDateText(row.optString("responseDate")).let { if(it.isBlank()) "" else "Yanıt: $it" })
                                else listOf(serviceDateText(row.optString("allocationDate")), "${serviceQtyText(row.optDouble("allocatedHours", 0.0))} saat")
                            Text(when_.filter { it.isNotBlank() }.joinToString(" · "), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        } else {
            val o = order!!
            fun launchUri(action: String, uri: String) { runCatching { context.startActivity(Intent(action, Uri.parse(uri))) }.onFailure { message = "Uygun uygulama bulunamadı." } }
            val selected = itemLines.firstOrNull { it.optInt("lineNo") == selectedLine }
            val ready = !busy && detailReady && selected != null
            fun hasDate(key: String) = selected?.optString(key).let { !it.isNullOrBlank() && it != "0001-01-01" }
            // 0 = to start, 1 = working, 2 = finished and waiting to be posted.
            val step = serviceStep(hasDate("startingDate"), hasDate("finishingDate"))
            val onHold = serviceEnumName(o.optString("status")) == "On Hold"
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton({ dialog = ""; laborSaved = false; message = ""; order = null; runJob { reload() } }, enabled = !busy) { Text(if(all) "‹ Tüm İşler" else "‹ İşlerim") }
                Spacer(Modifier.weight(1f))
                TextButton({ runJob { reload() } }, enabled = !busy) { Text("Yenile") }
            }

            // ---- 1. What is the job: one card, read top to bottom.
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(o.optString("no"), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                        o.optString("priority").takeIf { it.isNotBlank() }?.let { InfoPill(servicePriorityLabel(it), priorityColor(it).copy(alpha = 0.14f), priorityColor(it)) }
                    }
                    Text(o.optString("description").ifBlank { o.optString("name") }, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text(listOf(o.optString("name").takeIf { o.optString("description").isNotBlank() }.orEmpty(), o.optString("city")).filter { it.isNotBlank() }.joinToString(" · "),
                        style = MaterialTheme.typography.bodyLarge)
                    // The equipment belongs to the job description when there is only one.
                    if(itemLines.size == 1) itemLines[0].let { line ->
                        val equipment = listOf(line.optString("description").takeIf { it != o.optString("description") }.orEmpty(), line.optString("serviceItemNo"),
                            line.optString("serialNo").let { if(it.isBlank()) "" else "Seri $it" }).filter { it.isNotBlank() }.joinToString(" · ")
                        if(equipment.isNotBlank()) Text(equipment, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    val facts = listOf(
                        serviceDateText(o.optString("responseDate")).let { if(it.isBlank()) "" else "Yanıt: $it ${serviceTimeText(o.optString("responseTime"))}".trim() },
                        o.optString("salesOrderNo").let { if(it.isBlank()) "" else "Satış siparişi: $it" },
                        o.optString("technicianNames").let { if(it.isBlank()) "" else "Teknisyen: $it" },
                        o.optString("contactName").let { if(it.isBlank()) "" else "İlgili: $it" }).filter { it.isNotBlank() }
                    facts.forEach { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    val address = serviceAddressText(o.optString("address"), o.optString("address2"), o.optString("postCode"), o.optString("city"))
                    val phone = listOf("phoneNo", "phoneNo2").map { o.optString(it).trim() }.firstOrNull { it.isNotBlank() }.orEmpty()
                    if(address.isNotBlank() || phone.isNotBlank()) {
                        HorizontalDivider(Modifier.padding(vertical = 4.dp))
                        if(address.isNotBlank()) Text(address, style = MaterialTheme.typography.bodyMedium)
                        if(phone.isNotBlank()) Text("Tel: $phone", style = MaterialTheme.typography.bodyMedium)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if(address.isNotBlank()) FilledTonalButton({ launchUri(Intent.ACTION_VIEW, "geo:0,0?q=${Uri.encode(address)}") }, enabled = !busy,
                                modifier = Modifier.weight(1f).height(44.dp), shape = RoundedCornerShape(12.dp)) { Text("Yol tarifi", maxLines = 1) }
                            if(phone.isNotBlank()) FilledTonalButton({ launchUri(Intent.ACTION_DIAL, "tel:${Uri.encode(phone)}") }, enabled = !busy,
                                modifier = Modifier.weight(1f).height(44.dp), shape = RoundedCornerShape(12.dp)) { Text("Ara", maxLines = 1) }
                        }
                    }
                }
            }

            // Several service items on one order: pick the one being worked on.
            if(itemLines.size > 1) {
                sectionTitle("Hangi ekipman?")
                itemLines.forEach { line ->
                    val isSel = selectedLine == line.optInt("lineNo")
                    Card(onClick = { if(!busy) selectedLine = line.optInt("lineNo") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(containerColor = if(isSel) MaterialTheme.colorScheme.primary.copy(alpha = 0.08f) else MaterialTheme.colorScheme.surface),
                        border = androidx.compose.foundation.BorderStroke(if(isSel) 2.dp else 1.dp, if(isSel) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant)) {
                        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(line.optString("description"), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                            Text(listOf(line.optString("serviceItemNo"), line.optString("serialNo").let { if(it.isBlank()) "" else "Seri $it" }).filter { it.isNotBlank() }.joinToString(" · "),
                                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }

            // ---- 2. Where the job stands and the one thing to do next.
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        listOf("Başla", "Bitir", "Kaydet").forEachIndexed { index, label ->
                            val done = index < step
                            val current = index == step
                            if(index > 0) HorizontalDivider(Modifier.weight(1f).padding(horizontal = 6.dp),
                                color = if(index <= step) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant, thickness = 2.dp)
                            Box(Modifier.size(26.dp).background(if(done || current) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
                                androidx.compose.foundation.shape.CircleShape), contentAlignment = Alignment.Center) {
                                Text(if(done) "✓" else "${index + 1}", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold,
                                    color = if(done || current) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface)
                            }
                            Text(label, modifier = Modifier.padding(start = 6.dp), style = MaterialTheme.typography.labelLarge,
                                fontWeight = if(current) FontWeight.Bold else FontWeight.Normal,
                                color = if(done || current) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    val progress = serviceProgressText(serviceTimeText(selected?.optString("startingTime").orEmpty()).takeIf { hasDate("startingDate") }.orEmpty(),
                        serviceTimeText(selected?.optString("finishingTime").orEmpty()).takeIf { hasDate("finishingDate") }.orEmpty(),
                        serviceFinishSummary(selected?.optString("faultAreaText").orEmpty().ifBlank { selected?.optString("faultAreaCode").orEmpty() },
                            selected?.optString("symptomText").orEmpty().ifBlank { selected?.optString("symptomCode").orEmpty() },
                            selected?.optString("resolutionText").orEmpty().ifBlank { selected?.optString("resolutionCode").orEmpty() }),
                        if(onHold) selected?.optString("repairStatusText").orEmpty() else "")
                    if(progress.isNotBlank()) Text(progress, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    when(step) {
                        0 -> Button({ execute("startWork", "serviceItemLineNo" to selectedLine) }, enabled = ready,
                            modifier = Modifier.fillMaxWidth().height(wmsPrimaryButtonHeight())) { Text("İşe Başla", fontWeight = FontWeight.Bold) }
                        1 -> Button({ open("İşi Bitir") }, enabled = ready,
                            modifier = Modifier.fillMaxWidth().height(wmsPrimaryButtonHeight())) { Text("İşi Bitir", fontWeight = FontWeight.Bold) }
                        else -> {
                            val signed = attachments.any { it.optString("fileName").startsWith("IMZA-") }
                            if(setup.allowTerminalPosting) {
                                Button({ dialog = "Servisi Kaydet" }, enabled = !busy && detailReady && lines.isNotEmpty() && (signed || !setup.requireSignature),
                                    modifier = Modifier.fillMaxWidth().height(wmsPrimaryButtonHeight()), colors = ButtonDefaults.buttonColors(containerColor = status.success)) {
                                    Text("Servisi Kaydet", fontWeight = FontWeight.Bold)
                                }
                                Text(when {
                                    lines.isEmpty() -> "Parça veya işçilik satırı olmadığı için kayıt ofiste yapılır."
                                    setup.requireSignature && !signed -> "Kaydetmeden önce müşteri imzasını alın."
                                    signed -> "Müşteri imzası alındı. Servisi kaydedebilirsiniz."
                                    else -> "İsterseniz önce fotoğraf ve müşteri imzası ekleyin."
                                }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            } else Text("İş bitirildi. Servis kaydını ofis yapacak.", style = MaterialTheme.typography.bodyMedium, color = status.success, fontWeight = FontWeight.SemiBold)
                        }
                    }
                    // Everything else is optional and small.
                    val tiles = buildList {
                        if(step < 2) { add("Parça" to "Parça Ekle"); add("İşçilik" to "İşçilik Ekle") }
                        add("Not" to "Not Ekle"); add("Fotoğraf" to "Fotoğraf"); add("İmza" to "Müşteri İmzası")
                        if(step < 2) add("Beklet" to "Beklet")
                        if(setup.isDispatcher && step < 2) add("Teknisyen" to "Teknisyen Ata")
                    }
                    tiles.chunked(4).forEach { rowTiles ->
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            rowTiles.forEach { (label, name) ->
                                OutlinedButton({
                                    when(name) {
                                        "Fotoğraf" -> if (androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) launchCamera()
                                            else cameraPermission.launch(android.Manifest.permission.CAMERA)
                                        "Müşteri İmzası" -> { message = ""; dialog = "Müşteri İmzası" }
                                        else -> open(name)
                                    }
                                }, enabled = if(name == "Fotoğraf" || name == "Müşteri İmzası") !busy && detailReady else ready,
                                    modifier = Modifier.weight(1f).height(44.dp), shape = RoundedCornerShape(12.dp), contentPadding = PaddingValues(horizontal = 2.dp)) {
                                    Text(label, style = MaterialTheme.typography.labelLarge, maxLines = 1, softWrap = false)
                                }
                            }
                            repeat(4 - rowTiles.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }

            // ---- 3. What has been entered so far.
            if(lines.isNotEmpty()) {
                sectionTitle("Parça ve işçilik")
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
                    Column {
                        lines.forEachIndexed { index, line ->
                            val shipped = line.optDouble("quantityShipped", 0.0)
                            if(index > 0) HorizontalDivider()
                            Row(Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClick = {
                                if(!busy && detailReady && shipped == 0.0 && line.optDouble("quantityConsumed", 0.0) == 0.0) deleteLine = line
                            }).padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                Column(Modifier.weight(1f)) {
                                    Text(line.optString("description"), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                    Text(serviceLineTypeLabel(line.optString("type")) + if(shipped > 0) " · kaydedildi" else "",
                                        style = MaterialTheme.typography.labelSmall, color = if(shipped > 0) status.success else MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Text("${serviceQtyText(line.optDouble("quantity", 0.0))} ${line.optString("unitOfMeasureCode")}", fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
                if(lines.any { it.optDouble("quantityShipped", 0.0) == 0.0 }) Text("Yanlış satırı silmek için üzerine uzun basın.",
                    style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            // Notes the history does not cover (typed before the log existed, or not logged) are never hidden.
            val unlogged = serviceUnloggedComments(comments.map { it.optString("comment") }, logEntries.map { it.optString("entryText") }).map { comments[it] }
            if(unlogged.isNotEmpty()) {
                sectionTitle("Notlar")
                unlogged.forEach {
                    Text("${serviceCommentTypeLabel(it.optString("type"))} · ${serviceDateText(it.optString("date"))}  ${it.optString("comment")}", style = MaterialTheme.typography.bodyMedium)
                }
            }
            if(logEntries.isNotEmpty()) {
                // Typed notes are always shown; the steps of the job open on request.
                val notes = logEntries.filter { serviceLogIsNote(it.optString("entryType")) }
                val shown = if(historyOpen) logEntries else notes
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(if(historyOpen) "Servis geçmişi" else "Notlar", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    TextButton({ historyOpen = !historyOpen }) { Text(if(historyOpen) "Yalnız notlar" else "Tüm geçmiş (${logEntries.size})") }
                }
                if(shown.isNotEmpty()) Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        shown.forEach { entry ->
                            val type = entry.optString("entryType")
                            val note = serviceLogIsNote(type)
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                                Box(Modifier.padding(top = 5.dp).size(9.dp).background(
                                    if(note) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant, androidx.compose.foundation.shape.CircleShape))
                                Column(Modifier.weight(1f)) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text(serviceLogTypeLabel(type), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                        Text(serviceLogTimeText(entry.optString("loggedAt")), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    val text = entry.optString("entryText")
                                    if(text.isNotBlank()) Text(text, style = if(note) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.bodySmall,
                                        color = if(note) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
                                    entry.optString("technicianName").ifBlank { entry.optString("userName") }.takeIf { it.isNotBlank() }?.let {
                                        Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if(attachments.isNotEmpty()) {
                sectionTitle("Ekler (${attachments.size})")
                attachments.forEach { Text("• " + it.optString("fileName") + it.optString("fileExtension").let { e -> if(e.isBlank() || it.optString("fileName").endsWith(".$e")) "" else ".$e" },
                    style = MaterialTheme.typography.bodySmall) }
            }
        }
    }
    deleteLine?.let { line -> AlertDialog(onDismissRequest = { if(!busy) deleteLine = null }, title = { Text("Satır silinsin mi?") },
        text = { Text(line.optString("description")) }, confirmButton = { Button({ deleteLine = null; execute("deleteLine", "lineNo" to line.optInt("lineNo")) }, enabled = !busy) { Text("Sil") } },
        dismissButton = { TextButton({ deleteLine = null }, enabled = !busy) { Text("Vazgeç") } }) }
    if(dialog == "Servisi Kaydet") AlertDialog(onDismissRequest = { if(!busy) dialog = "" }, title = { Text("Servis sevkiyatını onayla") },
        text = { Text(lines.joinToString("\n") { "• ${it.optString("description")}: ${serviceQtyText(it.optDouble("quantity", 0.0))} ${it.optString("unitOfMeasureCode")}" } +
            "\n\nParçalar stoktan düşer, işçilik kaydedilir. Fatura ofiste kesilir.") },
        confirmButton = { Button({ runJob {
            try {
                val response = action("postShipment", "consume" to false)
                message = "Servis sevkiyatı kaydedildi: ${runCatching { JSONObject(response).optString("value", response) }.getOrDefault(response)}"
                dialog = ""; order = null
            } finally { refreshAfterAction() }
        } }, enabled = !busy) { Text("Kaydet") } }, dismissButton = { TextButton({ dialog = "" }, enabled = !busy) { Text("Vazgeç") } })
    if(dialog == "Müşteri İmzası") SheetScaffold(onDismiss = { if(!busy) dialog = "" }) {
        ServiceSignature(busy, onSave = { attach(it, true) })
    }
    if(dialog == "Yeni Servis") SheetScaffold(onDismiss = { if(!busy) dialog = "" }) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Yeni Servis", style = MaterialTheme.typography.titleLarge)
            StatusText(message)
            if(value("customerNo").isBlank()) {
                OutlinedTextField(value("customerQuery"), { values = values + ("customerQuery" to it) }, label = { Text("Müşteri ara (ad, no veya şehir)") },
                    singleLine = true, enabled = !busy, modifier = Modifier.fillMaxWidth())
                val query = value("customerQuery")
                val matches = if(query.trim().length < 2) emptyList() else customers.filter {
                    serviceSearchMatches(query, it.optString("name"), it.optString("no"), it.optString("city"))
                }.take(25)
                if(query.trim().length < 2) Text("En az 2 harf yazın.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                else if(matches.isEmpty() && !busy) Text("Müşteri bulunamadı.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                matches.forEach { c ->
                    OutlinedCard(onClick = { selectCustomer(c) }, enabled = !busy, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                        Column(Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
                            Text(c.optString("name"), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            Text(listOf(c.optString("no"), c.optString("city")).filter { it.isNotBlank() }.joinToString(" · "),
                                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            } else {
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)) {
                    Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(value("customerName"), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            Text(listOf(value("customerNo"), value("customerCity")).filter { it.isNotBlank() }.joinToString(" · "), style = MaterialTheme.typography.bodySmall)
                        }
                        TextButton({ values = values - "customerNo" - "customerName" - "customerCity" - "serviceItemNo" - "salesOrderNo"; customerItems = emptyList(); customerSalesOrders = emptyList() }, enabled = !busy) { Text("Değiştir") }
                    }
                }
                var itemsOpen by remember { mutableStateOf(false) }
                val selectedItem = customerItems.firstOrNull { it.optString("no") == value("serviceItemNo") }
                Text("Servis maddesi (ekipman)", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Box(Modifier.fillMaxWidth()) {
                    OutlinedButton({ itemsOpen = true }, enabled = !busy, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                        Text(selectedItem?.let { "${it.optString("no")} · ${it.optString("description")}" }
                            ?: if(customerItems.isEmpty()) "Bu müşterinin servis maddesi yok" else "Servis maddesi seçmeden devam",
                            modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text("▾")
                    }
                    DropdownMenu(itemsOpen, { itemsOpen = false }) {
                        DropdownMenuItem(text = { Text("Servis maddesi seçmeden devam") }, onClick = { values = values + ("serviceItemNo" to ""); itemsOpen = false })
                        customerItems.forEach { item -> DropdownMenuItem(text = { Text("${item.optString("no")} · ${item.optString("description")}") },
                            onClick = { values = values + ("serviceItemNo" to item.optString("no")); itemsOpen = false }) }
                    }
                }
                if(customerSalesOrders.isNotEmpty()) {
                    var ordersOpen by remember { mutableStateOf(false) }
                    val selectedOrder = customerSalesOrders.firstOrNull { it.optString("no") == value("salesOrderNo") }
                    Text("Satış siparişi (isteğe bağlı)", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Box(Modifier.fillMaxWidth()) {
                        OutlinedButton({ ordersOpen = true }, enabled = !busy, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                            Text(selectedOrder?.let { serviceSalesOrderLabel(it.optString("no"), it.optString("orderDate"), it.optString("yourReference"), it.optString("externalDocumentNo")) }
                                ?: "Satış siparişine bağlamadan devam", modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text("▾")
                        }
                        DropdownMenu(ordersOpen, { ordersOpen = false }) {
                            DropdownMenuItem(text = { Text("Satış siparişine bağlamadan devam") }, onClick = { values = values + ("salesOrderNo" to ""); ordersOpen = false })
                            customerSalesOrders.take(40).forEach { so -> DropdownMenuItem(
                                text = { Text(serviceSalesOrderLabel(so.optString("no"), so.optString("orderDate"), so.optString("yourReference"), so.optString("externalDocumentNo"))) },
                                onClick = { values = values + ("salesOrderNo" to so.optString("no")); ordersOpen = false }) }
                        }
                    }
                }
                OutlinedTextField(value("description"), { values = values + ("description" to it.take(100)) }, label = { Text("Arıza / iş açıklaması") },
                    minLines = 2, enabled = !busy, modifier = Modifier.fillMaxWidth())
                Text("Öncelik", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("Low" to "Düşük", "Medium" to "Orta", "High" to "Yüksek").forEach { (code, label) ->
                        FilterChip(value("priority") == code, { values = values + ("priority" to code) }, label = { Text(label) }, enabled = !busy)
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(value("assignToMe") == "true", { values = values + ("assignToMe" to it.toString()) }, enabled = !busy)
                    Text("Bana ata (İşlerim listesine düşsün)", style = MaterialTheme.typography.bodyMedium)
                }
                Button({
                    runJob {
                        require(value("description").isNotBlank()) { "Arıza açıklaması girin." }
                        val fields = arrayOf<Pair<String, Any>>(
                            "customerNo" to value("customerNo"), "serviceItemNo" to value("serviceItemNo"),
                            "description" to value("description").trim(), "priority" to value("priority").ifBlank { "Medium" },
                            "assignToMe" to (value("assignToMe") == "true"))
                        // The plain action also works on a BC without the sales order link.
                        val r = if(value("salesOrderNo").isBlank()) BcApi.post(context, "serviceSetups(${setup.id})/Microsoft.NAV.createServiceOrder", serviceActionBody(*fields))
                            else BcApi.post(context, "serviceSetups(${setup.id})/Microsoft.NAV.createServiceOrderForSalesOrder",
                                serviceActionBody(*fields, "salesOrderNo" to value("salesOrderNo")))
                        check(r.ok) { BcApi.errorMessage(r.body) }
                        val no = JSONObject(r.body).optString("value")
                        val created = fetch("serviceOrders?\$filter=" + Uri.encode("no eq '${serviceODataText(no)}'")).firstOrNull()
                        dialog = ""
                        message = "$no servis siparişi oluşturuldu."
                        if(created != null) {
                            detailReady = false
                            order = JSONObject().put("id", created.optString("id")).put("no", no)
                            selectedLine = 0
                        }
                        refreshAfterAction()
                    }
                }, enabled = !busy && setup.id.isNotBlank(), modifier = Modifier.fillMaxWidth().height(52.dp)) {
                    Text("Servisi Oluştur", fontWeight = FontWeight.Bold)
                }
            }
            TextButton({ if(!busy) dialog = "" }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Vazgeç") }
        }
    }
    if(dialog.isNotBlank() && dialog !in listOf("Servisi Kaydet", "Müşteri İmzası", "Yeni Servis")) SheetScaffold(onDismiss = { dismissForm() }) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(dialog, style = MaterialTheme.typography.titleLarge)
            StatusText(message)
            @Composable fun field(key: String, label: String) {
                val numeric = key == "hours" || key == "quantity"
                OutlinedTextField(value(key), { values = values + (key to it) }, label = { Text(label) }, enabled = !busy && !(laborSaved && key == "hours"),
                    singleLine = key != "text" && key != "resolutionNote",
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = if(numeric) androidx.compose.ui.text.input.KeyboardType.Decimal else androidx.compose.ui.text.input.KeyboardType.Text),
                    modifier = Modifier.fillMaxWidth())
            }
            @Composable fun choose(key: String, label: String, options: List<JSONObject>, codeKey: String = "code", showCode: Boolean = true) {
                var expanded by remember { mutableStateOf(false) }
                fun describe(o: JSONObject): String {
                    val d = o.optString("description", o.optString("resourceName"))
                    return if (showCode && d.isNotBlank()) "${o.optString(codeKey)} · $d" else if (showCode) o.optString(codeKey) else d
                }
                val current = options.firstOrNull { it.optString(codeKey) == value(key) }?.let { describe(it) } ?: value(key)
                Column(Modifier.fillMaxWidth()) {
                    Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Box(Modifier.fillMaxWidth()) {
                        OutlinedButton({ expanded = true }, enabled = !busy && !(laborSaved && key == "workTypeCode"), modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(10.dp)) {
                            Text(current.ifBlank { "Seçin" }, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text("▾")
                        }
                        DropdownMenu(expanded, { expanded = false }) {
                            DropdownMenuItem(text = { Text("—") }, onClick = { values = values + (key to ""); expanded = false })
                            options.forEach { option -> DropdownMenuItem(text = { Text(describe(option)) }, onClick = {
                                values = values + (key to option.optString(codeKey))
                                expanded = false
                            }) }
                        }
                    }
                }
            }
            // One tap per answer: the options are shown as chips with their plain names, never as codes.
            @Composable fun chips(key: String, title: String, options: List<JSONObject>, step: String = "", locked: Boolean = false) {
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if(step.isNotBlank()) Box(Modifier.size(22.dp).background(
                            if(value(key).isBlank()) MaterialTheme.colorScheme.outlineVariant else MaterialTheme.colorScheme.primary, androidx.compose.foundation.shape.CircleShape),
                            contentAlignment = Alignment.Center) {
                            Text(if(value(key).isBlank()) step else "✓", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold,
                                color = if(value(key).isBlank()) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onPrimary)
                        }
                        Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                    }
                    if(options.isEmpty()) Text(if(busy) "Yükleniyor…" else "Tanımlı seçenek yok.", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        options.forEach { option ->
                            val code = option.optString("code")
                            FilterChip(value(key) == code, { values = values + (key to if(value(key) == code) "" else code) },
                                label = { Text(serviceChoiceLabel(code, option.optString("description")), style = MaterialTheme.typography.bodyLarge) },
                                enabled = !busy && !locked, modifier = Modifier.heightIn(min = 40.dp))
                        }
                    }
                }
            }
            when(dialog) {
                "Beklet" -> chips("repairStatusCode", "Neden bekletiliyor?", catalog["serviceRepairStatuses"].orEmpty().filter { it.optBoolean("waitingForCustomer") || it.optBoolean("sparePartOrdered") })
                "İşi Bitir" -> {
                    Text("Üç soruyu dokunarak cevaplayın. Kod yazmanız gerekmez.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    chips("faultAreaCode", "Arıza neredeydi?", catalog["serviceFaultAreas"].orEmpty(), "1")
                    chips("symptomCode", "Sorun neydi?", catalog["serviceSymptomCodes"].orEmpty(), "2")
                    chips("resolutionCode", "Ne yapıldı?", catalog["serviceResolutionCodes"].orEmpty(), "3")
                    OutlinedTextField(value("resolutionNote"), { values = values + ("resolutionNote" to it) }, label = { Text("Açıklama (yapılan işi kısaca yazın)") },
                        minLines = 3, enabled = !busy, modifier = Modifier.fillMaxWidth())
                    HorizontalDivider()
                    Text("İşçilik", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton({ values = values + ("hours" to serviceStepHours(value("hours"), -1, setup.laborRoundingHours)) }, enabled = !busy && !laborSaved,
                            modifier = Modifier.size(52.dp), contentPadding = PaddingValues(0.dp), shape = RoundedCornerShape(12.dp)) { Text("−", style = MaterialTheme.typography.titleLarge) }
                        OutlinedTextField(value("hours"), { values = values + ("hours" to it) }, label = { Text("Saat") }, enabled = !busy && !laborSaved, singleLine = true,
                            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal),
                            modifier = Modifier.weight(1f))
                        OutlinedButton({ values = values + ("hours" to serviceStepHours(value("hours"), 1, setup.laborRoundingHours)) }, enabled = !busy && !laborSaved,
                            modifier = Modifier.size(52.dp), contentPadding = PaddingValues(0.dp), shape = RoundedCornerShape(12.dp)) { Text("+", style = MaterialTheme.typography.titleLarge) }
                    }
                    if(laborSaved) Text("İşçilik kaydedildi; yalnız işi bitirme adımı tekrarlanacak.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    else if(value("laborAlready").isNotBlank()) Text("Bu iş için daha önce ${value("laborAlready")} saat işçilik girdiniz. Buraya yalnız eklenecek süreyi yazın.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    // One work type that is already the default needs no question.
                    val workTypes = catalog["serviceWorkTypes"].orEmpty()
                    if(workTypes.size > 1 || (workTypes.size == 1 && value("workTypeCode") != workTypes[0].optString("code")))
                        chips("workTypeCode", "İş türü", workTypes, locked = laborSaved)
                }
                "Parça Ekle" -> {
                    ScanField(label = "Madde no / barkod", value = value("itemNo"), onValueChange = { values = values + ("itemNo" to it) }, onScanned = { values = values + ("itemNo" to it) }, enabled = !busy)
                    field("quantity", "Miktar")
                }
                "Not Ekle" -> {
                    chips("commentType", "Not türü", listOf("General" to "Genel", "Fault" to "Arıza", "Resolution" to "Çözüm", "Internal" to "Dahili").map { JSONObject().put("code", it.first).put("description", it.second) })
                    OutlinedTextField(value("text"), { values = values + ("text" to it) }, label = { Text("Not") }, minLines = 3, enabled = !busy, modifier = Modifier.fillMaxWidth())
                }
                "Teknisyen Ata" -> {
                    choose("resourceNo", "Teknisyen", catalog["serviceTechnicians"].orEmpty(), "resourceNo")
                    field("allocationDate", "Atama tarihi (yyyy-AA-gg)")
                }
            }
            if(dialog in listOf("İşçilik Ekle", "Teknisyen Ata")) field("hours", if(dialog == "Teknisyen Ata") "Planlanan süre (saat)" else "İşçilik saati")
            if(dialog == "İşçilik Ekle") choose("workTypeCode", "İş türü", catalog["serviceWorkTypes"].orEmpty())
            if(dialog == "İşçilik Ekle") field("description", "Açıklama")
            Button({
                runJob {
                    try {
                        val line = "serviceItemLineNo" to selectedLine
                        val hours = value("hours").replace(',', '.').toDoubleOrNull()
                        when(dialog) {
                            "Beklet" -> { require(value("repairStatusCode").isNotBlank()) { "Bekletme nedenini seçin." }; action("setRepairStatus", line, "repairStatusCode" to value("repairStatusCode")) }
                            "İşi Bitir" -> {
                                require(hours != null && hours.isFinite() && hours >= 0) { "Geçerli saat girin." }
                                require(value("resolutionCode").isNotBlank() || value("resolutionNote").isNotBlank()) { "Ne yapıldığını seçin veya açıklama yazın." }
                                // Save labor before finishWork: a finished order rejects new lines.
                                // Retain this flag on failure so retry never repeats saved labor.
                                if(!laborSaved && hours > 0) {
                                    action("addLabor", line, "hours" to hours, "workTypeCode" to value("workTypeCode"), "description" to "")
                                    laborSaved = true
                                }
                                // BC picks the fault code from the fault area and the problem; the terminal never asks for it.
                                action("finishWork", line, "faultAreaCode" to value("faultAreaCode"), "symptomCode" to value("symptomCode"), "faultCode" to "",
                                    "resolutionCode" to value("resolutionCode"), "resolutionNote" to value("resolutionNote").trim())
                            }
                            "İşçilik Ekle", "Teknisyen Ata" -> {
                                require(hours != null && hours.isFinite() && hours > 0) { "Sıfırdan büyük saat girin." }
                                if(dialog == "İşçilik Ekle") action("addLabor", line, "hours" to hours, "workTypeCode" to value("workTypeCode"), "description" to value("description"))
                                else {
                                    require(value("resourceNo").isNotBlank()) { "Teknisyen seçin." }
                                    val date = LocalDate.parse(value("allocationDate")).toString()
                                    action("assignTechnician", line, "resourceNo" to value("resourceNo"), "allocationDate" to date, "hours" to hours)
                                }
                            }
                            "Parça Ekle" -> {
                                val quantity = value("quantity").replace(',', '.').toDoubleOrNull()
                                require(quantity != null && quantity.isFinite() && quantity > 0) { "Geçerli miktar girin." }
                                val scanned = BarcodeIntentResolver.resolve(value("itemNo"))
                                val item = scanned.itemNo ?: scanned.value
                                require(item.isNotBlank()) { "Madde no girin." }
                                // Scanner labels are resolved locally, then checked against the BC item number
                                // (BCWMS items entity: no/description/baseUnitOfMeasure).
                                val r = BcApi.get(context, "items?\$filter=" + Uri.encode("no eq '${serviceODataText(item)}'") + "&\$select=no,description,baseUnitOfMeasure")
                                check(r.ok) { BcApi.errorMessage(r.body) }
                                val verified = BcApi.parseValueArray(r.body).firstOrNull { it.optString("no").equals(item, true) }
                                require(verified != null) { "Madde bulunamadı: $item" }
                                action("addPart", line, "itemNo" to verified.optString("no"), "quantity" to quantity, "locationCode" to "")
                            }
                            "Not Ekle" -> {
                                require(value("text").isNotBlank()) { "Not girin." }
                                action("addComment", line, "commentType" to value("commentType").ifBlank { "General" }, "text" to value("text"))
                            }
                        }
                        dialog = ""; laborSaved = false; message = "İşlem tamamlandı."
                    } finally { refreshAfterAction() }
                }
            }, enabled = !busy && (detailReady || laborSaved), modifier = Modifier.fillMaxWidth().height(52.dp)) {
                Text(if(laborSaved) "İşi Bitirmeyi Tekrar Dene" else if(dialog == "İşi Bitir") "İşi Bitir" else "Kaydet", fontWeight = FontWeight.Bold)
            }
            TextButton({ dismissForm() }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Vazgeç") }
        }
    }
    if (confirmLeaveFinish) AlertDialog(
        onDismissRequest = { confirmLeaveFinish = false },
        title = { Text("İş henüz bitirilmedi") },
        text = { Text("İşçilik kaydedildi, ancak işi bitirme işlemi tamamlanmadı. Girilen arıza ve çözüm bilgileriyle yeniden deneyebilirsiniz. Çıkılsın mı?") },
        confirmButton = { TextButton({ confirmLeaveFinish = false; laborSaved = false; dialog = "" }) { Text("Çık") } },
        dismissButton = { TextButton({ confirmLeaveFinish = false }) { Text("Geri Dön") } },
    )
}

@Composable
private fun ServiceSignature(busy: Boolean, onSave: (Bitmap) -> Unit) {
    val strokes = remember { mutableStateListOf<List<Offset>>() }
    var width by remember { mutableIntStateOf(1) }
    var height by remember { mutableIntStateOf(1) }
    Text("Müşteri İmzası")
    Canvas(Modifier.fillMaxWidth().height(240.dp).background(Color.White).onSizeChanged { width = it.width; height = it.height }
        .pointerInput(busy) {
            if(!busy) detectDragGestures(onDragStart = { strokes.add(listOf(it)) }, onDrag = { change, _ ->
                change.consume(); if(strokes.isNotEmpty()) strokes[strokes.lastIndex] = strokes.last() + change.position
            })
        }) {
        strokes.forEach { stroke -> stroke.zipWithNext().forEach { (a, b) -> drawLine(Color.Black, a, b, 4f) } }
    }
    TextButton({ strokes.clear() }, enabled = !busy) { Text("Temizle") }
    Button({
        val bounds = serviceSignatureSize(strokes.flatten().map { it.x to it.y })
        val bitmap = Bitmap.createBitmap(minOf(width, bounds.first + 4).coerceAtLeast(1), minOf(height, bounds.second + 4).coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)
        canvas.drawColor(android.graphics.Color.WHITE)
        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.BLACK; strokeWidth = 4f; strokeCap = android.graphics.Paint.Cap.ROUND }
        strokes.forEach { it.zipWithNext().forEach { (a,b) -> canvas.drawLine(a.x,a.y,b.x,b.y,paint) } }
        onSave(bitmap)
    }, enabled = !busy && strokes.any { it.size > 1 }) { Text("Kaydet") }
}

/** Decodes a camera JPEG at most ~2x the upload size and applies its EXIF rotation. */
internal fun serviceDecodePhoto(path: String, maxSide: Int = 1600): Bitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(path, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
    val bitmap = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
    val degrees = when (android.media.ExifInterface(path).getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, android.media.ExifInterface.ORIENTATION_NORMAL)) {
        android.media.ExifInterface.ORIENTATION_ROTATE_90 -> 90f
        android.media.ExifInterface.ORIENTATION_ROTATE_180 -> 180f
        android.media.ExifInterface.ORIENTATION_ROTATE_270 -> 270f
        else -> 0f
    }
    if (degrees == 0f) return bitmap
    return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(degrees) }, true)
}
