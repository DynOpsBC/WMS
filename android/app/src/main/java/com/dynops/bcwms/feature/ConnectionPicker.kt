package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.dynops.bcwms.BcApi

/** Selection is a draft. Only the explicit Connect action may change the saved connection. */
@Composable
internal fun ConnectionPicker(
    environments: List<BcApi.EnvCompanies>,
    currentEnvironment: String,
    currentCompanyId: String,
    currentCompanyName: String,
    busy: Boolean,
    onRefresh: () -> Unit,
    onFind: (String) -> Unit,
    onConnect: (BcApi.EnvCompanies, BcApi.Company) -> Unit,
    onCancel: () -> Unit,
) {
    var selectedEnvironment by remember { mutableStateOf(currentEnvironment) }
    var selectedCompanyId by remember(selectedEnvironment) {
        mutableStateOf(if (selectedEnvironment.equals(currentEnvironment, true)) currentCompanyId else "")
    }
    var showSearch by remember { mutableStateOf(false) }
    var search by remember { mutableStateOf("") }
    val environment = environments.firstOrNull { it.environment.equals(selectedEnvironment, true) }
    val company = environment?.companies?.firstOrNull { it.id == selectedCompanyId }

    OutlinedCard(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Mevcut bağlantı", style = MaterialTheme.typography.labelMedium)
            Text(currentEnvironment, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(currentCompanyName.ifBlank { "Şirket seçilmedi" }, style = MaterialTheme.typography.bodyMedium)
        }
    }
    Spacer(Modifier.height(16.dp))
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text("1. Ortamı seç", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold,
            modifier = Modifier.weight(1f))
        TextButton(onClick = onRefresh, enabled = !busy) { Text("Yenile") }
    }
    if (busy) {
        LinearProgressIndicator(Modifier.fillMaxWidth())
        Text("Bağlantı kontrol ediliyor…", style = MaterialTheme.typography.bodySmall)
    }
    environments.forEach { option ->
        val selected = option.environment.equals(selectedEnvironment, true)
        OutlinedCard(
            onClick = { selectedEnvironment = option.environment }, enabled = !busy,
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp), shape = RoundedCornerShape(14.dp),
            colors = CardDefaults.outlinedCardColors(containerColor = if (selected)
                MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface),
        ) {
            Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                RadioButton(selected = selected, onClick = null)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(option.environment, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(if (option.environment.equals("Production", true)) "Canlı ortam" else "Test ortamı",
                        style = MaterialTheme.typography.bodySmall)
                }
                if (option.environment.equals(currentEnvironment, true)) Text("Mevcut", style = MaterialTheme.typography.labelSmall)
            }
        }
    }
    if (!busy && environments.isEmpty()) {
        Text("Ortam bulunamadı. Yenileyin veya ortam adını girin.", Modifier.padding(vertical = 12.dp))
    }
    TextButton(onClick = { showSearch = !showSearch }, enabled = !busy) {
        Text(if (showSearch) "Aramayı kapat" else "Başka ortam ekle")
    }
    if (showSearch) {
        OutlinedTextField(search, { search = it }, label = { Text("Ortam adı") }, singleLine = true,
            enabled = !busy, modifier = Modifier.fillMaxWidth())
        OutlinedButton(onClick = { onFind(search.trim()) }, enabled = !busy && search.isNotBlank(),
            modifier = Modifier.fillMaxWidth()) { Text("Ortamı bul") }
    }
    Spacer(Modifier.height(12.dp))
    Text("2. Şirketi seç", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
    if (environment == null) {
        Text("Şirketleri görmek için bir ortam seçin.", Modifier.padding(vertical = 12.dp),
            style = MaterialTheme.typography.bodyMedium)
    }
    environment?.companies?.forEach { option ->
        val selected = company?.id == option.id
        OutlinedCard(
            onClick = { selectedCompanyId = option.id }, enabled = !busy,
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp), shape = RoundedCornerShape(14.dp),
            colors = CardDefaults.outlinedCardColors(containerColor = if (selected)
                MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface),
        ) {
            Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                RadioButton(selected = selected, onClick = null)
                Spacer(Modifier.width(10.dp))
                Text(option.displayName, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            }
        }
    }
    Spacer(Modifier.height(16.dp))
    if (environment != null && company != null) {
        Text("${environment.environment} · ${company.displayName}", style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.height(6.dp))
    }
    Button(
        onClick = { if (environment != null && company != null) onConnect(environment, company) },
        enabled = !busy && environment != null && company != null,
        modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp),
    ) { Text(if (busy) "Kontrol ediliyor…" else "Seçilen şirkete bağlan") }
    TextButton(onClick = onCancel, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Vazgeç") }
}

/** Verification runs against the target; a failed probe must leave the active connection intact. */
internal suspend fun verifyConnectionChange(
    verify: suspend () -> BcApi.ApiResult,
    save: () -> Unit,
): BcApi.ApiResult {
    val result = verify()
    if (result.ok) save()
    return result
}
