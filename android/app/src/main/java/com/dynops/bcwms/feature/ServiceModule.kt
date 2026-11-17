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

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
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
            values = values + ("hours" to serviceElapsedHours(start, LocalDateTime.now(), setup.laborRoundingHours).toString())
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
        message = ""
        dialog = "Yeni Servis"
        if (customers.isEmpty()) runJob {
            customers = fetch("serviceCustomers?\$select=no,name,city,blocked")
                .filter { serviceEnumName(it.optString("blocked")) != "All" }
        }
    }
    fun selectCustomer(c: JSONObject) {
        values = values + ("customerNo" to c.optString("no")) + ("customerName" to c.optString("name")) +
            ("customerCity" to c.optString("city")) + ("serviceItemNo" to "")
        customerItems = emptyList()
        runJob { customerItems = fetch("serviceItems?\$filter=" + Uri.encode("customerNo eq '${serviceODataText(c.optString("no"))}'")) }
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
                            Text(listOf(row.optString("city"), row.optString(if(all) "description" else "serviceItemDescription")).filter { it.isNotBlank() }.joinToString(" · "),
                                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                statusPill(row.optString(if(all) "status" else "orderStatus"))
                                if(!all && row.optString("repairStatus").isNotBlank()) InfoPill("Onarım: " + row.optString("repairStatus"))
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
            TextButton({ dialog = ""; laborSaved = false; message = ""; order = null; runJob { reload() } }, enabled = !busy) { Text(if(all) "‹ Tüm İşler" else "‹ İşlerim") }
            val o = order!!
            DocHeaderCard(o.optString("no"), listOf(o.optString("name"), o.optString("city")).filter { it.isNotBlank() }.joinToString(" · "),
                badge = o.optString("status").takeIf { it.isNotBlank() }?.let { serviceStatusLabel(it) })
            fun launchUri(action: String, uri: String) { runCatching { context.startActivity(Intent(action, Uri.parse(uri))) }.onFailure { message = "Uygun uygulama bulunamadı." } }
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if(o.optString("description").isNotBlank()) Text(o.optString("description"), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        o.optString("priority").takeIf { it.isNotBlank() }?.let { InfoPill("Öncelik: " + servicePriorityLabel(it), priorityColor(it).copy(alpha = 0.14f), priorityColor(it)) }
                        serviceDateText(o.optString("responseDate")).takeIf { it.isNotBlank() }?.let { InfoPill("Yanıt: $it ${serviceTimeText(o.optString("responseTime"))}".trim()) }
                    }
                    if(o.optString("contactName").isNotBlank()) Text("İlgili: " + o.optString("contactName"), style = MaterialTheme.typography.bodyMedium)
                    val address = listOf("address", "address2", "postCode", "city").map { o.optString(it) }.filter { it.isNotBlank() }.joinToString(" ")
                    if(address.isNotBlank()) OutlinedButton({ launchUri(Intent.ACTION_VIEW, "geo:0,0?q=${Uri.encode(address)}") }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                        Text("Adres: $address", maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    listOf("phoneNo", "phoneNo2").map { o.optString(it) }.filter { it.isNotBlank() }.forEach { phone ->
                        OutlinedButton({ launchUri(Intent.ACTION_DIAL, "tel:${Uri.encode(phone)}") }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Ara: $phone") }
                    }
                    if(o.optString("technicianNames").isNotBlank()) Text("Teknisyen: " + o.optString("technicianNames"), style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            sectionTitle("Servis kalemi")
            itemLines.forEach { line ->
                val isSel = selectedLine == line.optInt("lineNo")
                Card(onClick = { if(!busy) selectedLine = line.optInt("lineNo") }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = if(isSel) MaterialTheme.colorScheme.primary.copy(alpha = 0.08f) else MaterialTheme.colorScheme.surface),
                    border = androidx.compose.foundation.BorderStroke(if(isSel) 2.dp else 1.dp, if(isSel) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant)) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(line.optString("description"), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                        Text(listOf(line.optString("serviceItemNo"), line.optString("serialNo").let { if(it.isBlank()) "" else "Seri: $it" }).filter { it.isNotBlank() }.joinToString(" · "),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            if(line.optString("repairStatusCode").isNotBlank()) InfoPill("Onarım: " + line.optString("repairStatusCode"))
                            serviceDateText(line.optString("startingDate")).takeIf { it.isNotBlank() }?.let { InfoPill("Başladı ${serviceTimeText(line.optString("startingTime"))}") }
                            serviceDateText(line.optString("finishingDate")).takeIf { it.isNotBlank() }?.let { InfoPill("Bitti ${serviceTimeText(line.optString("finishingTime"))}", status.success.copy(alpha = 0.14f), status.success) }
                        }
                        val codes = listOf("faultAreaCode", "symptomCode", "faultCode", "resolutionCode").map { line.optString(it) }.filter { it.isNotBlank() }
                        if(codes.isNotEmpty()) Text("Arıza/çözüm: " + codes.joinToString(" / "), style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
            val selected = itemLines.firstOrNull { it.optInt("lineNo") == selectedLine }
            val ready = !busy && detailReady && selected != null
            if(selected?.optString("startingDate").let { it.isNullOrBlank() || it == "0001-01-01" }) {
                Button({ execute("startWork", "serviceItemLineNo" to selectedLine) }, enabled = ready,
                    modifier = Modifier.fillMaxWidth().height(wmsPrimaryButtonHeight())) { Text("İşe Başla", fontWeight = FontWeight.Bold) }
            }
            // A finished line only takes photos, the signature and notes before posting.
            val lineFinished = selected?.optString("finishingDate").let { !it.isNullOrBlank() && it != "0001-01-01" }
            val actions = buildList {
                if(!lineFinished) { add("İşi Bitir"); add("Beklet"); add("Parça Ekle"); add("İşçilik Ekle") }
                add("Fotoğraf"); add("Müşteri İmzası"); add("Not Ekle")
                if(setup.isDispatcher && !lineFinished) add("Teknisyen Ata")
            }
            if(lineFinished) Text("İş bitirildi. Fotoğraf ve müşteri imzasını ekleyip servisi kaydedin.",
                style = MaterialTheme.typography.bodyMedium, color = status.success, fontWeight = FontWeight.SemiBold)
            actions.chunked(2).forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    pair.forEach { name ->
                        OutlinedButton({
                            when(name) {
                                "Fotoğraf" -> if (androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) launchCamera()
                                    else cameraPermission.launch(android.Manifest.permission.CAMERA)
                                "Müşteri İmzası" -> { message = ""; dialog = "Müşteri İmzası" }
                                else -> open(name)
                            }
                        }, enabled = if(name == "Fotoğraf" || name == "Müşteri İmzası") !busy && detailReady else ready,
                            modifier = Modifier.weight(1f).height(50.dp), shape = RoundedCornerShape(12.dp)) {
                            Text(name, fontWeight = FontWeight.SemiBold, maxLines = 1)
                        }
                    }
                    if(pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
            sectionTitle("Parça ve işçilik (${lines.size})")
            if(lines.isEmpty()) Text("Henüz parça veya işçilik eklenmedi.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            lines.forEach { line ->
                val shipped = line.optDouble("quantityShipped", 0.0)
                Card(Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClick = {
                    if(!busy && detailReady && shipped == 0.0 && line.optDouble("quantityConsumed", 0.0) == 0.0) deleteLine = line
                }), shape = RoundedCornerShape(12.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        InfoPill(serviceLineTypeLabel(line.optString("type")))
                        Column(Modifier.weight(1f)) {
                            Text(line.optString("description"), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            Text(listOf(line.optString("no"), line.optString("locationCode")).filter { it.isNotBlank() }.joinToString(" · "),
                                style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text("${serviceQtyText(line.optDouble("quantity", 0.0))} ${line.optString("unitOfMeasureCode")}", fontWeight = FontWeight.Bold)
                            if(shipped > 0) Text("Sevk: ${serviceQtyText(shipped)}", style = MaterialTheme.typography.labelSmall, color = status.success)
                        }
                    }
                }
            }
            if(lines.any { it.optDouble("quantityShipped", 0.0) == 0.0 }) Text("Kaydedilmemiş satırı silmek için satıra uzun basın.",
                style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            sectionTitle("Notlar (${comments.size})")
            comments.forEach {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                    InfoPill(serviceCommentTypeLabel(it.optString("type")))
                    Text("${serviceDateText(it.optString("date"))}  ${it.optString("comment")}", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                }
            }
            sectionTitle("Ekler (${attachments.size})")
            attachments.forEach { Text("• " + it.optString("fileName") + it.optString("fileExtension").let { e -> if(e.isBlank() || it.optString("fileName").endsWith(".$e")) "" else ".$e" },
                style = MaterialTheme.typography.bodySmall) }
            if(setup.allowTerminalPosting) Button({ dialog = "Servisi Kaydet" }, enabled = !busy && detailReady && lines.isNotEmpty(),
                modifier = Modifier.fillMaxWidth().height(wmsPrimaryButtonHeight()), colors = ButtonDefaults.buttonColors(containerColor = status.success)) {
                Text("Servisi Kaydet", fontWeight = FontWeight.Bold)
            }
            OutlinedButton({ runJob { reload() } }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { WmsRefreshLabel(busy) }
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
                        TextButton({ values = values - "customerNo" - "customerName" - "customerCity" - "serviceItemNo"; customerItems = emptyList() }, enabled = !busy) { Text("Değiştir") }
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
                        val r = BcApi.post(context, "serviceSetups(${setup.id})/Microsoft.NAV.createServiceOrder", serviceActionBody(
                            "customerNo" to value("customerNo"), "serviceItemNo" to value("serviceItemNo"),
                            "description" to value("description").trim(), "priority" to value("priority").ifBlank { "Medium" },
                            "assignToMe" to (value("assignToMe") == "true")))
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
                                if(key == "faultAreaCode" || key == "symptomCode") values = values + ("faultCode" to "")
                                expanded = false
                            }) }
                        }
                    }
                }
            }
            when(dialog) {
                "Beklet" -> choose("repairStatusCode", "Onarım durumu", catalog["serviceRepairStatuses"].orEmpty().filter { it.optBoolean("waitingForCustomer") || it.optBoolean("sparePartOrdered") })
                "İşi Bitir" -> {
                    choose("faultAreaCode", "Arıza alanı", catalog["serviceFaultAreas"].orEmpty())
                    choose("symptomCode", "Belirti", catalog["serviceSymptomCodes"].orEmpty())
                    choose("faultCode", "Arıza", catalog["serviceFaultCodes"].orEmpty().filter { it.optString("faultAreaCode") == value("faultAreaCode") && (it.optString("symptomCode").isBlank() || it.optString("symptomCode") == value("symptomCode")) })
                    choose("resolutionCode", "Çözüm", catalog["serviceResolutionCodes"].orEmpty())
                    field("resolutionNote", "Çözüm notu")
                }
                "Parça Ekle" -> {
                    ScanField(label = "Madde no / barkod", value = value("itemNo"), onValueChange = { values = values + ("itemNo" to it) }, onScanned = { values = values + ("itemNo" to it) }, enabled = !busy)
                    field("quantity", "Miktar")
                }
                "Not Ekle" -> {
                    choose("commentType", "Not türü", listOf("General" to "Genel", "Fault" to "Arıza", "Resolution" to "Çözüm", "Internal" to "Dahili").map { JSONObject().put("code", it.first).put("description", it.second) }, showCode = false)
                    field("text", "Not")
                }
                "Teknisyen Ata" -> {
                    choose("resourceNo", "Teknisyen", catalog["serviceTechnicians"].orEmpty(), "resourceNo")
                    field("allocationDate", "Atama tarihi (yyyy-AA-gg)")
                }
            }
            if(dialog in listOf("İşi Bitir", "İşçilik Ekle", "Teknisyen Ata")) field("hours", if(dialog == "Teknisyen Ata") "Planlanan süre (saat)" else "İşçilik saati")
            if(dialog in listOf("İşi Bitir", "İşçilik Ekle")) choose("workTypeCode", "İş türü", catalog["serviceWorkTypes"].orEmpty())
            if(dialog == "İşçilik Ekle") field("description", "Açıklama")
            Button({
                runJob {
                    try {
                        val line = "serviceItemLineNo" to selectedLine
                        val hours = value("hours").replace(',', '.').toDoubleOrNull()
                        when(dialog) {
                            "Beklet" -> { require(value("repairStatusCode").isNotBlank()) { "Onarım durumu seçin." }; action("setRepairStatus", line, "repairStatusCode" to value("repairStatusCode")) }
                            "İşi Bitir" -> {
                                require(hours != null && hours.isFinite() && hours >= 0) { "Geçerli saat girin." }
                                // Save labor before finishWork: a finished order rejects new lines.
                                // Retain this flag on failure so retry never repeats saved labor.
                                if(!laborSaved && hours > 0) {
                                    action("addLabor", line, "hours" to hours, "workTypeCode" to value("workTypeCode"), "description" to "")
                                    laborSaved = true
                                }
                                action("finishWork", line, *listOf("faultAreaCode", "symptomCode", "faultCode", "resolutionCode", "resolutionNote").map { it to value(it) }.toTypedArray())
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
