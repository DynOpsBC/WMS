package com.dynops.bcwms.feature

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.ui.SheetScaffold
import com.dynops.bcwms.ui.StatusText
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * DKC (24 Kas 2026): üretim çıktısı kutularını palete koyma ve paleti tek
 * seferde yerleştirme. BC tarafı: productionOrderLines.palletizeOutput ve
 * licensePlates.moveToBin (palet LP'si için kutuların yerleştirmelerini kaydeder).
 */
internal fun palletizeOutputPath(orderNo: String, lineNo: Int): String =
    "productionOrderLines(status='Released',prodOrderNo='${orderNo.replace("'", "''")}',lineNo=$lineNo)/Microsoft.NAV.palletizeOutput"

internal fun palletizeOutputBody(templateCode: String, palletLpNo: String): String =
    JSONObject().put("templateCode", templateCode.trim()).put("palletLpNo", palletLpNo.trim()).toString()

internal fun outputLinePath(orderNo: String, lineNo: Int, action: String): String =
    "productionOrderLines(status='Released',prodOrderNo='${orderNo.replace("'", "''")}',lineNo=$lineNo)/Microsoft.NAV.$action"

internal fun palletizeBoxesBody(templateCode: String, palletLpNo: String, boxes: Collection<String>): String =
    JSONObject().put("templateCode", templateCode.trim()).put("palletLpNo", palletLpNo.trim())
        .put("boxLpNos", boxes.joinToString(",")).toString()

/** Palete konabilecek kutu: LP no, raf, miktar, birim, lot. */
internal data class OutputBox(val lpNo: String, val binCode: String, val quantity: Double, val unit: String, val lotNo: String)

/** BC listOutputBoxes sonucu: {"value":"[...]"} ya da doğrudan dizi. */
internal fun parseOutputBoxes(body: String): List<OutputBox>? = runCatching {
    val text = body.trim()
    val raw = if (text.startsWith("[")) text else JSONObject(text).optString("value")
    val arr = org.json.JSONArray(raw)
    (0 until arr.length()).map { i -> arr.getJSONObject(i).let {
        OutputBox(it.optString("lpNo"), it.optString("binCode"), it.optDouble("quantity", 0.0), it.optString("unit"), it.optString("lotNo"))
    } }.filter { it.lpNo.isNotBlank() }
}.getOrNull()

internal fun outputBoxQtyText(q: Double): String =
    if (q == Math.floor(q)) q.toLong().toString() else q.toString().replace('.', ',')

/** Şablonun taşıyıcı adı: kod/açıklamada KUTU → "Kutu", KOLİ → "Koli", PALET → "Palet", ÇUVAL → "Çuval"; yoksa "LP". */
internal fun lpKindWord(code: String, description: String): String {
    val t = "$code $description".uppercase(java.util.Locale.ROOT)
    return when {
        "KUTU" in t || "BOX" in t -> "Kutu"
        "KOLİ" in t || "KOLI" in t -> "Koli"
        "ÇUVAL" in t || "CUVAL" in t -> "Çuval"
        "PALET" in t || "PALLET" in t -> "Palet"
        else -> "LP"
    }
}

/** Palet şablonu varsayılanı: kodunda/açıklamasında PALET/PALLET geçen ilk şablon. */
internal fun defaultPalletTemplate(templates: List<JSONObject>): String =
    templates.firstOrNull { t ->
        listOf(t.optString("code"), t.optString("description")).any { it.contains("PALET", true) || it.contains("PALLET", true) }
    }?.optString("code") ?: templates.firstOrNull()?.optString("code").orEmpty()

internal data class PalletizeResult(val palletLpNo: String, val boxCount: Int, val totalBoxCount: Int, val binCode: String)

