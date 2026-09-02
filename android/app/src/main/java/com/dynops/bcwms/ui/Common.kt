package com.dynops.bcwms.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.json.JSONObject

/** First non-blank API value among the given keys; empty if none. */
fun rawValue(obj: JSONObject, vararg keys: String): String {
    for (key in keys) {
        val value = obj.optString(key)
        if (value.isNotBlank() && value != "null") return value
    }
    return ""
}

/** Display-only variant of [rawValue]; never pass its "-" placeholder to BC. */
fun firstValue(obj: JSONObject, vararg keys: String): String =
    rawValue(obj, *keys).ifBlank { "-" }

@Composable
fun EmptyState(message: String) {
    Card(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Text(
            message,
            Modifier.padding(16.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * Operasyon listelerinin ortak belge kartı. Uzun kaynak/lokasyon/kullanıcı
 * bilgilerini telefonda güvenli biçimde iki satıra sınırlar; eski renkli dolgu
 * yerine beyaz zemin ve ince sınır kullanır.
 */
@Composable
fun OperationDocumentCard(
    title: String,
    metadata: String,
    onClick: () -> Unit,
    status: String = "",
    progressPercent: Int? = null,
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                if (status.isNotBlank()) {
                    Spacer(Modifier.width(8.dp))
                    Surface(
                        color = MaterialTheme.colorScheme.primaryContainer,
                        shape = RoundedCornerShape(50),
                    ) {
                        Text(
                            status,
                            modifier = Modifier.padding(horizontal = 9.dp, vertical = 4.dp),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
            Spacer(Modifier.height(4.dp))
            Text(
                metadata,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            progressPercent?.let { percent ->
                Spacer(Modifier.height(9.dp))
                LinearProgressIndicator(
                    progress = { percent.coerceIn(0, 100) / 100f },
                    modifier = Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(50)),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.surfaceVariant,
                )
            }
        }
    }
}

/** Status banner that colour-codes PASS / EMPTY / error text. */
@Composable
fun StatusText(status: String) {
    if (status.isBlank()) return
    val visibleStatus = operatorFacingStatus(status)
    val palette = bcwmsStatus()
    val color = when {
        visibleStatus.startsWith("TAMAM") || visibleStatus.startsWith("🟢") || visibleStatus.startsWith("✅") -> palette.success
        visibleStatus.startsWith("BOŞ") || visibleStatus.startsWith("⚠️") -> palette.warning
        visibleStatus.startsWith("HATA") || visibleStatus.startsWith("🔴") || visibleStatus.startsWith("❌") -> palette.danger
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Surface(
        color = color.copy(alpha = 0.10f),
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(Modifier.padding(horizontal = 11.dp, vertical = 9.dp), verticalAlignment = Alignment.Top) {
            val glyph = if (visibleStatus.startsWith("HATA") || visibleStatus.startsWith("BOŞ") || visibleStatus.startsWith("⚠")) {
                WmsGlyph.WARNING
            } else {
                WmsGlyph.QUALITY
            }
            WmsIcon(glyph, color, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(
                visibleStatus,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

/**
 * API ayrıntıları destek kaydında kalır; saha operatörüne yalnız yapılabilir
 * bir sonraki adım gösterilir. Bu dönüşüm yalnız ekrana basılan metne uygulanır,
 * iş akışının hata sınıflandırmasını değiştirmez.
 */
fun operatorFacingStatus(raw: String): String {
    if (raw.isBlank()) return raw
    val englishBcValidation = Regex(
        """\b(required|must|cannot|already|not\s+found|no\s+longer|nothing\s+to|not\s+allowed|unable\s+to|failed\s+to)\b""",
        RegexOption.IGNORE_CASE,
    ).containsMatchIn(raw) ||
        Regex("""\b(Table|Field)\s+[A-Za-z0-9_. -]+""", RegexOption.IGNORE_CASE).containsMatchIn(raw) ||
        raw.contains("No.=", ignoreCase = true)
    val technicalDeployment = raw.contains("publish", ignoreCase = true) ||
        raw.contains("güncel BC", ignoreCase = true) ||
        raw.contains("uzantısını yayın", ignoreCase = true) ||
        raw.contains("CorrelationId", ignoreCase = true) ||
        raw.contains("Identification fields", ignoreCase = true) ||
        raw.contains("Microsoft.", ignoreCase = true) ||
        raw.contains("Exception", ignoreCase = true) ||
        raw.contains("Bad Request", ignoreCase = true) ||
        raw.contains("OData", ignoreCase = true) ||
        raw.contains(" does not ", ignoreCase = true) ||
        raw.contains(" is not ", ignoreCase = true) ||
        englishBcValidation ||
        raw.trimStart().startsWith("{")
    if (technicalDeployment) {
        operatorSafeBcMessage(raw)?.let { return "HATA: $it" }
        return operatorFacingApiError(raw)
    }
    return raw
        .replace(Regex("""\s*\(HTTP\s*\d+\)""", RegexOption.IGNORE_CASE), "")
        .replace(Regex("""\bHTTP\s*\d+\b""", RegexOption.IGNORE_CASE), "")
        .replace(Regex("""\breclass\b""", RegexOption.IGNORE_CASE), "stok hareketi")
        .replace(Regex("""\bslot\b""", RegexOption.IGNORE_CASE), "sayıcı")
        .replace(Regex("""\s{2,}"""), " ")
        .trim()
}

/** Stable, non-sensitive reference for matching an operator report to raw logs. */
fun operatorSupportReference(raw: String, httpCode: Int = 0): String =
    "REF-" + "$httpCode:${raw.trim()}".hashCode().toUInt().toString(16).uppercase().padStart(8, '0')

/**
 * BCWMS'in kendi AL hataları Türkçe ve operatöre yöneliktir ("Araç bilgileri
 * eksik…", "Terminal kullanıcısı … kayıtlı değil"). Bunlar yalnız yanlarındaki
 * CorrelationId/HTTP eki yüzünden maskeleniyor, kullanıcı adı/şirket gibi
 * eyleme dönük bilgi kayboluyordu. Ek temizlenince İngilizce/teknik iz
 * kalmıyorsa ve metin Türkçe ise mesaj olduğu gibi döner; aksi halde null.
 * "HATA:" öneki çıkarılmış döner; çağıran ekler.
 */
fun operatorSafeBcMessage(raw: String): String? {
    val stripped = raw
        .replace(Regex("""\s*CorrelationId:\s*[0-9a-fA-F-]+\.?""", RegexOption.IGNORE_CASE), "")
        .replace(Regex("""\s*\(HTTP\s*\d+\)""", RegexOption.IGNORE_CASE), "")
        .replace(Regex("""\bHTTP\s*\d+\b""", RegexOption.IGNORE_CASE), "")
        .replace(Regex("""\s{2,}"""), " ")
        .trim()
        .removePrefix("HATA:").trim()
    if (stripped.isBlank() || stripped.startsWith("{")) return null
    val technical = Regex(
        """\b(required|must|cannot|already|not\s+found|no\s+longer|nothing\s+to|not\s+allowed|unable\s+to|failed\s+to|does\s+not|is\s+not|Exception|OData|Bad\s+Request|Identification\s+fields|publish)\b""",
        RegexOption.IGNORE_CASE,
    ).containsMatchIn(stripped) ||
        Regex("""\b(Table|Field)\s+[A-Za-z0-9_. -]+""").containsMatchIn(stripped) ||
        stripped.contains("Microsoft.") ||
        stripped.contains("No.=") ||
        stripped.contains("güncel BC", ignoreCase = true) ||
        stripped.contains("uzantısını yayın", ignoreCase = true)
    if (technical) return null
    // Operatör metni Türkçedir. Türkçe karakter ya da yaygın Türkçe iş kuralı
    // sözcükleri yoksa kaynağı bilinmeyen bir İngilizce mesajdır ve maskelenir.
    // ("Sevkiyat Acente Kodu zorunludur. Belge No: X" gibi ASCII Türkçe
    // mesajlar da geçmeli.)
    val turkish = Regex("""[çğıöşüÇĞİÖŞÜ]""").containsMatchIn(stripped) ||
        Regex("""\b(zorunlu|zorunludur|gerekli|lütfen|belge|sipariş|kayıt|raf|sevk|kabul|kod|seçin|girin|bulunamadı|tamamla|kontrol)\w*""", RegexOption.IGNORE_CASE).containsMatchIn(stripped)
    if (!turkish) return null
    return stripped
}

/**
 * Miktar alanı: Türkçe klavyede ondalık ayırıcı virgüldür. Virgül noktaya
 * çevrilir, rakam ve tek nokta dışındaki her şey atılır. Aksi halde "12,5"
 * "125" olur (10 kat miktar riski).
 */
fun normalizeQtyInput(raw: String): String {
    val cleaned = raw.replace(',', '.').filter { it.isDigit() || it == '.' }
    val first = cleaned.indexOf('.')
    if (first < 0) return cleaned
    return cleaned.substring(0, first + 1) + cleaned.substring(first + 1).replace(".", "")
}

/** Sık görülen İngilizce BC iş kuralı hataları → eyleme dönük Türkçe metin (null = eşleşme yok). */
fun operatorKnownBcError(raw: String): String? {
    Regex("""cannot handle more than the outstanding\s+(\d+(?:[.,]\d+)?)""", RegexOption.IGNORE_CASE).find(raw)?.let {
        return "Kalan miktardan fazla giremezsiniz (kalan: ${it.groupValues[1]}). Miktarı düzeltin."
    }
    Regex("""Qty\. to Ship must not be greater than\s+(\d+(?:[.,]\d+)?)""", RegexOption.IGNORE_CASE).find(raw)?.let {
        return "Sevk miktarı kalan miktardan (${it.groupValues[1]}) fazla olamaz."
    }
    Regex("""Qty\. to Receive must not be greater than\s+(\d+(?:[.,]\d+)?)""", RegexOption.IGNORE_CASE).find(raw)?.let {
        return "Alınan miktar kalan miktardan (${it.groupValues[1]}) fazla olamaz."
    }
    if (Regex("""Status must be equal to 'Open'\s+in Warehouse Shipment Header""", RegexOption.IGNORE_CASE).containsMatchIn(raw))
        return "Sevkiyat serbest bırakılmış (Released): satır miktarı/lotu BC'de doğrudan değiştirilemez. Miktarı ve lotu Pick Oluştur ile toplayarak belirleyin."
    if (Regex("""Status must be equal to 'Open'\s+in Warehouse Receipt Header""", RegexOption.IGNORE_CASE).containsMatchIn(raw))
        return "Mal kabul belgesi serbest bırakılmış; satır BC'de doğrudan değiştirilemez. Belgeyi BC'de yeniden açın."
    Regex("""Qty\. to Handle \(Base\) in the item tracking assigned to the document line for item\s+(\S+)\s+is currently\s+(\d+(?:[.,]\d+)?)\. It must be\s+(\d+(?:[.,]\d+)?)""", RegexOption.IGNORE_CASE).find(raw)?.let {
        val (item, cur, need) = it.destructured
        return "$item ürününün lot dağılımı ($cur) sevk miktarıyla ($need) uyuşmuyor. Toplamayı (pick) tamamlayıp kaydedin veya BC'de sevk miktarını $cur yapın."
    }
    Regex("""cannot assign new numbers from the number series\s+(\S+?)\.?(\s|$)""", RegexOption.IGNORE_CASE).find(raw)?.let {
        return "${it.groupValues[1]} numara serisi yeni numara veremiyor (seri tükenmiş veya kapalı). İşlem BC'de kaydedilmiş olabilir; belgeyi yenileyip kontrol edin ve numara serisini uzatması için yöneticiye bildirin."
    }
    // Ad-Hoc harekette olmayan raf: BC "Cannot determine a location for bin X" der,
    // bu da genel REF mesajina dusuyordu; operator rafin yanlis oldugunu anlamiyordu.
    Regex("""Cannot determine a location for bin\s+(\S+?)[.\s]""", RegexOption.IGNORE_CASE).find(raw)?.let {
        return "${it.groupValues[1]} rafı depoda kayıtlı değil. Raf etiketini yeniden okutun veya raf listesinden seçin."
    }
    // Ad-Hoc hedef raf kontrolü ayrı bir metin döndürüyor: "Target bin X does
    // not exist in location Y" (UAT fx-04c).
    Regex("""(?:Target|Source|From|To)\s+bin\s+(\S+?)\s+does not exist in location\s+(\S+?)[.\s]""", RegexOption.IGNORE_CASE).find(raw)?.let {
        val (bin, loc) = it.destructured
        return "$bin rafı $loc lokasyonunda yok. Raf etiketini yeniden okutun veya raf listesinden seçin."
    }
    // Stoktan fazla tasima: gercek raf bakiyesini yaz.
    Regex("""Tracking quantity\s+([\d.,]*\d)\s+exceeds available bin quantity\s+([\d.,]*\d)""", RegexOption.IGNORE_CASE).find(raw)?.let {
        val (istenen, mevcut) = it.destructured
        return "Rafta yeterli stok yok: bu raf/lot için $mevcut var, $istenen istediniz. Miktarı düşürün ya da başka raftan alın."
    }
    Regex("""do not match the available bin content""", RegexOption.IGNORE_CASE).find(raw)?.let {
        return "Girilen miktar bu rafın bakiyesiyle uyuşmuyor. 'Kaynak Bindeki Lotları Göster' ile raftaki lot ve miktarları kontrol edin."
    }
    // Olmayan urun/kayit: BC'nin "does not exist" kalibi.
    Regex("""The\s+(.+?)\s+does not exist[^.]*\.\s*Identification fields and values:\s*(.+?)(\.|$)""", RegexOption.IGNORE_CASE).find(raw)?.let {
        val (tur, deger) = it.destructured
        return "$tur kaydı bulunamadı ($deger). Okuttuğunuz kodu kontrol edin."
    }
    // BC "Qty. to Ship must not be greater than 0" derken satirda kalan miktar
    // gorunuyordu; eski ceviri "kalan miktardan (0) fazla olamaz" diyerek
    // operatoru yaniltiyordu. Gercek sebep: satira sevk miktari girilmemis.
    Regex("""Qty\. to Ship must not be greater than\s*0(\D|$)""", RegexOption.IGNORE_CASE).find(raw)?.let {
        return "Bu depoda sevk miktarı toplamadan gelir; elle girilemez. Önce 'Pick Oluştur' ile toplama yapıp kaydedin, sonra sevkiyatı kaydedin."
    }
    Regex("""is already being packed""", RegexOption.IGNORE_CASE).find(raw)?.let {
        return "Bu siparişte açık bir paketleme var. Paketlemeyi tamamlayın ya da kapatın, sonra sevkiyatı tekrar deneyin."
    }
    if (raw.contains("Nothing to handle", ignoreCase = true))
        return "Toplanacak miktar yok: stok zaten sevk rafında ya da uygun rafta bulunamadı. BC'de raf içeriğini ve mevcut toplama belgelerini kontrol edin."
    // "... contains a value (X) that cannot be found in the related table (Y)"
    // Local WMS User için daha özel bir kural yukarıda; burası diğer tablolar.
    Regex("""contains a value \(([^)]*)\) that cannot be found in the related table \(([^)]*)\)""", RegexOption.IGNORE_CASE).find(raw)?.let {
        val (deger, tablo) = it.destructured
        if (!tablo.contains("Local WMS User", ignoreCase = true))
            return "$deger, $tablo listesinde tanımlı değil. Listeden kayıtlı bir değer seçin."
    }
    if (raw.contains("Quantity Handled (Base) must be equal to '0'", ignoreCase = true) && raw.contains("Whse. Item Tracking Line", ignoreCase = true))
        return "Bu satırda kısmen kaydedilmiş lot izleme var; açık toplamayı tamamlayıp kaydedin, sonra tekrar deneyin."
    Regex("""Over-Receipt Code - (\S+), allows you to receive up to\s+(\d+(?:[.,]\d+)?)""", RegexOption.IGNORE_CASE).find(raw)?.let {
        return "Fazla kabul sınırı aşıldı (${it.groupValues[1]}): en fazla ${it.groupValues[2]} alınabilir."
    }
    // Yazıcı hataları: genel "Yazıcı ayarı tamamlanamadı" metni hangi ayarın
    // eksik olduğunu söylemiyordu (BADE toplu LP baskısı, 2 Eyl 2026).
    if (Regex("""No WMS bridge printer is mapped for .+? label printing""", RegexOption.IGNORE_CASE).containsMatchIn(raw))
        return "Bu cihaz için etiket yazıcısı seçilmemiş. Yazıcılar ekranında etiket (ZPL) yazıcısının 'Etiket' düğmesine basın."
    if (raw.contains("No PDF document printer is selected", ignoreCase = true))
        return "Bu cihaz için belge yazıcısı seçilmemiş. Yazıcılar ekranında PDF yazıcısının 'Belge' düğmesine basın."
    Regex("""(?:Mapped\s+)?printer\s+(\S+?)\s+is not registered""", RegexOption.IGNORE_CASE).find(raw)?.let {
        return "Seçili yazıcı (${it.groupValues[1]}) BC'de kayıtlı değil. Yazıcılar ekranını yenileyip yazıcıyı yeniden seçin."
    }
    Regex("""(?:Mapped\s+)?printer\s+(\S+?)\s+is inactive""", RegexOption.IGNORE_CASE).find(raw)?.let {
        return "Seçili yazıcı (${it.groupValues[1]}) pasif. Yazıcılar ekranından aktif bir yazıcı seçin."
    }
    if (raw.contains("job was saved but Azure dispatch failed", ignoreCase = true))
        return "Baskı işi kaydedildi ama yazıcı ajanına iletilemedi. Windows yazıcı ajanının açık ve bağlı olduğunu kontrol edip Yazıcılar ekranını yenileyin."
    return null
}

/** Raw BC/transport errors never belong on the warehouse terminal. */
fun operatorFacingApiError(raw: String, httpCode: Int = 0): String {
    operatorSafeBcMessage(raw)?.let {
        return "HATA: $it Sorun sürerse yöneticinize ${operatorSupportReference(raw, httpCode)} kodunu iletin."
    }
    operatorKnownBcError(raw)?.let {
        return "HATA: $it Sorun sürerse yöneticinize ${operatorSupportReference(raw, httpCode)} kodunu iletin."
    }
    // BC TestField: "<Alan> must have a value in <Tablo>: No.=X. It cannot be
    // zero or empty." Operatör hangi alanın boş olduğunu görmeli; aksi halde
    // BC'de dolu görünen belge terminalde nedensiz "tamamlanamadı" der.
    val missingField = Regex(
        """^\s*(.+?)\s+must have a value in\s+([^:.]+)""",
        RegexOption.IGNORE_CASE,
    ).find(raw)
    // Count Counter → Local WMS User tablo ilişkisi: operatör bu şirketin WMS
    // kullanıcı listesinde yok. Çözüm veri tarafında; operatör bunu bilmeli.
    val notWmsUser = raw.contains("Local WMS User", ignoreCase = true) ||
        raw.contains("Local WMS Users", ignoreCase = true)
    val action = when {
        notWmsUser -> {
            val who = Regex("""contains a value \((.+?)\)""").find(raw)?.groupValues?.get(1)?.trim().orEmpty()
            "Terminal kullanıcısı${if (who.isNotBlank()) " ($who)" else ""} bu şirketin Local WMS Users listesinde kayıtlı değil. BC'de ekleyin veya kayıtlı bir WMS kullanıcısıyla giriş yapın."
        }
        missingField != null -> {
            val field = operatorFieldCaption(missingField.groupValues[1].trim())
            val table = operatorTableCaption(missingField.groupValues[2].trim())
            "Zorunlu alan boş: $field ($table). Belge bilgilerini tamamlayıp tekrar deneyin."
        }
        raw.contains("lot", ignoreCase = true) ->
            "Lot bilgisi doğrulanamadı. Birden fazla lot veya raf varsa Pick Oluştur ile toplama yapın."
        raw.contains("printer", ignoreCase = true) || raw.contains("yazıcı", ignoreCase = true) ->
            "Yazıcı ayarı tamamlanamadı. Yazıcılar ekranını yenileyin."
        raw.contains("quantity", ignoreCase = true) || raw.contains("miktar", ignoreCase = true) ->
            "Miktar kaydedilemedi. Değeri kontrol edip tekrar deneyin."
        else -> "İşlem tamamlanamadı. Yenileyip tekrar deneyin."
    }
    return "HATA: $action Sorun sürerse yöneticinize ${operatorSupportReference(raw, httpCode)} kodunu iletin."
}

private fun operatorFieldCaption(field: String): String = when (field.lowercase()) {
    "vendor shipment no." -> "Tedarikçi İrsaliye No"
    "posting date" -> "Kayıt Tarihi"
    "vehicle plate no" -> "Araç Plaka No"
    "driver code" -> "Araç Sürücü Kodu"
    "actual receipt datetime" -> "Fiili Alış Tarihi - Saati"
    else -> field
}

private fun operatorTableCaption(table: String): String = when (table.lowercase()) {
    "warehouse receipt header" -> "mal kabul başlığı"
    "warehouse shipment header" -> "sevkiyat başlığı"
    "purchase header" -> "satın alma siparişi"
    "sales header" -> "satış siparişi"
    "transfer header" -> "transfer siparişi"
    else -> table
}

/** Non-clickable state badge. AssistChip is intentionally not used. */
@Composable
fun InfoPill(
    text: String,
    containerColor: Color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
    contentColor: Color = MaterialTheme.colorScheme.primary,
) {
    Surface(shape = RoundedCornerShape(50), color = containerColor) {
        Text(
            text,
            Modifier.padding(horizontal = 9.dp, vertical = 5.dp),
            style = MaterialTheme.typography.labelSmall,
            color = contentColor,
        )
    }
}

/** Reusable document header card. */
@Composable
fun DocHeaderCard(title: String, subtitle: String, badge: String? = null, percent: Int? = null) {
    Card(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(
                    title,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                badge?.let {
                    Spacer(Modifier.width(10.dp))
                    Surface(shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)) {
                        Text(
                            it,
                            Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                            maxLines = 1,
                        )
                    }
                }
            }
            Spacer(Modifier.height(6.dp))
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (percent != null) {
                Spacer(Modifier.height(8.dp))
                LinearProgressIndicator(
                    progress = { (percent.coerceIn(0, 100)) / 100f },
                    modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50)),
                )
                Spacer(Modifier.height(4.dp))
                Text("%$percent tamamlandı", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** Bottom action bar: a row of buttons pinned under content. */
@Composable
fun BottomActionBar(content: @Composable RowScope.() -> Unit) {
    // Yatay ekranda (kısa pencere) aksiyon şeritleri üst üste binince satır
    // listesine yer kalmıyor ve alttaki kaydet düğmesi kırpılıyordu; kısa
    // pencerede dikey boşluk yarıya iner.
    val compact = androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp < 460
    Surface(tonalElevation = 3.dp, shadowElevation = 8.dp) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = if (compact) 4.dp else 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = content
        )
    }
}

/** Yatay/kısa pencerede belge ekranlarındaki büyük düğmelerin yüksekliği. */
@Composable
fun wmsPrimaryButtonHeight(): androidx.compose.ui.unit.Dp =
    if (androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp < 460) 44.dp else 54.dp
