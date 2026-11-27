package com.dynops.bcwms.feature

import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/*
 * Transfer Sevk ve e-İrsaliye ekranlarının saf kuralları. Compose'a ve ağa bağlı değildir;
 * TransferShipWorkflowTest bu dosyayı doğrudan test eder.
 *
 * BC sözleşmesi (dynops/warehouse/v2.0):
 *   transferOrders('{no}')/Microsoft.NAV.ship            { linesJson, overridesJson, userId, idempotencyKey }
 *   transferOps('')/Microsoft.NAV.createAndShip          { requestJson, userId, idempotencyKey }
 *   transferOps('')/Microsoft.NAV.resolveReceiver        { fromLocationCode, fromBinCode, toLocationCode, toBinCode }
 *   transferOps('')/Microsoft.NAV.listReceivers          { receiverType, searchText, maxCount }
 *   eDespatchRequests({entryNo})/Microsoft.NAV.getDraft | updateDraft | send | print | refreshStatus | retry
 */

/** WMS e-İrsaliye talep durumu; ordinaller AL enum 72215 "DOPSWHS EDesp Status" ile aynıdır. */
internal enum class EDespatchStatus(val ordinal_: Int, val label: String) {
    Pending(0, "Hazırlanıyor"),
    Draft(1, "Taslak"),
    Sending(2, "Gönderiliyor"),
    Sent(3, "Gönderildi"),
    Accepted(4, "Kabul edildi"),
    Rejected(5, "Reddedildi"),
    Cancelled(6, "İptal"),
    Error(7, "Hata"),
    WaitingAdapter(8, "Sağlayıcı bekleniyor"),
    NotRequired(9, "Gerekmiyor");

    companion object {
        fun fromValue(value: Any?): EDespatchStatus {
            val text = value?.toString()?.trim().orEmpty()
            text.toIntOrNull()?.let { number -> entries.firstOrNull { it.ordinal_ == number }?.let { return it } }
            return entries.firstOrNull { it.name.equals(text, ignoreCase = true) } ?: Pending
        }
    }
}

/** Alıcı türü; ordinaller AL enum 72216 "DOPSWHS EDesp Receiver Type" ile aynıdır. */
internal enum class EDespatchReceiverType(val ordinal_: Int, val label: String, val apiName: String) {
    Auto(0, "Otomatik (eşleme)", ""),
    OwnCompany(1, "Kendi şirketim", "OwnCompany"),
    Vendor(2, "Tedarikçi / Fasoncu", "Vendor"),
    Customer(3, "Müşteri / Konsinye", "Customer");

    companion object {
        fun fromValue(value: Any?): EDespatchReceiverType {
            val text = value?.toString()?.trim().orEmpty()
            text.toIntOrNull()?.let { number -> entries.firstOrNull { it.ordinal_ == number }?.let { return it } }
            return entries.firstOrNull { it.apiName.isNotEmpty() && it.apiName.equals(text, ignoreCase = true) } ?: Auto
        }
    }
}

/** Sevk amacı; ordinaller AL enum 72217 "DOPSWHS EDesp Purpose" ile aynıdır. */
internal enum class EDespatchPurpose(val ordinal_: Int, val label: String) {
    Unset(0, "-"),
    InterLocation(1, "Depolar arası"),
    Subcontracting(2, "Fason"),
    Consignment(3, "Konsinye"),
    Other(4, "Diğer");

    companion object {
        fun fromValue(value: Any?): EDespatchPurpose {
            val number = value?.toString()?.trim()?.toIntOrNull() ?: return Unset
            return entries.firstOrNull { it.ordinal_ == number } ?: Unset
        }
    }
}

/** Yazdırma biçimi; AL enum 72218 "DOPSWHS EDesp Print Format". */
internal enum class EDespatchPrintFormat(val value: Int, val label: String) {
    A4Official(0, "A4"),
    Thermal80(1, "80 mm"),
    A4Fallback(2, "Sevk fişi"),
}

