package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.ui.SheetScaffold
import com.dynops.bcwms.ui.StatusText
import org.json.JSONObject

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AdHocReferenceField(
    referenceCode: String,
    onChange: (String) -> Unit,
    enabled: Boolean,
    useSalesOrder: Boolean,
) {
    val selectLabel = if (useSalesOrder) "Sipariş Seç" else "Proje Seç"
    var showPicker by remember { mutableStateOf(false) }
    var showMoves by remember { mutableStateOf(false) }
    var referenceName by remember { mutableStateOf("") }
    if (referenceCode.isBlank()) referenceName = ""

    Column(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = referenceCode,
                onValueChange = { referenceName = ""; onChange(normalizeProjectCode(it)) },
                label = { Text(if (useSalesOrder) "Satış Sipariş No" else "Proje (isteğe bağlı)") },
                singleLine = true,
                enabled = enabled,
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(8.dp))
            Button(onClick = { showPicker = true }, enabled = enabled, modifier = Modifier.height(52.dp)) { Text(selectLabel) }
        }
        Text(
            when {
                referenceCode.isBlank() -> "Boş bırakılırsa normal taşıma yapılır."
                referenceName.isNotBlank() -> referenceName
                useSalesOrder -> "Taşıma $referenceCode siparişine bağlanır."
                else -> "Taşıma $referenceCode projesi için kaydedilir."
            },
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 4.dp, top = 2.dp),
        )
        if (referenceCode.isNotBlank()) {
            Row {
                TextButton(onClick = { showMoves = true }) { Text(if (useSalesOrder) "Siparişin taşımaları" else "Bu projenin taşımaları", fontSize = 13.sp) }
                TextButton(onClick = { referenceName = ""; onChange("") }, enabled = enabled) { Text(if (useSalesOrder) "Siparişi kaldır" else "Projeyi kaldır", fontSize = 13.sp) }
            }
        }
    }

    if (showPicker) ReferencePickerSheet(
        useSalesOrder = useSalesOrder,
        title = selectLabel,
        onDismiss = { showPicker = false },
        onPick = { no, name -> referenceName = name; onChange(normalizeProjectCode(no)); showPicker = false },
    )
    if (showMoves) ReferenceMovesSheet(referenceCode, useSalesOrder, onDismiss = { showMoves = false })
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReferencePickerSheet(
    useSalesOrder: Boolean,
    title: String,
    onDismiss: () -> Unit,
    onPick: (no: String, name: String) -> Unit,
) {
    val context = LocalContext.current
    var references by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("Liste yükleniyor...") }
    var search by remember { mutableStateOf("") }
    LaunchedEffect(useSalesOrder) {
        val path = if (useSalesOrder)
            "salesSources?\$filter=startswith(no,'E4')&\$select=no,customerName&\$orderby=no desc"
        else
            "wmsProjects?\$top=500&\$orderby=no desc"
        val page = BcApi.getAllPages(context, path)
        references = if (page.complete) page.rows else emptyList()
        status = when {
            page.error?.httpCode == 404 -> "HATA: Liste için Business Central güncellemesi gerekli."
            !page.complete -> "HATA: Liste alınamadı. Tekrar deneyin."
            references.isEmpty() && useSalesOrder -> "Bağlı Business Central şirketinde E4 ile başlayan satış siparişi bulunamadı."
            references.isEmpty() -> "Business Central'da tanımlı proje yok."
            else -> ""
        }
    }
    val shown = references.filter { projectMatches(it, search) }
    SheetScaffold(onDismiss = onDismiss, contentPadding = PaddingValues(16.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(search, { search = it }, label = { Text(if (useSalesOrder) "Sipariş no ya da müşteri ara" else "Proje no ya da adı ara") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        if (status.isBlank() && shown.isEmpty())
            Text("Aramayla eşleşen kayıt yok.", fontSize = 13.sp)
        LazyColumn(Modifier.heightIn(max = 420.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(shown, key = { it.optString("no") }) { p ->
                val name = p.optString(if (useSalesOrder) "customerName" else "description")
                Card(onClick = { onPick(p.optString("no"), name) }, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text(p.optString("no"), fontWeight = FontWeight.Bold, fontSize = 16.sp)
                        if (name.isNotBlank()) Text(name, fontSize = 14.sp)
                        if (p.optString("billToName").isNotBlank()) Text(p.optString("billToName"), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text("Kapat") }
        Spacer(Modifier.height(8.dp))
    }
}

/** Siparişe ya da projeye bağlı taşıma geçmişi. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReferenceMovesSheet(referenceCode: String, useSalesOrder: Boolean, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var entries by remember(referenceCode) { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember(referenceCode) { mutableStateOf("Taşımalar yükleniyor...") }
    LaunchedEffect(referenceCode, useSalesOrder) {
        val filterField = if (useSalesOrder) "salesOrderNo" else "projectNo"
        val filter = java.net.URLEncoder.encode("$filterField eq '${referenceCode.replace("'", "''")}'", "UTF-8")
            .replace("+", "%20")
        val page = BcApi.getAllPages(
            context,
            "projectMoveEntries?\$top=200&\$orderby=entryNo desc&\$filter=$filter",
            maxPages = 2,
        )
        entries = page.rows
        status = when {
            page.error?.httpCode == 404 || (useSalesOrder && page.error?.httpCode == 400) -> "HATA: Taşıma geçmişi için Business Central sürümünü kontrol edin."
            !page.complete && entries.isEmpty() -> "HATA: Taşımalar alınamadı. Tekrar deneyin."
            entries.isEmpty() -> "Henüz taşıma kaydı yok."
            else -> if (!page.complete || entries.size >= 200) "Son ${entries.size} taşıma" else "${entries.size} taşıma"
        }
    }
    SheetScaffold(onDismiss = onDismiss, contentPadding = PaddingValues(16.dp)) {
        Text("$referenceCode taşımaları", style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        LazyColumn(Modifier.heightIn(max = 460.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(entries, key = { it.optInt("entryNo") }) { e ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text(e.optString("itemNo"), fontWeight = FontWeight.Bold, fontSize = 15.sp)
                        if (e.optString("itemDescription").isNotBlank()) Text(e.optString("itemDescription"), fontSize = 13.sp, maxLines = 1)
                        Text(projectMoveSummary(e), fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                        Text(
                            listOf(projectMoveTimeText(e.optString("movedAt")), e.optString("userName").ifBlank { e.optString("userId") }, e.optString("lpNo").takeIf { it.isNotBlank() }?.let { "LP $it" })
                                .filter { !it.isNullOrBlank() }.joinToString(" · "),
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
        TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text("Kapat") }
        Spacer(Modifier.height(8.dp))
    }
}
