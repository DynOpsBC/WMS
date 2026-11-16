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
    val isDispatcher: Boolean = false,
)
fun parseServiceSetup(json: String): ServiceSetup = runCatching {
    val root = JSONObject(json)
    val o = if (root.has("value")) root.getJSONArray("value").optJSONObject(0) ?: JSONObject() else root
    ServiceSetup(o.optBoolean("enabled"), o.optBoolean("hideWarehouseModules"),
        o.optBoolean("allowTerminalPosting"), o.optBoolean("requireSignature"),
        o.optDouble("laborRoundingHours", 0.25).takeIf { it.isFinite() && it > 0 } ?: 0.25,
        o.optString("defaultWorkTypeCode", ""), o.optBoolean("isDispatcher"))
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