internal enum class EDespatchAction { Save, Send, PrintA4, PrintThermal, PrintSlip, Refresh, Retry }

internal data class TransferOrderSummary(
    val no: String,
    val fromCode: String,
    val toCode: String,
    val toName: String,
    val requiresWhseShipment: Boolean,
    val outstandingQuantity: Double,
    val lineCount: Int,
    val fasonReferenceNo: String,
)

internal data class TransferLineSummary(
    val lineNo: Int,
    val itemNo: String,
    val description: String,
    val unitOfMeasureCode: String,
    val outstandingQuantity: Double,
    val toBinCode: String,
    val gtin: String,
    val lotRequired: Boolean,
    val serialRequired: Boolean,
)

/** Operatörün sevk için girdiği satır. */
internal data class TransferShipEntry(
    val lineNo: Int,
    val quantity: Double,
    val lotNo: String = "",
    val serialNo: String = "",
)

/** Yeni transfer için okutulan satır. */
internal data class NewTransferLine(
    val itemNo: String,
    val quantity: Double,
    val unitOfMeasureCode: String = "",
    val variantCode: String = "",
    val lotNo: String = "",
    val serialNo: String = "",
    val fromBinCode: String = "",
    val lpNo: String = "",
)

/** e-İrsaliye inceleme sayfasında düzenlenen alanlar. Boş alanlar gönderilmez. */
internal data class EDespatchChanges(
    val receiverType: EDespatchReceiverType? = null,
    val receiverNo: String? = null,
    val receiverAddressCode: String? = null,
    val purpose: EDespatchPurpose? = null,
    val vehiclePlateNo: String? = null,
    val trailerPlateNo: String? = null,
    val driverFirstName: String? = null,
    val driverFamilyName: String? = null,
    val driverIdentificationNo: String? = null,
    val shippingAgentCode: String? = null,
    val note: String? = null,
)

internal data class TransferShipResult(
    val transferOrderNo: String,
    val postedShipmentNo: String,
    val eDespatchRequired: Boolean,
    val eDespatch: JSONObject?,
) {
    val requestEntryNo: Int get() = eDespatch?.optInt("entryNo") ?: 0
    val status: EDespatchStatus get() = EDespatchStatus.fromValue(eDespatch?.opt("status"))
}

internal data class MovementRegisterResult(
    val activityNo: String,
    val registeredNo: String,
    val eDespatchRequired: Boolean,
    val eDespatch: JSONObject?,
) {
    val requestEntryNo: Int get() = eDespatch?.optInt("entryNo") ?: 0
}

internal fun parseTransferOrders(rows: List<JSONObject>): List<TransferOrderSummary> = rows.map { row ->
    TransferOrderSummary(
        no = row.optString("no"),
        fromCode = row.optString("transferFromCode"),
        toCode = row.optString("transferToCode"),
        toName = row.optString("transferToName"),
        requiresWhseShipment = row.optBoolean("requiresWhseShipment"),
        outstandingQuantity = row.optDouble("outstandingQuantity", 0.0).let { if (it.isNaN()) 0.0 else it },
        lineCount = row.optInt("lineCount"),
        fasonReferenceNo = row.optString("fasonReferenceNo"),
    )
}.filter { it.no.isNotBlank() }

internal fun parseTransferLines(rows: List<JSONObject>): List<TransferLineSummary> = rows.map { row ->
    TransferLineSummary(
        lineNo = row.optInt("lineNo"),
        itemNo = row.optString("itemNo"),
        description = row.optString("description"),
        unitOfMeasureCode = row.optString("unitOfMeasureCode"),
        outstandingQuantity = row.optDouble("outstandingQuantity", 0.0).let { if (it.isNaN()) 0.0 else it },
        toBinCode = row.optString("transferToBinCode"),
        gtin = row.optString("gtin"),
        lotRequired = row.optBoolean("lotRequired"),
        serialRequired = row.optBoolean("serialRequired"),
    )
}.filter { it.itemNo.isNotBlank() && it.outstandingQuantity > 0.0 }

