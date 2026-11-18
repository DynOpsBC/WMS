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

/**
 * Element4 (18 Kas 2026): Ad-Hoc Hareket'te proje alanı. Proje listeden seçilir
 * (kod elle de yazılabilir); taşıma, hangi proje için yapıldığıyla birlikte BC'deki
 * "Proje Taşıma Kayıtları"na yazılır ve bu ekrandan da görülebilir.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AdHocProjectField(projectCode: String, onChange: (String) -> Unit, enabled: Boolean) {
    var showPicker by remember { mutableStateOf(false) }
    var showMoves by remember { mutableStateOf(false) }
    var projectName by remember { mutableStateOf("") }
    if (projectCode.isBlank()) projectName = ""

    Column(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = projectCode,
                onValueChange = { projectName = ""; onChange(normalizeProjectCode(it)) },
                label = { Text("Proje (isteğe bağlı)") },
                singleLine = true,
                enabled = enabled,
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(8.dp))
            Button(onClick = { showPicker = true }, enabled = enabled, modifier = Modifier.height(52.dp)) { Text("Proje Seç") }
        }
        Text(
            when {
                projectCode.isBlank() -> "Boş bırakılırsa normal taşıma yapılır."
                projectName.isNotBlank() -> "$projectName — taşıma bu proje için kaydedilir."
                else -> "Taşıma $projectCode projesi için kaydedilir."
            },
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 4.dp, top = 2.dp),
        )
        if (projectCode.isNotBlank()) {
            Row {
                TextButton(onClick = { showMoves = true }) { Text("Bu projenin taşımaları", fontSize = 13.sp) }
                TextButton(onClick = { projectName = ""; onChange("") }, enabled = enabled) { Text("Projeyi kaldır", fontSize = 13.sp) }
            }
        }
    }

    if (showPicker) ProjectPickerSheet(
        onDismiss = { showPicker = false },
        onPick = { no, name -> projectName = name; onChange(normalizeProjectCode(no)); showPicker = false },
    )
    if (showMoves) ProjectMovesSheet(projectCode = projectCode, onDismiss = { showMoves = false })
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProjectPickerSheet(onDismiss: () -> Unit, onPick: (no: String, name: String) -> Unit) {
    val context = LocalContext.current
    var projects by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember { mutableStateOf("Projeler yükleniyor...") }
    var search by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        val page = BcApi.getAllPages(context, "wmsProjects?\$top=500&\$orderby=no desc")
        projects = if (page.complete) page.rows else emptyList()
        status = when {
            page.error?.httpCode == 404 -> "HATA: Proje listesi için Business Central güncellemesi gerekli (BCWMS 1.14.4.3)."
            !page.complete -> "HATA: Proje listesi alınamadı. Tekrar deneyin."
            projects.isEmpty() -> "Business Central'da tanımlı proje yok."
            else -> ""
        }
    }
    val shown = projects.filter { projectMatches(it, search) }
    SheetScaffold(onDismiss = onDismiss, contentPadding = PaddingValues(16.dp)) {
        Text("Proje seç", style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(search, { search = it }, label = { Text("Proje no ya da adı ara") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(6.dp))
        StatusText(status)
        LazyColumn(Modifier.heightIn(max = 420.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(shown, key = { it.optString("no") }) { p ->
                Card(onClick = { onPick(p.optString("no"), p.optString("description")) }, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text(p.optString("no"), fontWeight = FontWeight.Bold, fontSize = 16.sp)
                        if (p.optString("description").isNotBlank()) Text(p.optString("description"), fontSize = 14.sp)
                        if (p.optString("billToName").isNotBlank()) Text(p.optString("billToName"), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text("Kapat") }
        Spacer(Modifier.height(8.dp))
    }
}

/** Bir projenin taşıma geçmişi: hangi ürün, ne kadar, nereden nereye, ne zaman, kim. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProjectMovesSheet(projectCode: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var entries by remember(projectCode) { mutableStateOf<List<JSONObject>>(emptyList()) }
    var status by remember(projectCode) { mutableStateOf("Taşımalar yükleniyor...") }
    LaunchedEffect(projectCode) {
        val page = BcApi.getAllPages(
            context,
            "projectMoveEntries?\$top=200&\$orderby=entryNo desc&\$filter=projectNo eq '${projectCode.replace("'", "''")}'",
            maxPages = 2,
        )
        entries = page.rows
        status = when {
            page.error?.httpCode == 404 -> "HATA: Bu liste için Business Central güncellemesi gerekli (BCWMS 1.14.4.3)."
            !page.complete && entries.isEmpty() -> "HATA: Taşımalar alınamadı. Tekrar deneyin."
            entries.isEmpty() -> "Bu proje için henüz taşıma yapılmadı."
            else -> "${entries.size} taşıma" + if (!page.complete) " (son kayıtlar)" else ""
        }
    }
    SheetScaffold(onDismiss = onDismiss, contentPadding = PaddingValues(16.dp)) {
        Text("$projectCode taşımaları", style = MaterialTheme.typography.titleLarge)
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