/** BC action sonucu: {"value":"{...json...}"} ya da doğrudan JSON metni. */
internal fun parsePalletizeResult(body: String): PalletizeResult? = runCatching {
    val outer = JSONObject(body)
    val inner = outer.optString("value").takeIf { it.trim().startsWith("{") }?.let(::JSONObject) ?: outer
    val no = inner.optString("palletLpNo").trim()
    if (no.isEmpty()) null
    else PalletizeResult(no, inner.optInt("boxCount"), inner.optInt("totalBoxCount", inner.optInt("boxCount")), inner.optString("binCode"))
}.getOrNull()

/** Okutulan değer LP/bin barkodu olabilir; GS1/ön ekli biçimler sade koda indirgenir. */
internal fun scannedCode(raw: String): String =
    BarcodeIntentResolver.resolve(raw).value.trim().ifBlank { raw.trim() }.uppercase()

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun OutputPalletSheet(
    orderNo: String,
    lineNo: Int,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var templates by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var templateCode by remember { mutableStateOf("") }
    var existingMode by remember { mutableStateOf(false) }
    var palletScan by remember { mutableStateOf("") }
    var printLabel by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var boxes by remember { mutableStateOf<List<OutputBox>>(emptyList()) }
    var selected by remember { mutableStateOf<Set<String>>(emptySet()) }
    var boxesLoaded by remember { mutableStateOf(false) }

    suspend fun loadBoxes() {
        val r = BcApi.post(context, outputLinePath(orderNo, lineNo, "listOutputBoxes"), "{}")
        val list = if (r.ok) parseOutputBoxes(r.body) else null
        if (list == null) { status = "HATA: Kutular okunamadı. ${if (r.ok) "" else BcApi.errorMessage(r.body)}".trim(); return }
        // En son oluşturulan kutu en üstte. Hiçbiri seçili gelmez: operatör palete
        // koyacaklarını işaretler (ya da "Tümü").
        boxes = list.sortedByDescending { it.lpNo }
        selected = emptySet()
        boxesLoaded = true
        if (list.isEmpty()) status = "Palete konacak kutu yok. Önce LP'ye dokunup kutuları oluşturun."
    }

    LaunchedEffect(Unit) {
        loadBoxes()
        val page = BcApi.getAllPages(context, "licensePlateTemplates?\$top=50&\$select=code,description")
        if (page.complete) {
            val sorted = page.rows.sortedBy { it.optString("code") }
            templateCode = defaultPalletTemplate(sorted)
            // Seçili palet şablonu kaydırmadan görünsün.
            templates = sorted.sortedBy { if (it.optString("code") == templateCode) 0 else 1 }
        }
    }

    fun run() {
        if (busy || done) return
        val pallet = if (existingMode) scannedCode(palletScan) else ""
        if (existingMode && pallet.isEmpty()) { status = "HATA: Palet LP etiketini okutun."; return }
        if (!existingMode && templateCode.isBlank()) { status = "HATA: BC'de LP şablonu tanımlı değil."; return }
        if (selected.isEmpty()) { status = "HATA: Palete konacak en az bir kutu seçin."; return }
        val chosen = boxes.map { it.lpNo }.filter { it in selected }
        scope.launch {
            busy = true
            status = "${chosen.size} kutu palete konuyor..."
            val r = BcApi.post(context, outputLinePath(orderNo, lineNo, "palletizeOutputBoxes"), palletizeBoxesBody(templateCode, pallet, chosen))
            val result = if (r.ok) parsePalletizeResult(r.body) else null
            if (result == null) {
                busy = false
                status = "HATA: ${if (r.ok) "BC sonucu okunamadı" else BcApi.errorMessage(r.body)}"
                return@launch
            }
            var printed = true
            if (printLabel) {
                status = "Palet etiketi basılıyor..."
                printed = BcApi.boundAction(context, "licensePlates", result.palletLpNo, "printLabel",
                    JSONObject().put("printerId", getMtePrinter(context)).put("copies", 0).toString()).ok
            }
            busy = false
            done = true
            status = "TAMAM: ${result.boxCount} kutu ${result.palletLpNo} paletine kondu" +
                (if (result.totalBoxCount != result.boxCount) " (palette toplam ${result.totalBoxCount} kutu)" else "") +
                ". Paleti Yerleştirme > Palet Yerleştir ile tek seferde rafa koyun." +
                when { !printLabel -> ""; printed -> " Palet etiketi basıldı."; else -> " Palet etiketi gönderilemedi; LP ekranından yazdırın." }
        }
    }

    SheetScaffold(onDismiss = { if (!busy) onDismiss() }, contentPadding = PaddingValues(20.dp)) {
        Text("Kutuları Palete Koy", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text("$orderNo emri için oluşturduğunuz kutu LP'leri. Palete koyacaklarınızı işaretleyin.",
            fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        if (boxes.isNotEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Kutular · ${selected.size}/${boxes.size} seçili", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                TextButton(onClick = { selected = if (selected.size == boxes.size) emptySet() else boxes.map { it.lpNo }.toSet() },
                    enabled = !busy && !done) { Text(if (selected.size == boxes.size) "Hiçbiri" else "Tümü") }
            }
            Column(Modifier.heightIn(max = 280.dp).verticalScroll(rememberScrollState())) {
                boxes.forEach { b ->
                    val on = b.lpNo in selected
                    Row(Modifier.fillMaxWidth().clickable(enabled = !busy && !done) {
                            selected = if (on) selected - b.lpNo else selected + b.lpNo
                        }.padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = on, onCheckedChange = { selected = if (it) selected + b.lpNo else selected - b.lpNo }, enabled = !busy && !done)
                        Column(Modifier.weight(1f)) {
                            Text(b.lpNo, fontWeight = FontWeight.Bold)
                            Text(listOf("${outputBoxQtyText(b.quantity)} ${b.unit}".trim(), b.lotNo.takeIf { it.isNotBlank() }?.let { "Lot $it" }, b.binCode)
                                .filterNotNull().filter { it.isNotBlank() }.joinToString(" · "), fontSize = 12.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        } else if (!boxesLoaded) {
            Text("Kutular yükleniyor...", fontSize = 12.sp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = !existingMode, onClick = { existingMode = false }, enabled = !busy && !done, label = { Text("Yeni palet") })
            FilterChip(selected = existingMode, onClick = { existingMode = true }, enabled = !busy && !done, label = { Text("Mevcut palete ekle") })
        }
        Spacer(Modifier.height(8.dp))
        if (existingMode) {
            OutlinedTextField(palletScan, { palletScan = it.take(40) }, label = { Text("Palet LP etiketini okutun") },
                enabled = !busy && !done, singleLine = true, modifier = Modifier.fillMaxWidth())
        } else if (templates.size > 1) {
            Text("Palet şablonu", fontSize = 12.sp)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                templates.forEach { t ->
                    val code = t.optString("code")
                    FilterChip(selected = code == templateCode, onClick = { templateCode = code }, enabled = !busy && !done,
                        label = { Text(t.optString("description").ifBlank { code }) })
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(checked = printLabel, onCheckedChange = { printLabel = it }, enabled = !busy && !done)
            Text("Palet etiketi bas")
        }
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        if (!done) Button(onClick = { run() }, enabled = !busy && selected.isNotEmpty(), modifier = Modifier.fillMaxWidth().height(48.dp)) {
            Text((if (existingMode) "Palete Ekle" else "Palete Koy") + if (selected.isNotEmpty()) " · ${selected.size} kutu" else "")
        }
        TextButton(onClick = onDismiss, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(if (done) "Kapat" else "Vazgeç") }
    }
}

/**
 * Paleti yerleştir: palet LP'si ve hedef raf okutulur; BC kutuların tüm açık
 * yerleştirmelerini o rafa kaydeder. Önerilen raf ilk kutunun yerleştirme
 * satırındaki "Koy" rafıdır.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PalletPutAwaySheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var palletScan by remember { mutableStateOf("") }
    var pallet by remember { mutableStateOf("") }
    var boxCount by remember { mutableStateOf(0) }
    var suggestedBin by remember { mutableStateOf("") }
    var binScan by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }

    fun checkPallet() {
        val no = scannedCode(palletScan)
        if (no.isEmpty() || busy) return
        scope.launch {
            busy = true
            status = "Palet kontrol ediliyor..."
            val safe = no.replace("'", "''")
            val kids = BcApi.getAllPages(context, "licensePlates?\$filter=parentLpNo eq '$safe'&\$select=no,binCode,status")
            busy = false
            if (!kids.complete) { status = "HATA: Palet okunamadı. Yeniden deneyin."; return@launch }
            if (kids.rows.isEmpty()) { pallet = ""; status = "HATA: $no LP'sinde kutu yok. Önce Üretim Çıktısı > Palete Koy ile kutuları bağlayın."; return@launch }
            pallet = no
            boxCount = kids.rows.size
            val first = kids.rows.first().optString("no").replace("'", "''")
            val pl = BcApi.get(context, "putAwayLines?\$filter=lpNo eq '$first' and actionType eq 'Place'&\$select=binCode&\$top=1")
            suggestedBin = if (pl.ok) BcApi.parseValueArray(pl.body).firstOrNull()?.optString("binCode").orEmpty() else ""
            if (binScan.isBlank() && suggestedBin.isNotBlank()) binScan = suggestedBin
            status = "$no paletinde $boxCount kutu var." + if (suggestedBin.isNotBlank()) " Önerilen raf: $suggestedBin" else ""
        }
    }

    fun run() {
        if (busy || done) return
        val bin = scannedCode(binScan)
        if (pallet.isEmpty()) { status = "HATA: Önce palet LP etiketini okutun."; return }
        if (bin.isEmpty()) { status = "HATA: Hedef rafı okutun."; return }
        scope.launch {
            busy = true
            status = "$boxCount kutu $bin rafına yerleştiriliyor..."
            val userId = BcApi.currentUserId(context).trim()
            val r = BcApi.boundActionLongRunning(context, "licensePlates", pallet, "moveToBin",
                JSONObject().put("targetBinCode", bin).put("userId", userId).toString())
            busy = false
            if (r.ok) { done = true; status = "TAMAM: $pallet paleti ve $boxCount kutu $bin rafına yerleştirildi." }
            else status = "HATA: ${BcApi.errorMessage(r.body)}"
        }
    }

    SheetScaffold(onDismiss = { if (!busy) onDismiss() }, contentPadding = PaddingValues(20.dp)) {
        Text("Palet Yerleştir", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text("Paletin üzerindeki tüm kutuların yerleştirmeleri tek seferde kaydedilir.",
            fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(10.dp))
        OutlinedTextField(palletScan, { palletScan = it.take(40); if (pallet.isNotEmpty() && scannedCode(it) != pallet) pallet = "" },
            label = { Text("Palet LP etiketini okutun") }, enabled = !busy && !done, singleLine = true,
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
            keyboardActions = androidx.compose.foundation.text.KeyboardActions(onDone = { checkPallet() }),
            modifier = Modifier.fillMaxWidth())
        if (pallet.isEmpty()) TextButton(onClick = { checkPallet() }, enabled = !busy && palletScan.isNotBlank()) { Text("Paleti Kontrol Et") }
        if (pallet.isNotEmpty()) {
            OutlinedTextField(binScan, { binScan = it.take(40) }, label = { Text("Hedef rafı okutun") },
                enabled = !busy && !done, singleLine = true, modifier = Modifier.fillMaxWidth())
        }
        StatusText(status)
        Spacer(Modifier.height(8.dp))
        if (!done && pallet.isNotEmpty()) Button(onClick = { run() }, enabled = !busy, modifier = Modifier.fillMaxWidth().height(48.dp)) {
            Text("Paleti Yerleştir")
        }
        TextButton(onClick = onDismiss, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(if (done) "Kapat" else "Vazgeç") }
    }
}