/** Okutulan barkodun hangi transfer satırına ait olduğunu bulur: ürün no, GTIN. */
internal fun matchTransferLine(lines: List<TransferLineSummary>, scanned: String): TransferLineSummary? {
    val value = scanned.trim()
    if (value.isEmpty()) return null
    return lines.firstOrNull { it.itemNo.equals(value, ignoreCase = true) }
        ?: lines.firstOrNull { it.gtin.isNotBlank() && it.gtin.trimStart('0') == value.trimStart('0') }
}

/** Sevk satırlarını kontrol eder; hata mesajı veya null döner. */
internal fun validateShipEntries(lines: List<TransferLineSummary>, entries: List<TransferShipEntry>): String? {
    val positive = entries.filter { it.quantity > 0.0 }
    if (positive.isEmpty()) return "En az bir satıra sevk miktarı girin."
    val byLine = lines.associateBy { it.lineNo }
    positive.groupBy { it.lineNo }.forEach { (lineNo, rows) ->
        val line = byLine[lineNo] ?: return "Satır $lineNo bu transferde yok. Belgeyi yenileyin."
        val total = rows.sumOf { it.quantity }
        if (total > line.outstandingQuantity + 0.000001)
            return "${line.itemNo}: ${fmtQty(total)} girildi, kalan ${fmtQty(line.outstandingQuantity)}."
        if (line.lotRequired && rows.any { it.lotNo.isBlank() }) return "${line.itemNo} lot takipli; lot numarasını okutun."
        if (line.serialRequired && rows.any { it.serialNo.isBlank() }) return "${line.itemNo} seri takipli; seri numarasını okutun."
        if (line.serialRequired && rows.any { it.quantity != 1.0 }) return "${line.itemNo} seri takipli; her seri için miktar 1 olmalı."
    }
    return null
}

internal fun buildShipLinesJson(entries: List<TransferShipEntry>): String {
    val array = JSONArray()
    entries.filter { it.quantity > 0.0 }.forEach { entry ->
        array.put(JSONObject().apply {
            put("lineNo", entry.lineNo)
            put("quantity", entry.quantity)
            if (entry.lotNo.isNotBlank()) put("lotNo", entry.lotNo.trim())
            if (entry.serialNo.isNotBlank()) put("serialNo", entry.serialNo.trim())
        })
    }
    return array.toString()
}

internal fun buildChangesJson(changes: EDespatchChanges): JSONObject = JSONObject().apply {
    changes.receiverType?.let { put("receiverType", it.ordinal_) }
    changes.receiverNo?.let { put("receiverNo", it.trim()) }
    changes.receiverAddressCode?.let { put("receiverAddressCode", it.trim()) }
    changes.purpose?.let { put("purpose", it.ordinal_) }
    changes.vehiclePlateNo?.let { put("vehiclePlateNo", normalizePlate(it)) }
    changes.trailerPlateNo?.let { put("trailerPlateNo", normalizePlate(it)) }
    changes.driverFirstName?.let { put("driverFirstName", it.trim()) }
    changes.driverFamilyName?.let { put("driverFamilyName", it.trim()) }
    changes.driverIdentificationNo?.let { put("driverIdentificationNo", it.filter(Char::isDigit)) }
    changes.shippingAgentCode?.let { put("shippingAgentCode", it.trim().uppercase(Locale.ROOT)) }
    changes.note?.let { put("note", it.trim()) }
}

