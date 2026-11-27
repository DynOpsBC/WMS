package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.ui.InfoPill
import com.dynops.bcwms.ui.StatusText
import com.dynops.bcwms.ui.WmsRefreshLabel
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * e-İrsaliye inceleme sayfası: alıcı, teslim adresi, araç ve şoför gönderilmeden önce kontrol edilir ve
 * değiştirilebilir; sonra gönderilir ve A4 ya da 80 mm yazdırılır. Gönderilen e-İrsaliye artık değişmez.
 * Kayıt (sevk/hareket) çoktan yapılmıştır: bu sayfadaki hiçbir işlem stoğu geri almaz.
 */
@Composable
internal fun EDespatchReviewSheet(entryNo: Int, onClose: () -> Unit) {
    androidx.activity.compose.BackHandler { onClose() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var request by remember { mutableStateOf<JSONObject?>(null) }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var requireVehicle by remember { mutableStateOf(true) }
    var showSendConfirm by remember { mutableStateOf(false) }
    var showReceiverPicker by remember { mutableStateOf(false) }

    // Düzenlenebilir alanlar; yüklenen değerlerle karşılaştırılıp yalnız değişenler gönderilir.
    var receiverType by remember { mutableStateOf(EDespatchReceiverType.Auto) }
    var receiverNo by remember { mutableStateOf("") }
    var receiverName by remember { mutableStateOf("") }
    var receiverAddressCode by remember { mutableStateOf("") }
    var purpose by remember { mutableStateOf(EDespatchPurpose.Unset) }
    var plate by remember { mutableStateOf("") }
    var trailer by remember { mutableStateOf("") }
    var driverFirst by remember { mutableStateOf("") }
    var driverFamily by remember { mutableStateOf("") }
    var driverId by remember { mutableStateOf("") }
    var agent by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }

    fun bind(json: JSONObject) {
        request = json
        receiverType = EDespatchReceiverType.fromValue(json.opt("receiverType"))
        receiverNo = json.optString("receiverNo")
        receiverName = json.optString("receiverName")
        receiverAddressCode = json.optString("receiverAddressCode")
        purpose = EDespatchPurpose.fromValue(json.opt("purpose"))
        plate = json.optString("vehiclePlateNo")
        trailer = json.optString("trailerPlateNo")
        driverFirst = json.optString("driverFirstName")
        driverFamily = json.optString("driverFamilyName")
        driverId = json.optString("driverIdentificationNo")
        agent = json.optString("shippingAgentCode")
        note = json.optString("note")
    }

    fun pendingChanges(): EDespatchChanges {
        val loaded = request ?: return EDespatchChanges()
        fun changed(value: String, key: String) = if (value.trim() != loaded.optString(key).trim()) value else null
        val receiverChanged = receiverType != EDespatchReceiverType.fromValue(loaded.opt("receiverType")) ||
            receiverNo.trim() != loaded.optString("receiverNo") ||
            receiverAddressCode.trim() != loaded.optString("receiverAddressCode")
        return EDespatchChanges(
            receiverType = if (receiverChanged) receiverType else null,
            receiverNo = if (receiverChanged) receiverNo else null,
            receiverAddressCode = if (receiverChanged) receiverAddressCode else null,
            purpose = if (purpose != EDespatchPurpose.fromValue(loaded.opt("purpose"))) purpose else null,
            vehiclePlateNo = changed(plate, "vehiclePlateNo"),
            trailerPlateNo = changed(trailer, "trailerPlateNo"),
            driverFirstName = changed(driverFirst, "driverFirstName"),
            driverFamilyName = changed(driverFamily, "driverFamilyName"),
            driverIdentificationNo = changed(driverId, "driverIdentificationNo"),
            shippingAgentCode = changed(agent, "shippingAgentCode"),
            note = changed(note, "note"),
        )
    }

    suspend fun callAction(action: String, body: JSONObject = JSONObject()): JSONObject? {
        val api = BcApi.postLongRunning(context, "eDespatchRequests($entryNo)/Microsoft.NAV.$action", body.toString())
        if (!api.ok) {
            status = if (BcApi.isAmbiguousMutationFailure(api))
                "HATA: Bağlantı kesildi; işlemin sonucu bilinmiyor. Yenile ile durumu kontrol edin."
            else "HATA: ${BcApi.errorMessage(api.body)} (HTTP ${api.httpCode})"
            return null
        }
        return parseActionJson(api.body)
    }

    fun load() {
        scope.launch {
            busy = true
            val setup = BcApi.get(context, "transferOps?\$top=1")
            if (setup.ok) runCatching {
                JSONObject(setup.body).getJSONArray("value").optJSONObject(0)?.let {
                    requireVehicle = it.optBoolean("eDespatchRequireVehicle", true)
                }
            }
            val json = callAction("getDraft")
            busy = false
            if (json != null) {
                bind(json)
                status = eDespatchSummaryLine(json)
            }
        }
    }

    LaunchedEffect(entryNo) { load() }

    fun save(then: (() -> Unit)? = null) {
        val changes = buildChangesJson(pendingChanges())
        if (changes.length() == 0) {
            then?.invoke()
            return
        }
        scope.launch {
            busy = true
            status = "Değişiklikler kaydediliyor..."
            val json = callAction("updateDraft", JSONObject().put("changesJson", changes.toString()))
            busy = false
            if (json != null) {
                bind(json)
                status = "TAMAM: e-İrsaliye taslağı güncellendi."
                then?.invoke()
            }
        }
    }

    fun send() {
        validateVehicleInfo(plate, driverFirst, driverFamily, driverId, agent, requireVehicle)?.let {
            status = "HATA: $it"
            return
        }
        save {
            scope.launch {
                busy = true
                status = "e-İrsaliye entegratöre gönderiliyor..."
                val json = callAction("send")
                busy = false
                if (json != null) {
                    request = json
                    status = when (EDespatchStatus.fromValue(json.opt("status"))) {
                        EDespatchStatus.Sent, EDespatchStatus.Accepted, EDespatchStatus.Sending ->
                            "TAMAM: e-İrsaliye gönderildi · ${json.optString("eDespatchNo")}"
                        EDespatchStatus.WaitingAdapter -> "UYARI: e-İrsaliye sağlayıcısı bağlı değil. Sevk fişi basabilirsiniz."
                        else -> eDespatchSummaryLine(json)
                    }
                }
            }
        }
    }

    fun print(format: EDespatchPrintFormat) {
        val printerId = getDefaultPrinter(context, printerUsageFor(format))
        scope.launch {
            busy = true
            status = "${format.label} çıktısı yazıcıya gönderiliyor..."
            val json = callAction(
                "print",
                JSONObject().put("format", format.value).put("printerId", printerId).put("copies", 0),
            )
            busy = false
            if (json != null) {
                json.optJSONObject("eDespatch")?.let { request = it }
                val jobId = json.optInt("printJobId")
                status = "TAMAM: ${format.label} çıktısı kuyruğa alındı" + (if (jobId > 0) " (iş $jobId)" else "") +
                    (if (printerId.isBlank()) " · cihaz yazıcısı seçili değil, BC eşlemesi kullanıldı." else " · $printerId")
            }
        }
    }

    fun simple(action: String, message: String) {
        scope.launch {
            busy = true
            status = message
            val json = callAction(action)
            busy = false
            if (json != null) {
                bind(json)
                status = eDespatchSummaryLine(json)
            }
        }
    }

    val current = request
    val requestStatus = EDespatchStatus.fromValue(current?.opt("status"))
    val editable = current?.optBoolean("editable") == true
    val provider = current?.optJSONObject("providerDraft")
    val providerConnected = provider != null || current?.optString("provider").orEmpty().isNotBlank() ||
        requestStatus != EDespatchStatus.WaitingAdapter
    val actions = eDespatchActionsFor(requestStatus, editable, providerConnected)

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp)) {
        TextButton(onClick = onClose, enabled = !busy) { Text("‹ Geri") }
        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
            Column(Modifier.padding(14.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("e-İrsaliye", fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    InfoPill(requestStatus.label)
                }
                Text(current?.optString("eDespatchNo").orEmpty().ifBlank { "Numara gönderimde verilir" }, fontWeight = FontWeight.SemiBold)
                Text(
                    "${current?.optString("sourceTypeCaption").orEmpty()} ${current?.optString("sourceNo").orEmpty()}",
                    fontSize = 12.sp, color = Color.Gray,
                )
                current?.optString("ettn")?.takeIf { it.isNotBlank() }?.let {
                    Text("ETTN $it", fontSize = 10.sp, fontFamily = FontFamily.Monospace, color = Color.Gray)
                }
                Text(
                    "${current?.optString("locationCode").orEmpty()} ${current?.optString("fromBinCode").orEmpty()} → " +
                        "${current?.optString("toLocationCode").orEmpty()} ${current?.optString("toBinCode").orEmpty()}",
                    fontSize = 12.sp,
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Row {
            OutlinedButton(onClick = { if (actions.contains(EDespatchAction.Refresh)) simple("refreshStatus", "Durum okunuyor...") else load() }, enabled = !busy) {
                WmsRefreshLabel(busy)
            }
            if (actions.contains(EDespatchAction.Retry)) {
                Spacer(Modifier.width(8.dp))
                OutlinedButton(onClick = { simple("retry", "Taslak yeniden hazırlanıyor...") }, enabled = !busy) { Text("Tekrar dene") }
            }
        }
        StatusText(status)
        if (requestStatus == EDespatchStatus.NotRequired) {
            Text("Bu hareket için e-İrsaliye gerekmiyor: ${current?.optString("skipReason").orEmpty()}", color = Color.Gray)
            return@Column
        }

        Spacer(Modifier.height(8.dp))
        Text("Alıcı", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            EDespatchReceiverType.entries.filter { it != EDespatchReceiverType.Auto }.forEach { type ->
                val selected = receiverType == type
                if (selected) Button(onClick = {}, enabled = editable && !busy) { Text(type.label, fontSize = 11.sp) }
                else OutlinedButton(
                    onClick = {
                        receiverType = type
                        receiverNo = ""
                        receiverName = if (type == EDespatchReceiverType.OwnCompany) "Kendi şirketim" else ""
                        receiverAddressCode = ""
                        if (type != EDespatchReceiverType.OwnCompany) showReceiverPicker = true
                    },
                    enabled = editable && !busy,
                ) { Text(type.label, fontSize = 11.sp) }
            }
        }
        Card(Modifier.fillMaxWidth().padding(top = 6.dp), shape = RoundedCornerShape(12.dp)) {
            Column(Modifier.padding(12.dp)) {
                Text(receiverName.ifBlank { "Alıcı seçilmedi" }, fontWeight = FontWeight.SemiBold)
                if (receiverNo.isNotBlank()) Text("No: $receiverNo" + if (receiverAddressCode.isNotBlank()) " · Adres $receiverAddressCode" else "", fontSize = 12.sp)
                Text("VKN/TCKN: ${current?.optString("receiverIdentificationNo").orEmpty().ifBlank { "-" }}", fontSize = 12.sp)
                val alias = current?.optString("receiverAlias").orEmpty()
                val registered = current?.optBoolean("receiverRegistered") == true
                Text(
                    if (registered) "e-İrsaliye mükellefi · $alias" else "Mükellef değil: kâğıt çıktı araçla gitmeli · ${alias.ifBlank { "GİB PK" }}",
                    fontSize = 12.sp,
                    color = if (registered) Color.Gray else MaterialTheme.colorScheme.error,
                )
                Text("Teslim: ${current?.optString("deliveryAddress").orEmpty().ifBlank { "-" }}", fontSize = 12.sp)
                if (editable && receiverType in setOf(EDespatchReceiverType.Vendor, EDespatchReceiverType.Customer))
                    TextButton(onClick = { showReceiverPicker = true }, enabled = !busy) { Text("Alıcıyı değiştir") }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(top = 6.dp)) {
            EDespatchPurpose.entries.filter { it != EDespatchPurpose.Unset }.forEach { p ->
                if (purpose == p) Button(onClick = {}, enabled = editable && !busy) { Text(p.label, fontSize = 11.sp) }
                else OutlinedButton(onClick = { purpose = p }, enabled = editable && !busy) { Text(p.label, fontSize = 11.sp) }
            }
        }

        Spacer(Modifier.height(10.dp))
        Text("Taşıma", fontWeight = FontWeight.Bold, fontSize = 16.sp)
        OutlinedTextField(plate, { plate = normalizePlate(it) }, label = { Text("Araç plakası") }, enabled = editable && !busy, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(trailer, { trailer = normalizePlate(it) }, label = { Text("Dorse plakası") }, enabled = editable && !busy, singleLine = true, modifier = Modifier.fillMaxWidth())
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            OutlinedTextField(driverFirst, { driverFirst = it }, label = { Text("Şoför adı") }, enabled = editable && !busy, singleLine = true, modifier = Modifier.weight(1f))
            OutlinedTextField(driverFamily, { driverFamily = it }, label = { Text("Soyadı") }, enabled = editable && !busy, singleLine = true, modifier = Modifier.weight(1f))
        }
        OutlinedTextField(driverId, { driverId = it.filter(Char::isDigit).take(11) }, label = { Text("Şoför TCKN") }, enabled = editable && !busy, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(agent, { agent = it.uppercase() }, label = { Text("Nakliyeci kodu (varsa)") }, enabled = editable && !busy, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(note, { note = it.take(250) }, label = { Text("Not") }, enabled = editable && !busy, modifier = Modifier.fillMaxWidth())

        provider?.optJSONArray("lines")?.let { lines ->
            Spacer(Modifier.height(10.dp))
            Text("Satırlar (${lines.length()})", fontWeight = FontWeight.Bold, fontSize = 16.sp)
            for (i in 0 until lines.length()) {
                val line = lines.optJSONObject(i) ?: continue
                Text(
                    "${line.optString("itemNo")} · ${line.optString("description")} · ${fmtQty(line.optDouble("quantity"))} ${line.optString("unitCode")}" +
                        listOfNotNull(line.optString("lotNo").takeIf { it.isNotBlank() }?.let { "Lot $it" }, line.optString("serialNo").takeIf { it.isNotBlank() }?.let { "Seri $it" })
                            .joinToString(prefix = if (line.optString("lotNo").isNotBlank() || line.optString("serialNo").isNotBlank()) " · " else "", separator = " · "),
                    fontSize = 12.sp,
                )
            }
        }

        Spacer(Modifier.height(12.dp))
        if (actions.contains(EDespatchAction.Save)) {
            OutlinedButton(onClick = { save() }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Değişiklikleri kaydet") }
        }
        if (actions.contains(EDespatchAction.Send)) {
            Button(onClick = { showSendConfirm = true }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Gönder (GİB)") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            if (actions.contains(EDespatchAction.PrintA4))
                OutlinedButton(onClick = { print(EDespatchPrintFormat.A4Official) }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("A4 yazdır") }
            if (actions.contains(EDespatchAction.PrintThermal))
                OutlinedButton(onClick = { print(EDespatchPrintFormat.Thermal80) }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("80 mm yazdır") }
            if (actions.contains(EDespatchAction.PrintSlip))
                OutlinedButton(onClick = { print(EDespatchPrintFormat.A4Fallback) }, enabled = !busy, modifier = Modifier.weight(1f)) { Text("Sevk fişi") }
        }
        if (requestStatus == EDespatchStatus.Draft)
            Text("Gönderilmeden basılan çıktı TASLAK'tır; resmi belge gönderimden sonra basılır.", fontSize = 11.sp, color = Color.Gray)
    }

    if (showSendConfirm) AlertDialog(
        onDismissRequest = { showSendConfirm = false },
        title = { Text("e-İrsaliye gönderilsin mi?") },
        text = {
            Text(
                "Alıcı: ${receiverName.ifBlank { "-" }}\nPlaka: ${plate.ifBlank { "-" }}\n" +
                    "Gönderildikten sonra e-İrsaliye değiştirilemez.",
            )
        },
        confirmButton = { Button(onClick = { showSendConfirm = false; send() }) { Text("Gönder") } },
        dismissButton = { TextButton(onClick = { showSendConfirm = false }) { Text("Vazgeç") } },
    )

    if (showReceiverPicker) ReceiverPickerDialog(
        receiverType = receiverType,
        onDismiss = { showReceiverPicker = false },
        onPicked = { no, name, addressCode ->
            receiverNo = no
            receiverName = name
            receiverAddressCode = addressCode
            showReceiverPicker = false
        },
    )
}

/** Tedarikçi/müşteri ve teslim adresi seçimi (transferOps.listReceivers). */
@Composable
internal fun ReceiverPickerDialog(
    receiverType: EDespatchReceiverType,
    onDismiss: () -> Unit,
    onPicked: (no: String, name: String, addressCode: String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var search by remember { mutableStateOf("") }
    var rows by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var selected by remember { mutableStateOf<JSONObject?>(null) }
    var status by remember { mutableStateOf("") }

    fun find() {
        scope.launch {
            status = "Aranıyor..."
            val body = JSONObject()
                .put("receiverType", receiverType.apiName)
                .put("searchText", search.trim())
                .put("maxCount", 30)
            val api = BcApi.post(context, "transferOps('')/Microsoft.NAV.listReceivers", body.toString())
            if (!api.ok) {
                status = "HATA: ${BcApi.errorMessage(api.body)}"
                return@launch
            }
            val array = runCatching { JSONArray(BcApi.scalarValue(api.body)) }.getOrNull() ?: JSONArray()
            rows = (0 until array.length()).mapNotNull { array.optJSONObject(it) }
            status = if (rows.isEmpty()) "BOŞ: Kayıt bulunamadı." else ""
        }
    }

    LaunchedEffect(receiverType) { find() }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (receiverType == EDespatchReceiverType.Vendor) "Tedarikçi / fasoncu seç" else "Müşteri seç") },
        text = {
            Column {
                OutlinedTextField(search, { search = it }, label = { Text("Ad, no veya VKN") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                TextButton(onClick = { find() }) { Text("Ara") }
                StatusText(status)
                val chosen = selected
                if (chosen == null) {
                    LazyColumn(Modifier.heightIn(max = 320.dp)) {
                        items(rows) { row ->
                            TextButton(onClick = {
                                val addresses = row.optJSONArray("addresses")
                                if (addresses == null || addresses.length() == 0)
                                    onPicked(row.optString("no"), row.optString("name"), "")
                                else selected = row
                            }, modifier = Modifier.fillMaxWidth()) {
                                Column(Modifier.fillMaxWidth()) {
                                    Text(row.optString("name"), fontWeight = FontWeight.SemiBold)
                                    Text("${row.optString("no")} · VKN ${row.optString("vatRegistrationNo").ifBlank { "-" }} · ${row.optString("city")}", fontSize = 11.sp)
                                }
                            }
                        }
                    }
                } else {
                    Text("Teslim adresi", fontWeight = FontWeight.Bold)
                    TextButton(onClick = { onPicked(chosen.optString("no"), chosen.optString("name"), "") }) {
                        Text("Ana adres / hedef lokasyon adresi")
                    }
                    val addresses = chosen.optJSONArray("addresses") ?: JSONArray()
                    for (i in 0 until addresses.length()) {
                        val address = addresses.optJSONObject(i) ?: continue
                        TextButton(onClick = { onPicked(chosen.optString("no"), chosen.optString("name"), address.optString("code")) }) {
                            Text("${address.optString("code")} · ${address.optString("name")} · ${address.optString("city")}")
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Kapat") } },
    )
}
