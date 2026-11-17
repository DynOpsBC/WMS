package com.dynops.bcwms.feature

import org.json.JSONObject
import java.time.LocalDateTime
import java.time.Duration
import java.time.format.DateTimeFormatter
import java.util.Base64
import kotlin.math.ceil

data class ServiceSetup(
    val enabled: Boolean = false, val hideWarehouseModules: Boolean = false,
    val allowTerminalPosting: Boolean = false, val requireSignature: Boolean = false,
    val laborRoundingHours: Double = 0.25, val defaultWorkTypeCode: String = "",
    val isDispatcher: Boolean = false, val id: String = "", val isTechnician: Boolean = false,
    val myResourceNo: String = "",
)
fun parseServiceSetup(json: String): ServiceSetup = runCatching {
    val root = JSONObject(json)
    val o = if (root.has("value")) root.getJSONArray("value").optJSONObject(0) ?: JSONObject() else root
    ServiceSetup(o.optBoolean("enabled"), o.optBoolean("hideWarehouseModules"),
        o.optBoolean("allowTerminalPosting"), o.optBoolean("requireSignature"),
        o.optDouble("laborRoundingHours", 0.25).takeIf { it.isFinite() && it > 0 } ?: 0.25,
        o.optString("defaultWorkTypeCode", ""), o.optBoolean("isDispatcher"), o.optString("id", ""), o.optBoolean("isTechnician"),
        o.optString("myResourceNo", ""))
}.getOrDefault(ServiceSetup())
/** BC API returns option/enum names with spaces encoded as _x0020_ ("In_x0020_Process"). */
fun serviceEnumName(value: String): String = value.replace("_x0020_", " ").trim()
fun serviceStatusLabel(value: String): String = when(serviceEnumName(value)) {
    "Pending" -> "Bekliyor"; "In Process" -> "İşlemde"; "Finished" -> "Tamamlandı"; "On Hold" -> "Beklemede"
    "Active" -> "Aktif"; "Nonactive" -> "Pasif"; "Canceled" -> "İptal"; "Reallocation Needed" -> "Yeniden atanmalı"
    else -> serviceEnumName(value)
}
fun serviceCommentTypeLabel(value: String): String = when(serviceEnumName(value)) {
    "General" -> "Genel"; "Fault" -> "Arıza"; "Resolution" -> "Çözüm"; "Internal" -> "Dahili"; "Accessory" -> "Aksesuar"
    else -> serviceEnumName(value)
}
fun serviceLineTypeLabel(value: String): String = when(serviceEnumName(value)) {
    "Item" -> "Parça"; "Resource" -> "İşçilik"; "Cost" -> "Masraf"; "G/L Account" -> "Hesap"; else -> serviceEnumName(value)
}
/** "0001-01-01" is BC's blank date. */
fun serviceDateText(value: String): String =
    if (value.isBlank() || value.startsWith("0001-01-01")) "" else runCatching {
        java.time.LocalDate.parse(value.take(10)).format(DateTimeFormatter.ofPattern("dd.MM.yyyy"))
    }.getOrDefault(value)
fun serviceTimeText(value: String): String = value.removeSuffix("Z").take(5).takeIf { it.length == 5 && it != "00:00" }.orEmpty()
fun serviceQtyText(value: Double): String =
    if (value == Math.floor(value)) value.toLong().toString() else java.math.BigDecimal(value).setScale(2, java.math.RoundingMode.HALF_UP).stripTrailingZeros().toPlainString().replace('.', ',')