internal fun buildCreateAndShipJson(
    fromLocationCode: String,
    toLocationCode: String,
    toBinCode: String,
    lines: List<NewTransferLine>,
    changes: EDespatchChanges,
): String {
    val body = buildChangesJson(changes)
    body.put("fromLocationCode", fromLocationCode.trim().uppercase(Locale.ROOT))
    body.put("toLocationCode", toLocationCode.trim().uppercase(Locale.ROOT))
    if (toBinCode.isNotBlank()) body.put("toBinCode", toBinCode.trim().uppercase(Locale.ROOT))
    val array = JSONArray()
    lines.filter { it.quantity > 0.0 && it.itemNo.isNotBlank() }.forEach { line ->
        array.put(JSONObject().apply {
            put("itemNo", line.itemNo.trim())
            put("quantity", line.quantity)
            if (line.unitOfMeasureCode.isNotBlank()) put("unitOfMeasureCode", line.unitOfMeasureCode)
            if (line.variantCode.isNotBlank()) put("variantCode", line.variantCode)
            if (line.lotNo.isNotBlank()) put("lotNo", line.lotNo.trim())
            if (line.serialNo.isNotBlank()) put("serialNo", line.serialNo.trim())
            if (line.fromBinCode.isNotBlank()) put("fromBinCode", line.fromBinCode.trim().uppercase(Locale.ROOT))
            if (line.lpNo.isNotBlank()) put("lpNo", line.lpNo.trim())
        })
    }
    body.put("lines", array)
    return body.toString()
}

/** Yeni transfer formunu kontrol eder; hata mesajı veya null döner. */
internal fun validateNewTransfer(fromLocationCode: String, toLocationCode: String, lines: List<NewTransferLine>): String? = when {
    fromLocationCode.isBlank() -> "Kaynak lokasyonu seçin."
    toLocationCode.isBlank() -> "Hedef lokasyonu seçin."
    fromLocationCode.trim().equals(toLocationCode.trim(), ignoreCase = true) ->
        "Kaynak ve hedef aynı lokasyon. Aynı lokasyondaki raflar arası sevk için Taşıma ekranlarını kullanın."
    lines.none { it.quantity > 0.0 } -> "En az bir ürün okutun."
    lines.any { it.quantity <= 0.0 } -> "Miktarı sıfır olan satırları silin."
    else -> null
}

/** Plaka: boşluklar silinir, Latin harfler büyütülür (Türkçe büyük İ sorununa düşmeden). */
internal fun normalizePlate(value: String): String =
    value.filterNot(Char::isWhitespace).map { ch -> if (ch in 'a'..'z') ch - 32 else ch }.joinToString("")

/**
 * Göndermeden önce taşıma bilgisini kontrol eder. Nakliyeci yoksa şoför adı soyadı gerekir;
 * plaka her durumda istenir (GİB e-İrsaliye kuralı). TCKN girildiyse 11 hane olmalıdır.
 */
internal fun validateVehicleInfo(
    plate: String,
    driverFirstName: String,
    driverFamilyName: String,
    driverIdentificationNo: String,
    shippingAgentCode: String,
    requireVehicle: Boolean = true,
): String? {
    val normalized = normalizePlate(plate)
    if (requireVehicle && normalized.isEmpty()) return "Araç plakasını girin."
    if (normalized.isNotEmpty() && normalized.length < 5) return "Plaka çok kısa: $normalized"
    if (shippingAgentCode.isBlank() && requireVehicle && (driverFirstName.isBlank() || driverFamilyName.isBlank()))
        return "Nakliyeci yoksa şoför adı ve soyadı gerekli."
    val tckn = driverIdentificationNo.filter(Char::isDigit)
    if (driverIdentificationNo.isNotBlank() && tckn.length != 11) return "Şoför TCKN 11 haneli olmalı."
    return null
}

