package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

/** Initial assignment is free; a selected terminal cannot be cleared to bypass approval. */
internal fun terminalSelectionAllowed(current: String, next: String, managerProfile: JSONObject?): Boolean =
    next.isNotBlank() && (current.isBlank() || current == next ||
        (managerProfile != null && managerProfile.optBoolean("terminalAdmin", false) &&
            terminalProfileMatches(managerProfile, managerProfile.optString("userId"), next)))

/** Always verify a fresh manager PIN with BC; the displayed user list is not authorization. */
internal suspend fun verifiedTerminalChangeProfile(
    gateway: TerminalLoginGateway, terminal: String, username: String, pin: String,
): JSONObject {
    require(terminal.isNotBlank() && username.isNotBlank() && validTerminalPin(pin)) { "Yönetici ve 4 haneli PIN gereklidir." }
    val response = gateway.login(terminal, username, pin)
        ?: error("Yönetici doğrulanamadı. Bağlantıyı kontrol edip tekrar deneyin.")
    val profile = runCatching { JSONObject(response) }.getOrNull()
        ?: error("Yönetici doğrulanamadı.")
    check(profile.optString("error").isBlank()) { profile.optString("error") }
    check(terminalProfileMatches(profile, username, terminal) && profile.optBoolean("terminalAdmin", false)) {
        "Terminal değiştirmek için Yönetici yetkisi gereklidir."
    }
    return profile
}

@Composable
internal fun TerminalChangeDialog(gateway: TerminalLoginGateway, onDismiss: () -> Unit, onChanged: () -> Unit) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    val original = remember { TerminalSession.code(context) }
    val originalScope = remember { TerminalSession.scope(context) }
    var terminals by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var managers by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var target by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var pin by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf("") }
    var revision by remember { mutableIntStateOf(0) }

    LaunchedEffect(target, revision) {
        busy = true
        error = ""
        managers = emptyList()
        username = ""
        pin = ""
        try {
            if (target.isBlank()) {
                terminals = gateway.terminals()?.filter { it.optString("code") != original && !it.optBoolean("disabled") }
                    ?: error("Terminal listesi alınamadı. Tekrar deneyin.")
            } else {
                managers = gateway.users(target)?.filter { it.optBoolean("terminalAdmin") && !it.optBoolean("disabled") }
                    ?: error("Yönetici listesi alınamadı. Tekrar deneyin.")
                if (managers.size == 1) username = managers.first().optString("username")
            }
        } catch (e: CancellationException) { throw e
        } catch (e: Exception) { error = e.message ?: "Bağlantı kurulamadı."
        } finally { busy = false }
    }

    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text("Terminal değiştir") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Mevcut terminal: $original")
                Text("Değişiklik için Yönetici PIN’i gereklidir. Onaylanana kadar mevcut terminal korunur.")
                if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                if (error.isNotBlank()) Text(error, color = MaterialTheme.colorScheme.error)
                if (target.isBlank()) {
                    Text("Yeni terminali seçin")
                    terminals.forEach { row ->
                        OutlinedButton(onClick = { target = row.optString("code") }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                            Text(row.optString("code"))
                        }
                    }
                    if (!busy && terminals.isEmpty() && error.isBlank()) Text("Başka etkin terminal bulunamadı.")
                } else {
                    Text("Yeni terminal: $target")
                    managers.forEach { manager ->
                        val id = manager.optString("username")
                        OutlinedButton(onClick = { username = id; pin = "" }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                            Text((if (id == username) "✓ " else "") + terminalOperatorLabel(manager))
                        }
                    }
                    if (!busy && managers.isEmpty() && error.isBlank()) Text("Etkin Yönetici bulunamadı. BC’de yönetici tanımlayın.")
                    if (username.isNotBlank()) OutlinedTextField(
                        value = pin,
                        onValueChange = { if (it.length <= 4 && it.all { c -> c in '0'..'9' }) pin = it },
                        label = { Text("Yönetici PIN’i") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                        visualTransformation = PasswordVisualTransformation(), singleLine = true, enabled = !busy,
                    )
                    TextButton(onClick = { target = "" }, enabled = !busy) { Text("Başka terminal seç") }
                }
                if (error.isNotBlank()) TextButton(onClick = { revision++ }, enabled = !busy) { Text("Tekrar dene") }
            }
        },
        confirmButton = {
            TextButton(enabled = !busy && username.isNotBlank() && validTerminalPin(pin), onClick = {
                val submittedPin = pin
                pin = ""
                busy = true
                error = ""
                coroutineScope.launch {
                    try {
                        val profile = verifiedTerminalChangeProfile(gateway, target, username, submittedPin)
                        check(TerminalSession.scope(context) == originalScope && TerminalSession.code(context) == original) {
                            "Bağlantı veya terminal değişti. İşlemi yeniden başlatın."
                        }
                        check(TerminalSession.select(context, target, profile)) { "Terminal değişikliği onaylanmadı." }
                        // Authorization does not sign the manager in as the warehouse operator.
                        onChanged()
                    } catch (e: CancellationException) { throw e
                    } catch (e: Exception) { error = e.message ?: "Terminal değiştirilemedi."
                    } finally { busy = false }
                }
            }) { Text("Onayla ve değiştir") }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("Vazgeç") } },
    )
}