fun servicePriorityLabel(value: String): String = when(serviceEnumName(value)) {
    "High" -> "Yüksek"; "Medium" -> "Orta"; "Low" -> "Düşük"; else -> value
}
/** High first, then Medium, then Low; unknown last. */
fun servicePriorityRank(value: String): Int = when(serviceEnumName(value)) { "High" -> 0; "Medium" -> 1; "Low" -> 2; else -> 3 }
fun servicePriorityColor(value: String): String = when(serviceEnumName(value)) { "High" -> "danger"; "Medium" -> "warning"; "Low" -> "success"; else -> "neutral" }
fun serviceStatusColor(value: String): String = when(serviceEnumName(value)) { "Finished" -> "success"; "On Hold" -> "warning"; "In Process" -> "primary"; else -> "neutral" }
fun serviceElapsedHours(start: LocalDateTime?, now: LocalDateTime, rounding: Double): Double {
    if (start == null) return 0.0
    val stepMinutes = Math.round((rounding.takeIf { it.isFinite() && it > 0 } ?: 0.25) * 60).coerceAtLeast(1)
    val seconds = Duration.between(start, now).seconds.coerceAtLeast(0)
    val stepSeconds = stepMinutes * 60
    // Integer arithmetic: no 3.0000000000000004 style values reach BC.
    val roundedMinutes = ((seconds + stepSeconds - 1) / stepSeconds) * stepMinutes
    return java.math.BigDecimal(roundedMinutes).divide(java.math.BigDecimal(60), 2, java.math.RoundingMode.HALF_UP).toDouble()
}
fun serviceODataText(value: String): String = value.replace("'", "''")
/** Turkish-insensitive search key: "Tüpraş", "TUPRAS" and "tupras" all match. */
fun serviceSearchKey(value: String): String = value.lowercase(java.util.Locale.forLanguageTag("tr-TR"))
    .replace('ç', 'c').replace('ğ', 'g').replace('ı', 'i').replace('ö', 'o').replace('ş', 's').replace('ü', 'u')
    .replace("i̇", "i").trim()
/** Every word of the query must appear in one of the fields (customer name, no, city). */
fun serviceSearchMatches(query: String, vararg fields: String): Boolean {
    val words = serviceSearchKey(query).split(Regex("\\s+")).filter { it.isNotEmpty() }
    if (words.isEmpty()) return false
    val haystack = fields.joinToString(" ") { serviceSearchKey(it) }
    return words.all { haystack.contains(it) }
}
fun serviceCategories(enabled: Boolean, hideWarehouseModules: Boolean): List<String> =
    (if(enabled) listOf("Servis") else emptyList()) +
        (if(enabled && hideWarehouseModules) emptyList() else listOf("Gelen", "Giden", "İç Operasyon", "Üretim", "Kalite", "Sorgu")) + "Destek ve Ayarlar"
fun serviceFileName(orderNo: String, signature: Boolean, now: LocalDateTime): String =
    "${if(signature) "IMZA" else "FOTO"}-$orderNo-${now.format(DateTimeFormatter.ofPattern("yyyyMMddHHmmss"))}.${if(signature) "png" else "jpg"}"
fun serviceActionBody(vararg fields: Pair<String, Any>): String = JSONObject().apply { fields.forEach { put(it.first, it.second) } }.toString()
fun serviceBase64(bytes: ByteArray): String = Base64.getEncoder().encodeToString(bytes)
fun serviceBitmapSize(width: Int, height: Int, maxSide: Int = 1600): Pair<Int, Int> {
    require(width > 0 && height > 0 && maxSide > 0)
    val scale = minOf(1.0, maxSide.toDouble() / maxOf(width, height))
    return maxOf(1, (width * scale).toInt()) to maxOf(1, (height * scale).toInt())
}
fun serviceSignatureSize(points: List<Pair<Float, Float>>): Pair<Int, Int> =
    maxOf(1, ceil((points.maxOfOrNull { it.first } ?: 0f).toDouble()).toInt() + 1) to
        maxOf(1, ceil((points.maxOfOrNull { it.second } ?: 0f).toDouble()).toInt() + 1)