/** Bir talebin durumuna göre sayfada gösterilecek düğmeler. */
internal fun eDespatchActionsFor(status: EDespatchStatus, editable: Boolean, providerConnected: Boolean = true): Set<EDespatchAction> {
    val actions = mutableSetOf(EDespatchAction.Refresh)
    when (status) {
        EDespatchStatus.Draft -> {
            if (editable) actions += EDespatchAction.Save
            actions += setOf(EDespatchAction.Send, EDespatchAction.PrintA4, EDespatchAction.PrintThermal)
        }
        EDespatchStatus.Pending -> actions += EDespatchAction.Retry
        EDespatchStatus.Error -> {
            if (editable) actions += EDespatchAction.Save
            actions += setOf(EDespatchAction.Retry, EDespatchAction.Send, EDespatchAction.PrintSlip)
        }
        EDespatchStatus.WaitingAdapter -> actions += setOf(EDespatchAction.Retry, EDespatchAction.PrintSlip)
        EDespatchStatus.Sending -> Unit
        EDespatchStatus.Sent, EDespatchStatus.Accepted ->
            actions += setOf(EDespatchAction.PrintA4, EDespatchAction.PrintThermal)
        EDespatchStatus.Rejected, EDespatchStatus.Cancelled -> actions += EDespatchAction.PrintA4
        EDespatchStatus.NotRequired -> actions.remove(EDespatchAction.Refresh)
    }
    if (!providerConnected) {
        actions.removeAll(setOf(EDespatchAction.Send, EDespatchAction.PrintA4, EDespatchAction.PrintThermal))
        if (status != EDespatchStatus.NotRequired) actions += EDespatchAction.PrintSlip
    }
    return actions
}

/** Yazdırma formatı için cihazda seçili yazıcı kullanımı (PrintersModule tercih anahtarları). */
internal fun printerUsageFor(format: EDespatchPrintFormat): String = when (format) {
    EDespatchPrintFormat.Thermal80 -> PRINTER_USAGE_THERMAL
    else -> PRINTER_USAGE_DOCUMENT
}

/** BC bound action yanıtı {"value":"<json>"} biçimindedir. */
internal fun parseActionJson(body: String): JSONObject? = runCatching {
    val outer = JSONObject(body)
    val value = outer.opt("value")
    when (value) {
        is JSONObject -> value
        is String -> JSONObject(value)
        else -> outer
    }
}.getOrNull()

internal fun parseTransferShipResult(body: String): TransferShipResult? {
    val json = parseActionJson(body) ?: return null
    return TransferShipResult(
        transferOrderNo = json.optString("transferOrderNo"),
        postedShipmentNo = json.optString("postedShipmentNo"),
        eDespatchRequired = json.optBoolean("eDespatchRequired"),
        eDespatch = json.optJSONObject("eDespatch"),
    )
}

internal fun parseMovementRegisterResult(body: String): MovementRegisterResult? {
    val json = parseActionJson(body) ?: return null
    return MovementRegisterResult(
        activityNo = json.optString("activityNo"),
        registeredNo = json.optString("registeredNo"),
        eDespatchRequired = json.optBoolean("eDespatchRequired"),
        eDespatch = json.optJSONObject("eDespatch"),
    )
}

/** Ekranda gösterilecek kısa durum satırı. */
internal fun eDespatchSummaryLine(request: JSONObject): String {
    val status = EDespatchStatus.fromValue(request.opt("status"))
    val no = request.optString("eDespatchNo").ifBlank { "No yok" }
    val receiver = request.optString("receiverName").ifBlank { "Alıcı belirlenmedi" }
    return when (status) {
        EDespatchStatus.NotRequired -> "e-İrsaliye gerekmiyor · ${request.optString("skipReason")}"
        EDespatchStatus.Error -> "e-İrsaliye HATA · ${request.optString("lastError").take(160)}"
        else -> "e-İrsaliye ${status.label} · $no · $receiver"
    }
}

internal fun fmtQty(value: Double): String =
    if (value % 1.0 == 0.0) value.toLong().toString() else String.format(Locale.ROOT, "%.3f", value).trimEnd('0').trimEnd('.')
