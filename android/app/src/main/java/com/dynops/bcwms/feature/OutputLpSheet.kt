package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.ui.SheetScaffold
import com.dynops.bcwms.ui.StatusText
import com.dynops.bcwms.ui.normalizeQtyInput
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Üretim çıktısını LP'ye koy: yeni LP (çıktı gözünde, istenirse eşit bölünmüş
 * birden çok LP) ya da mevcut bir LP (okutulan palet). Hiçbir adım kendiliğinden
 * tekrarlanmaz; yarıda kalırsa oluşan LP'ler mesajda yazılır.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun OutputLpSheet(
    itemNo: String,
    lotNo: String,
    quantity: Double,
    unit: String,
    locationCode: String,
    outputBin: String,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var existingMode by remember { mutableStateOf(false) }
    var qtyText by remember { mutableStateOf(consumptionQtyInput(quantity)) }
    var countText by remember { mutableStateOf("1") }
    var targetLp by remember { mutableStateOf("") }
    var templates by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var templateCode by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    // Her oluşan/eklenen LP'nin şablon etiketi (BC tasarımı) basılır.
    var printPallet by remember { mutableStateOf(true) }

    suspend fun printLp(no: String): Boolean {
        val r = BcApi.boundAction(context, "licensePlates", no, "printLabel",
            JSONObject().put("printerId", getMtePrinter(context)).put("copies", 0).toString())
        return r.ok
    }

    LaunchedEffect(Unit) {
        val page = BcApi.getAllPages(context, "licensePlateTemplates?\$top=50&\$select=code,description")
        if (page.complete) {
            val sorted = page.rows.sortedBy { it.optString("code") }
            // Üretim çıktısı önce kutuya konur: KUTU şablonu varsayılan ve ilk sırada.
            templateCode = (sorted.firstOrNull { lpKindWord(it.optString("code"), it.optString("description")) == "Kutu" } ?: sorted.firstOrNull())
                ?.optString("code").orEmpty()
            templates = sorted.sortedBy { if (it.optString("code") == templateCode) 0 else 1 }
        }
    }

    // Etiket ve mesajlarda taşıyıcının adı: seçili şablon kutuysa "Kutu", paletse "Palet".
    val kind = if (existingMode) "LP" else templates.firstOrNull { it.optString("code") == templateCode }
        ?.let { lpKindWord(it.optString("code"), it.optString("description")) } ?: "LP"
    fun run() {
        if (busy || done) return
        val qty = qtyText.replace(',', '.').toDoubleOrNull()
        if (qty == null || qty <= 0.0) { status = "HATA: Miktarı girin."; return }
        if (qty > quantity + 0.00001) { status = "HATA: Çıkan miktardan (${receiptLabelQtyText(quantity, unit)}) fazlası konamaz."; return }
        if (outputBin.isBlank()) { status = "HATA: Çıktı gözü tanımlı değil; LP'ye konamaz."; return }
        scope.launch {
            busy = true
            val userId = BcApi.currentUserId(context).trim()
            if (existingMode) {
                val scanned = targetLp.trim()
                if (scanned.isEmpty()) { busy = false; status = "HATA: LP etiketini okutun."; return@launch }
                status = "LP kontrol ediliyor..."
                val r = BcApi.get(context, "licensePlates?\$filter=no eq '${scanned.replace("'", "''")}'&\$select=no,locationCode,binCode,status&\$top=1")
                if (!r.ok) { busy = false; status = "HATA: LP okunamadı (HTTP ${r.httpCode})."; return@launch }
                val lp = BcApi.parseValueArray(r.body).firstOrNull()
                outputTargetLpProblem(lp, scanned, locationCode)?.let { busy = false; status = "HATA: $it"; return@launch }
                val lpNo = lp!!.optString("no")
                status = "Ürün LP'ye ekleniyor..."
                val add = BcApi.boundAction(context, "licensePlates", lpNo, "addLineFromBin",
                    outputLpLineBody(itemNo, unit, qty, lotNo, outputBin, userId))
                busy = false
                if (add.ok) {
                    done = true
                    val printed = if (printPallet) printLp(lpNo) else true
                    status = "TAMAM: ${receiptLabelQtyText(qty, unit)} $lpNo LP'sine kondu" +
                        lp.optString("binCode").takeIf { it.isNotBlank() && !it.equals(outputBin, true) }?.let { " ve stok $it rafına taşındı" }.orEmpty() +
                        when { !printPallet -> "."; printed -> ", etiket basıldı."; else -> ". Etiket gönderilemedi; LP ekranından yazdırın." }
                } else status = "HATA: ${BcApi.errorMessage(add.body)} (HTTP ${add.httpCode})"
                return@launch
            }
            val count = countText.toIntOrNull() ?: 0
            val parts = splitOutputQuantity(qty, count)
            if (count !in 1..50 || parts.isEmpty()) { busy = false; status = "HATA: LP sayısı 1–50 arası olmalı ve miktar bölünebilmeli."; return@launch }
            if (templateCode.isBlank()) { busy = false; status = "HATA: BC'de LP şablonu tanımlı değil."; return@launch }
            val created = mutableListOf<String>()
            for ((index, part) in parts.withIndex()) {
                status = "LP ${index + 1}/${parts.size} oluşturuluyor..."
                val body = emptyLpRequestBody(templateCode, EmptyLpBin.Found(outputBin, locationCode))
                val r = BcApi.post(context, "licensePlates", body)
                val no = if (r.ok) createdLpNo(r.body) else ""
                if (no.isBlank()) {
                    busy = false
                    status = "HATA: LP oluşturulamadı: ${if (r.ok) "numara okunamadı" else BcApi.errorMessage(r.body)}." +
                        if (created.isNotEmpty()) " Oluşanlar: ${created.joinToString()}. Yeniden denemeden LP listesini kontrol edin." else ""
                    return@launch
                }
                val add = BcApi.boundAction(context, "licensePlates", no, "addLineFromBin",
                    outputLpLineBody(itemNo, unit, part, lotNo, outputBin, userId))
                if (!add.ok) {
                    busy = false
                    status = "HATA: $no LP'sine ürün eklenemedi: ${BcApi.errorMessage(add.body)}." +
                        " Oluşanlar: ${(created + no).joinToString()} ($no boş). Yeniden denemeden LP listesini kontrol edin."
                    return@launch
                }
                created += no
            }
            val notPrinted = if (printPallet) created.filterNot { status = "$kind etiketi basılıyor: $it"; printLp(it) } else emptyList()
            busy = false
            done = true
            status = "TAMAM: ${created.size} ${kind.lowercase()} LP oluşturuldu: ${created.joinToString()}." + when {
                !printPallet -> " Etiket için LP ekranından yazdırın."
                notPrinted.isEmpty() -> " $kind etiketleri basıldı."
                else -> " Etiketi gönderilemeyen LP: ${notPrinted.joinToString()} — LP ekranından yazdırın."
            }
        }
    }

    SheetScaffold(onDismiss = { if (!busy) onDismiss() }, contentPadding = PaddingValues(20.dp)) {
        Text("Çıktıyı LP'ye Koy", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text("$itemNo · Lot ${lotNo.ifBlank { "yok" }} · Çıkan ${receiptLabelQtyText(quantity, unit)} · Göz $outputBin",
            fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = !existingMode, onClick = { existingMode = false }, enabled = !busy && !done, label = { Text("Yeni LP") })
            FilterChip(selected = existingMode, onClick = { existingMode = true }, enabled = !busy && !done, label = { Text("Mevcut LP'ye koy") })
        }
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(qtyText, { qtyText = normalizeQtyInput(it) }, label = { Text("Konacak miktar ($unit)") },
            enabled = !busy && !done, singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.fillMaxWidth())
        if (existingMode) {
            OutlinedTextField(targetLp, { targetLp = it.trim().uppercase().take(20) }, label = { Text("LP etiketini okutun") },
                enabled = !busy && !done, singleLine = true, modifier = Modifier.fillMaxWidth())
            Text("LP başka bir raftaysa ürün o rafa taşınır.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            OutlinedTextField(countText, { countText = it.filter(Char::isDigit).take(2) }, label = { Text(if (kind == "LP") "Kaç LP'ye bölünsün" else "Kaç ${kind.lowercase()}ya bölünsün") },
                enabled = !busy && !done, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
            val preview = splitOutputQuantity(qtyText.replace(',', '.').toDoubleOrNull() ?: 0.0, countText.toIntOrNull() ?: 0)
            if (preview.size > 1) Text("${if (kind == "LP") "LP" else kind} başına: ${receiptLabelQtyText(preview.first(), unit)}" +
                if (preview.last() != preview.first()) " (sonuncu ${receiptLabelQtyText(preview.last(), unit)})" else "",
                fontSize = 12.sp)
            if (templates.size > 1) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                templates.forEach { t ->
                    val code = t.optString("code")
                    FilterChip(selected = code == templateCode, onClick = { templateCode = code }, enabled = !busy && !done,
                        label = { Text(t.optString("description").ifBlank { code }) })
                }
            }
        }
        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Checkbox(checked = printPallet, onCheckedChange = { printPallet = it }, enabled = !busy && !done)
            Text("$kind etiketi bas")
        }
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        if (!done) Button(onClick = { run() }, enabled = !busy, modifier = Modifier.fillMaxWidth().height(48.dp)) {
            Text(if (existingMode) "LP'ye Ekle" else if (kind == "LP") "LP Oluştur" else "$kind LP Oluştur")
        }
        TextButton(onClick = onDismiss, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(if (done) "Kapat" else "Vazgeç") }
    }
}