/** Chips show the plain name; the code is only a fallback when BC has no description. */
fun serviceChoiceLabel(code: String, description: String): String = description.trim().ifBlank { code }
/** "Bant · Isınma → Ayar": where, what, and what was done, skipping blanks. */
fun serviceFinishSummary(faultArea: String, symptom: String, resolution: String): String {
    val problem = listOf(faultArea, symptom).map { it.trim() }.filter { it.isNotEmpty() }.joinToString(" · ")
    val done = resolution.trim()
    return when {
        problem.isEmpty() -> done
        done.isEmpty() -> problem
        else -> "$problem → $done"
    }
}
/** − / + next to the labor hours: one rounding step at a time, never below zero, Turkish decimal comma. */
fun serviceStepHours(current: String, direction: Int, step: Double): String {
    val size = step.takeIf { it.isFinite() && it > 0 } ?: 0.25
    val now = current.replace(',', '.').toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 } ?: 0.0
    val steps = Math.round(now / size) + direction
    return serviceQtyText((steps.coerceAtLeast(0) * size))
}
fun serviceLogTypeLabel(value: String): String = when(serviceEnumName(value)) {
    "Note" -> "Not"; "Fault Note" -> "Arıza notu"; "Resolution Note" -> "Çözüm notu"; "Internal Note" -> "Dahili not"
    "Order Description" -> "Sipariş açıklaması"; "Created" -> "Servis açıldı"; "Assigned" -> "Teknisyen atandı"; "Started" -> "İşe başlandı"
    "On Hold" -> "Bekletildi"; "Labor" -> "İşçilik"; "Part" -> "Parça"; "Finished" -> "İş bitirildi"; "Posted" -> "Servis kaydedildi"
    "Attachment" -> "Ek"; "Line Deleted" -> "Satır silindi"; else -> serviceEnumName(value)
}
/** Typed texts (notes, descriptions) stand out in the history; job steps stay in the background. */
fun serviceLogIsNote(value: String): Boolean = serviceEnumName(value) in setOf("Note", "Fault Note", "Resolution Note", "Internal Note", "Order Description", "Created")
/** BC stores log times in UTC ("2026-11-17T09:24:13.063Z"); the technician reads his own clock. */
fun serviceLogTimeText(value: String, zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): String = runCatching {
    java.time.Instant.parse(value).atZone(zone).format(DateTimeFormatter.ofPattern("dd.MM HH:mm"))
}.getOrDefault("")
fun serviceSalesOrderLabel(no: String, orderDate: String, yourReference: String, externalDocumentNo: String): String =
    listOf(no, serviceDateText(orderDate), yourReference.ifBlank { externalDocumentNo }.let { if(it.isBlank()) "" else "Ref: $it" })
        .filter { it.isNotBlank() }.joinToString(" · ")
/** Hours still to enter when finishing: elapsed time minus the labor already on the item, never negative. */
fun serviceRemainingHours(elapsed: Double, alreadyEntered: Double): Double =
    java.math.BigDecimal(elapsed).subtract(java.math.BigDecimal(alreadyEntered)).setScale(2, java.math.RoundingMode.HALF_UP).toDouble().coerceAtLeast(0.0)
/**
 * Notes that the service history does not show: comments typed before the log existed, or by an
 * office user whose entry was not logged. BC stores a note in 80-character lines; a line counts as
 * shown when a logged text contains it.
 */
fun serviceUnloggedComments(comments: List<String>, loggedTexts: List<String>): List<Int> =
    comments.indices.filter { i ->
        val line = comments[i].trim()
        line.isNotEmpty() && loggedTexts.none { it.contains(line) }
    }
/** Where a job stands on the detail screen: 0 = to start, 1 = working, 2 = finished (waiting to be posted). */
fun serviceStep(started: Boolean, finished: Boolean): Int = when {
    finished -> 2
    started -> 1
    else -> 0
}
/** One line under the steps: "Başladı 13:23 · Bitti 13:25 · Rulo · Ses → Değişim", or why the job is on hold. */
fun serviceProgressText(startTime: String, finishTime: String, result: String, holdReason: String): String =
    listOf(if(holdReason.isBlank()) "" else "Bekletiliyor: $holdReason",
        if(startTime.isBlank()) "" else "Başladı $startTime", if(finishTime.isBlank()) "" else "Bitti $finishTime", result)
        .filter { it.isNotBlank() }.joinToString(" · ")
/** One address line; a post code or city already written inside the address lines is not repeated. */
fun serviceAddressText(address: String, address2: String, postCode: String, city: String): String {
    val parts = mutableListOf<String>()
    listOf(address, address2, postCode, city).map { it.trim().replace(Regex("\\s+"), " ") }.filter { it.isNotEmpty() }.forEach { part ->
        val key = serviceSearchKey(part)
        if (parts.none { serviceSearchKey(it).contains(key) }) parts.add(part)
    }
    return parts.joinToString(" ")
}
