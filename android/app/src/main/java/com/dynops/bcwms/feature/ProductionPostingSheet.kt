package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.ui.SheetScaffold
import com.dynops.bcwms.ui.StatusText
import com.dynops.bcwms.ui.normalizeQtyInput
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.time.LocalDate
import java.util.UUID

private class ProductionDraftStore(context: Context, orderNo: String, lineNo: Int) {
    private val prefs = context.getSharedPreferences("production_output_pending_v1", Context.MODE_PRIVATE)
    private val key = listOf(BcApi.getTenant(context).lowercase(), BcApi.getEnvironment(context).lowercase(),
        BcApi.getCompanyId(context).lowercase(), orderNo, lineNo.toString()).joinToString("|")
    fun read(): String? = prefs.getString(key, null)
    fun save(draft: ProductionOutputDraft): Boolean = prefs.edit().putString(key, draft.toJson()).commit()
    fun clear(): Boolean = prefs.edit().remove(key).commit()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ProductionPostingSheet(
    line: JSONObject,
    onDismiss: () -> Unit,
    onPosted: () -> Unit,
    onPrint: (OutputLot) -> Unit,
    /** Doluysa yeni çıktı açılmaz: önceki çıktının sarfiyatı bekleniyor. */
    newOutputBlockedReason: String? = null,
    /** Çekilen malzemenin yettiği en çok çıktı; null = sınır yok. */
    outputCapByPicked: Double? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { ProductionDraftStore(context, line.optString("prodOrderNo"), line.optInt("lineNo")) }
    val saved = remember { runCatching { store.read() } }
    val restored = remember { saved.getOrNull()?.let(::productionOutputDraftFromJson)?.takeIf { productionDraftMatchesLine(it, line) } }
    var blocked by remember { mutableStateOf(saved.isFailure || (saved.getOrNull() != null && restored == null)) }
    var draft by remember { mutableStateOf(restored) }
    var quantity by remember { mutableStateOf("") }
    var postingDate by remember { mutableStateOf(line.optString("workDate").takeIf { productionIsoDate(it) != null } ?: LocalDate.now().toString()) }
    var expirationDate by remember { mutableStateOf("") }
    var bin by remember { mutableStateOf(line.optString("binCode")) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf(if (blocked) "HATA: Önceki bildirim okunamadı. Yeni bildirim oluşturmadan sistem yöneticinize bildirin." else "") }
    var confirmPost by remember { mutableStateOf(false) }
    val current = draft
    val result = current?.result?.takeIf { it.isNotBlank() }?.let { validatedProductionOutputResult(current, it) }
    val posted = current?.phase == "posted"
    val remaining = line.optDouble("remainingQuantity", 0.0)
    val unit = line.optString("unitOfMeasureCode")

    fun persist(value: ProductionOutputDraft): Boolean {
        if (!runCatching { store.save(value) }.getOrDefault(false)) {
            blocked = true
            status = "HATA: Bildirim cihazda saklanamadı. Yeni işlem başlatmadan bağlantıyı ve cihaz depolamasını kontrol edin."
            return false
        }
        draft = value
        return true
    }

    fun send(action: String) {
        if (busy || blocked) return
        val existing = draft ?: return
        val phase = when (action) { "prepare" -> "prepare"; "postOutput" -> "posting"; else -> if (existing.phase in setOf("prepare", "cancel_prepare")) "cancel_prepare" else "cancel" }
        val pending = existing.copy(phase = phase)
        if (!persist(pending)) return
        busy = true
        scope.launch {
            try {
                status = when (action) { "prepare" -> "BC bildirimi hazırlıyor ve lot atıyor…"; "postOutput" -> "Çıktı deftere naklediliyor…"; else -> "Bildirim kontrol ediliyor…" }
                val response = BcApi.post(context,
                    if (action == "prepare") productionPreparePath(pending) else productionRequestPath(pending, action),
                    if (action == "prepare") pending.body else "{}")
                if (!response.ok && action == "cancelOutput" && phase == "cancel_prepare" && response.httpCode == 404) {
                    if (store.clear()) { draft = null; status = "Hazırlık iptal edildi. Miktarı düzenleyebilirsiniz." }
                    else { blocked = true; status = "HATA: Cihazdaki hazırlık kapatılamadı." }
                    return@launch
                }
                if (!response.ok) {
                    status = "HATA: ${BcApi.errorMessage(response.body)} Aynı bildirimi yeniden kontrol edin; yeni bildirim açmayın."
                    return@launch
                }
                val text = BcApi.scalarValue(response.body)
                val answer = validatedProductionOutputResult(pending, text)
                if (answer == null) {
                    status = "HATA: BC yanıtı doğrulanamadı. Aynı bildirimi yeniden kontrol edin."
                    return@launch
                }
                if (answer.getBoolean("cancelled")) {
                    if (store.clear()) { draft = null; status = "Bildirim iptal edildi. Miktarı düzenleyebilirsiniz." }
                    else { blocked = true; status = "HATA: İptal sonucu cihazda saklanamadı." }
                } else {
                    val complete = answer.getBoolean("completed")
                    if (persist(pending.copy(phase = if (complete) "posted" else "prepared", result = text))) {
                        status = if (complete) "TAMAM: ${receiptLabelQtyText(answer.getDouble("quantity"), unit)} deftere nakledildi. Etiketi basabilirsiniz."
                            else "Bildirim hazır. ${answer.optString("lotNo").takeIf { it.isNotBlank() }?.let { "BC lotu: $it." }.orEmpty()} Henüz deftere nakledilmedi."
                        if (complete) onPosted()
                    }
                }
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                status = "HATA: Bildirim sonucu alınamadı. Aynı bildirim cihazda saklandı; yeniden kontrol edin."
            } finally { busy = false }
        }
    }

    SheetScaffold(onDismiss = { if (!busy) onDismiss() }) {
        Text("Üretim Çıktısı Bildir", style = MaterialTheme.typography.titleLarge)
        Text("${line.optString("prodOrderNo")} · ${line.optString("itemNo")}")
        Text("Kalan: ${receiptLabelQtyText(remaining, unit)}")
        Spacer(Modifier.height(8.dp))
        StatusText(status)
        if (current == null && !line.optString("status").equals("Released", true)) {
            Text("Yeni çıktı yalnız serbest bırakılmış üretim emrine bildirilebilir.")
        } else if (current == null && newOutputBlockedReason != null) {
            Text(newOutputBlockedReason, color = MaterialTheme.colorScheme.error, fontWeight = FontWeight.Bold)
        } else if (current == null) {
            outputCapByPicked?.let { Text("Çekilen malzeme en çok ${receiptLabelQtyText(it, unit)} üretmeye yeter.", fontWeight = FontWeight.SemiBold) }
            OutlinedTextField(quantity, { quantity = normalizeQtyInput(it) }, label = { Text("Bu bildirimin miktarı ($unit)") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), enabled = !busy && !blocked, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(postingDate, { postingDate = it }, label = { Text("Kayıt tarihi (YYYY-AA-GG)") }, enabled = !busy && !blocked, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(bin, { bin = it.take(20) }, label = { Text("Çıktı gözü") }, enabled = !busy && !blocked, modifier = Modifier.fillMaxWidth())
            if (line.optBoolean("expirationRequired")) {
                OutlinedTextField(expirationDate, { expirationDate = it }, label = { Text("Son kullanma tarihi (YYYY-AA-GG)") },
                    enabled = !busy && !blocked, modifier = Modifier.fillMaxWidth())
            }
            Button(enabled = !busy && !blocked && !line.optBoolean("serialRequired"), modifier = Modifier.fillMaxWidth(), onClick = {
                val qty = quantity.toDoubleOrNull()
                val error = productionReportQuantityError(qty, remaining)
                    ?: if (qty != null && outputCapByPicked != null && qty > outputCapByPicked + 0.000001)
                        "Çekilen malzeme en çok ${receiptLabelQtyText(outputCapByPicked, unit)} üretmeye yeter. Önce toplama yapın." else null
                val date = productionIsoDate(postingDate)
                val expiry = productionIsoDate(expirationDate, optional = !line.optBoolean("expirationRequired"))
                if (error != null || date == null || expiry == null) {
                    status = "HATA: ${error ?: "Tarihleri YYYY-AA-GG biçiminde girin."}"
                    return@Button
                }
                val id = UUID.randomUUID().toString()
                val body = JSONObject().put("quantity", qty).put("postingDate", date).put("expirationDate", expiry)
                    .put("binCode", bin.trim()).put("requestId", id).toString()
                if (persist(ProductionOutputDraft(id, line.optString("prodOrderNo"), line.optInt("lineNo"), line.optString("itemNo"), body))) send("prepare")
            }) { Text(if (line.optBoolean("lotRequired")) "Lot Ata — BC'den Otomatik" else "Bildirimi Hazırla") }
            if (line.optBoolean("serialRequired")) Text("Seri takipli ürün için BC ürün izleme ekranını kullanın.")
        } else {
            val body = JSONObject(current.body)
            Text("Bildirilen: ${receiptLabelQtyText(body.getDouble("quantity"), unit)}", fontWeight = FontWeight.Bold)
            Text("Kayıt tarihi: ${productionDateText(body.getString("postingDate"))}")
            result?.let {
                Text("Lot: ${it.optString("lotNo").ifBlank { "Lotsuz" }}")
                if (posted) Text("Madde hareketi: ${it.optInt("entryNo")} · Belge: ${it.optString("documentNo")}")
            }
            when (current.phase) {
                "prepare" -> Button(onClick = { send("prepare") }, enabled = !busy && !blocked, modifier = Modifier.fillMaxWidth()) { Text("Aynı Bildirimi Yeniden Hazırla") }
                "prepared" -> Button(onClick = { confirmPost = true }, enabled = !busy && !blocked, modifier = Modifier.fillMaxWidth()) { Text("Deftere Naklet") }
                "posting" -> Button(onClick = { send("postOutput") }, enabled = !busy && !blocked, modifier = Modifier.fillMaxWidth()) { Text("Aynı Bildirimin Kaydını Tamamla") }
                "cancel", "cancel_prepare" -> Button(onClick = { send("cancelOutput") }, enabled = !busy && !blocked, modifier = Modifier.fillMaxWidth()) { Text("İptal Sonucunu Kontrol Et") }
                "posted" -> {
                    Button(enabled = !busy && !blocked && result != null, modifier = Modifier.fillMaxWidth(), onClick = {
                        result?.let { onPrint(OutputLot(it.getString("lotNo"), it.getDouble("quantityBase"), it.getString("baseUnitOfMeasure"), it.getString("postingDate"))) }
                    }) { Text("Bu Çıktının Etiketini Bas") }
                    // Önce üret, sonra tüket: çıktıdan sonra emir ekranındaki Sarfiyat
                    // bölümü ne kadar tüketilebileceğini gösterir.
                    OutlinedButton(enabled = !busy && !blocked, modifier = Modifier.fillMaxWidth(), onClick = {
                        if (store.clear()) { onDismiss() } else { blocked = true; status = "HATA: Cihazdaki bildirim kapatılamadı." }
                    }) { Text("Sarfiyata Geç") }
                    Text("Bildirim kapanır; emir ekranında bu çıktı için ne kadar bileşen tüketebileceğiniz görünür.", style = MaterialTheme.typography.bodySmall)
                }
            }
            if (current.phase in setOf("prepare", "prepared", "posting")) TextButton(enabled = !busy && !blocked, onClick = { send("cancelOutput") }) { Text("Bildirimi İptal Et / Miktarı Değiştir") }
        }
        TextButton(onClick = onDismiss, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Kapat") }
        Spacer(Modifier.height(12.dp))
    }
    if (confirmPost) AlertDialog(onDismissRequest = { confirmPost = false }, title = { Text("Üretim çıktısı deftere nakledilsin mi?") },
        text = { Text("${current?.let { receiptLabelQtyText(JSONObject(it.body).getDouble("quantity"), unit) }.orEmpty()} stok kaydı oluşturulacak. Üretim emri kalan miktar için açık kalacak.") },
        confirmButton = { TextButton(onClick = { confirmPost = false; send("postOutput") }) { Text("Deftere Naklet") } },
        dismissButton = { TextButton(onClick = { confirmPost = false }) { Text("Vazgeç") } })
}
