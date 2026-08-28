package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.scanner.ScanField
import com.dynops.bcwms.ui.StatusText
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** EMU / DKÇ'ye özel ürün LP -> kutu -> palet hiyerarşi ekranı. */
private enum class HierarchicalLpOperation(val label: String, val hint: String) {
    Create("LP Oluştur", "Ürün, kutu veya palet"),
    Attach("Birbirine Bağla", "Ürün → kutu, kutu → palet"),
    Detach("Bağlantıyı Kaldır", "Yanlış bağlanan LP'yi çıkar"),
    Contents("İçeriği Gör", "Paletin bütün ağacını göster"),
    Move("Tamamını Taşı", "Palet ve altlarını tek işlemde taşı"),
    Print("Etiket Yazdır", "Ürün, kutu veya palet etiketi"),
}

private enum class DkcLpKind(val label: String, val templateCode: String) {
    Item("Ürün", "DKC-ITEM"),
    Box("Kutu", "DKC-BOX"),
    Pallet("Palet", "DKC-PALLET"),
}

@Composable
fun HierarchicalLpModule() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var operation by remember { mutableStateOf(HierarchicalLpOperation.Create) }
    var busy by remember { mutableStateOf(false) }
    var enabled by remember { mutableStateOf(false) }
    var templatesReady by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Business Central ayarları kontrol ediliyor...") }

    fun checkSetup() {
        scope.launch {
            busy = true
            val setup = BcApi.get(context, "movementOps('')?\$select=hierarchicalLpEnabled")
            enabled = setup.ok && runCatching {
                JSONObject(setup.body).optBoolean("hierarchicalLpEnabled") ||
                    BcApi.parseValueArray(setup.body).firstOrNull()?.optBoolean("hierarchicalLpEnabled") == true
            }.getOrDefault(false)
            val templates = if (enabled) {
                BcApi.getAllPages(
                    context,
                    "licensePlateTemplates?\$filter=code eq 'DKC-ITEM' or code eq 'DKC-BOX' or code eq 'DKC-PALLET'&\$select=code&\$top=10",
                )
            } else null
            templatesReady = templates?.complete == true &&
                templates.rows.map { it.optString("code") }.toSet()
                    .containsAll(DkcLpKind.entries.map { it.templateCode })
            status = when {
                !setup.ok -> "HATA: Güncel DKC Business Central uzantısına ulaşılamadı."
                !enabled -> "HATA: Bu BC şirketinde Hiyerarşik LP kapalı. Advanced WMS Setup ekranından açın."
                !templatesReady -> "HATA: DKC şablonları eksik. BC Setup ekranında DKC LP şablonlarını oluşturun."
                else -> "TAMAM: Ürün → kutu → palet akışı hazır."
            }
            busy = false
        }
    }

    LaunchedEffect(Unit) { checkSetup() }

    Column(Modifier.fillMaxSize().padding(12.dp)) {
        Text("DKC Kutu ve Palet", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Text("Her adım barkod okutarak ilerler.", style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.height(8.dp))
        OutlinedButton(onClick = { checkSetup() }, enabled = !busy) {
            Text(if (busy) "Kontrol ediliyor..." else "Ayarları Kontrol Et")
        }
        StatusText(status)
        if (!enabled || !templatesReady) return@Column

        Spacer(Modifier.height(8.dp))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(HierarchicalLpOperation.entries) { item ->
                FilterChip(
                    selected = operation == item,
                    onClick = { operation = item; status = item.hint },
                    label = { Text(item.label) },
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        when (operation) {
            HierarchicalLpOperation.Create -> CreateDkcLpForm(busy, { busy = it }, { status = it })
            HierarchicalLpOperation.Attach -> LinkDkcLpForm(false, busy, { busy = it }, { status = it })
            HierarchicalLpOperation.Detach -> LinkDkcLpForm(true, busy, { busy = it }, { status = it })
            HierarchicalLpOperation.Contents -> HierarchyContentsForm(busy, { busy = it }, { status = it })
            HierarchicalLpOperation.Move -> MoveHierarchyForm(busy, { busy = it }, { status = it })
            HierarchicalLpOperation.Print -> PrintHierarchyForm(busy, { busy = it }, { status = it })
        }
    }
}

@Composable
private fun CreateDkcLpForm(busy: Boolean, onBusy: (Boolean) -> Unit, onStatus: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var kind by remember { mutableStateOf(DkcLpKind.Item) }
    var location by remember { mutableStateOf("") }
    var bin by remember { mutableStateOf("") }

    FormCard("Yeni DKC LP") {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DkcLpKind.entries.forEach { option ->
                FilterChip(selected = kind == option, onClick = { kind = option }, label = { Text(option.label) })
            }
        }
        ScanField("Lokasyon", location, { location = it }, Modifier.fillMaxWidth())
        ScanField("Bin", bin, { bin = it }, Modifier.fillMaxWidth())
        Button(
            enabled = !busy && location.isNotBlank() && bin.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
            onClick = {
                scope.launch {
                    onBusy(true)
                    val body = JSONObject().apply {
                        put("locationCode", location.trim())
                        put("binCode", bin.trim())
                    }.toString()
                    val result = BcApi.boundAction(context, "licensePlateTemplates", kind.templateCode, "build", body)
                    onBusy(false)
                    onStatus(if (result.ok) "TAMAM: ${kind.label} LP ${BcApi.scalarValue(result.body)} oluşturuldu."
                        else "HATA: ${BcApi.errorMessage(result.body)}")
                }
            },
        ) { Text(if (busy) "Oluşturuluyor..." else "${kind.label} LP Oluştur") }
    }
}

@Composable
private fun LinkDkcLpForm(detach: Boolean, busy: Boolean, onBusy: (Boolean) -> Unit, onStatus: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var parent by remember { mutableStateOf("") }
    var child by remember { mutableStateOf("") }
    FormCard(if (detach) "LP Bağlantısını Kaldır" else "LP'leri Birbirine Bağla") {
        ScanField("Ana LP (Kutu / Palet)", parent, { parent = it }, Modifier.fillMaxWidth())
        ScanField("Alt LP (Ürün / Kutu)", child, { child = it }, Modifier.fillMaxWidth())
        Button(
            enabled = !busy && parent.isNotBlank() && child.isNotBlank() && parent.trim() != child.trim(),
            modifier = Modifier.fillMaxWidth(),
            onClick = {
                scope.launch {
                    onBusy(true)
                    val action = if (detach) "detachChild" else "attachChild"
                    val result = BcApi.boundAction(
                        context, "licensePlates", parent.trim(), action,
                        JSONObject().put("childLpNo", child.trim()).toString(),
                    )
                    onBusy(false)
                    onStatus(if (result.ok) {
                        val verb = if (detach) "bağlantıdan çıkarıldı" else "${parent.trim()} içine bağlandı"
                        "TAMAM: ${child.trim()} $verb."
                    } else "HATA: ${BcApi.errorMessage(result.body)}")
                    if (result.ok) child = ""
                }
            },
        ) { Text(if (busy) "İşleniyor..." else if (detach) "Bağlantıyı Kaldır" else "Bağla") }
    }
}

@Composable
private fun HierarchyContentsForm(busy: Boolean, onBusy: (Boolean) -> Unit, onStatus: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rootLp by remember { mutableStateOf("") }
    var hierarchy by remember { mutableStateOf<JSONObject?>(null) }
    FormCard("Kutu / Palet İçeriği") {
        ScanField("Kök LP (tercihen palet)", rootLp, { rootLp = it; hierarchy = null }, Modifier.fillMaxWidth())
        Button(
            enabled = !busy && rootLp.isNotBlank(), modifier = Modifier.fillMaxWidth(),
            onClick = {
                scope.launch {
                    onBusy(true)
                    val result = BcApi.boundAction(context, "licensePlates", rootLp.trim(), "getHierarchy")
                    hierarchy = if (result.ok) parseHierarchy(result.body) else null
                    onBusy(false)
                    onStatus(if (hierarchy != null) "TAMAM: Hiyerarşi yüklendi." else "HATA: ${BcApi.errorMessage(result.body)}")
                }
            },
        ) { Text(if (busy) "Yükleniyor..." else "İçeriği Getir") }
        hierarchy?.let { HierarchyNode(it) }
    }
}

@Composable
private fun MoveHierarchyForm(busy: Boolean, onBusy: (Boolean) -> Unit, onStatus: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var rootLp by remember { mutableStateOf("") }
    var targetBin by remember { mutableStateOf("") }
    FormCard("Hiyerarşiyi Tek İşlemde Taşı") {
        Text("Yalnız kök paleti/kutuyu okutun; bütün alt LP'ler birlikte taşınır.", style = MaterialTheme.typography.bodySmall)
        ScanField("Kök LP", rootLp, { rootLp = it }, Modifier.fillMaxWidth())
        ScanField("Hedef Bin", targetBin, { targetBin = it }, Modifier.fillMaxWidth())
        Button(
            enabled = !busy && rootLp.isNotBlank() && targetBin.isNotBlank(), modifier = Modifier.fillMaxWidth(),
            onClick = {
                scope.launch {
                    onBusy(true)
                    val userId = BcApi.currentUserId(context).trim()
                    if (userId.isBlank()) {
                        onBusy(false); onStatus("HATA: Kullanıcı kimliği bulunamadı. Yeniden giriş yapın.")
                        return@launch
                    }
                    val body = JSONObject().put("targetBinCode", targetBin.trim()).put("userId", userId).toString()
                    val result = BcApi.boundAction(context, "licensePlates", rootLp.trim(), "moveHierarchy", body)
                    onBusy(false)
                    onStatus(if (result.ok) "TAMAM: ${rootLp.trim()} ve bütün alt LP'leri ${targetBin.trim()} binine taşındı."
                        else "HATA: ${BcApi.errorMessage(result.body)}")
                }
            },
        ) { Text(if (busy) "Taşınıyor..." else "Hiyerarşiyi Taşı") }
    }
}

@Composable
private fun PrintHierarchyForm(busy: Boolean, onBusy: (Boolean) -> Unit, onStatus: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var lpNo by remember { mutableStateOf("") }
    var reprintReason by remember { mutableStateOf("") }
    FormCard("Hiyerarşi Etiketi") {
        ScanField("LP", lpNo, { lpNo = it }, Modifier.fillMaxWidth())
        OutlinedTextField(
            value = reprintReason,
            onValueChange = { reprintReason = it },
            label = { Text("Tekrar basım nedeni (opsiyonel)") },
            modifier = Modifier.fillMaxWidth(), singleLine = true,
        )
        Button(
            enabled = !busy && lpNo.isNotBlank(), modifier = Modifier.fillMaxWidth(),
            onClick = {
                scope.launch {
                    onBusy(true)
                    val action = if (reprintReason.isBlank()) "completeAndPrint" else "reprintHierarchyLabel"
                    val body = JSONObject().apply {
                        put("printerId", getDefaultPrinter(context))
                        put("labelProfile", "")
                        put("copies", 1)
                        if (reprintReason.isNotBlank()) put("reason", reprintReason.trim())
                    }.toString()
                    val result = BcApi.boundAction(context, "licensePlates", lpNo.trim(), action, body)
                    onBusy(false)
                    onStatus(if (result.ok) "TAMAM: ${lpNo.trim()} etiketi yazıcı kuyruğuna gönderildi."
                        else "HATA: ${BcApi.errorMessage(result.body)}")
                }
            },
        ) { Text(if (busy) "Gönderiliyor..." else if (reprintReason.isBlank()) "Tamamla ve Yazdır" else "Tekrar Yazdır") }
    }
}

@Composable
private fun FormCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 17.sp)
            content()
        }
    }
}

private fun parseHierarchy(body: String): JSONObject? = runCatching {
    val scalar = BcApi.scalarValue(body)
    JSONObject(scalar.ifBlank { body })
}.getOrNull()

@Composable
private fun HierarchyNode(node: JSONObject, depth: Int = 0) {
    val no = node.optString("no").ifBlank { node.optString("lpNo") }
    val kind = node.optString("templateCode")
    Text("${"  ".repeat(depth)}${if (depth == 0) "Palet" else "Alt LP"}: $no${if (kind.isBlank()) "" else " · $kind"}")
    val children = node.optJSONArray("children") ?: JSONArray()
    for (index in 0 until children.length()) {
        children.optJSONObject(index)?.let { HierarchyNode(it, depth + 1) }
    }
}
