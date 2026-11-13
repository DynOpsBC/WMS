package com.dynops.bcwms.feature

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
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

internal fun mayCaptureTerminalTenant(flavor: String, configured: Boolean, current: String, incoming: String): Boolean =
    flavor != "bade" || !configured || current.equals(incoming, ignoreCase = true)

internal fun companyChangeProfileApproved(profile: JSONObject?, username: String, terminal: String): Boolean =
    profile != null && terminalProfileMatches(profile, username, terminal) &&
        profile.optBoolean("terminalAdmin", false) && !profile.optBoolean("disabled", false)

/** Fresh server PIN verification for this action only; never replaces the current operator. */
@Composable
internal fun CompanyChangeApproval(
    onApproved: () -> Unit,
    onDismiss: () -> Unit,
    gateway: TerminalLoginGateway? = null,
    terminalOverride: String? = null,
) {
    val context = LocalContext.current
    var terminal by remember { mutableStateOf(terminalOverride ?: TerminalSession.code(context)) }
    val sourceScope = TerminalSession.scope(context)
    val api = remember(gateway) { gateway ?: BcTerminalLoginGateway(context) }
    val scope = rememberCoroutineScope()
    var managers by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var username by remember { mutableStateOf("") }
    var pin by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        try {
            if (terminal.isBlank()) {
                terminal = api.terminals().orEmpty().firstOrNull { !it.optBoolean("disabled", true) }
                    ?.optString("code").orEmpty()
            }
            if (terminal.isBlank()) {
                error = "Yönetici doğrulaması için etkin BC terminali bulunamadı."
                return@LaunchedEffect
            }
            managers = api.users(terminal).orEmpty().filter {
                authorizedTerminalUser(it, it.optString("username"), terminal) && it.optBoolean("terminalAdmin")
            }
            if (managers.size == 1) username = managers.single().optString("username")
            if (managers.isEmpty()) error = "Yönetici listesi alınamadı. BC terminal yöneticisini kontrol edin."
        } catch (e: CancellationException) { throw e }
        catch (_: Exception) { error = "Yönetici listesi alınamadı. Tekrar deneyin." }
        finally { busy = false }
    }
    AlertDialog(onDismissRequest = { if (!busy) onDismiss() },
        title = { Text("Şirket değişikliği · Yönetici onayı") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Devam etmek için yönetici PIN'ini girin.")
                managers.forEach { manager ->
                    Row {
                        RadioButton(username == manager.optString("username"), onClick = {
                            username = manager.optString("username"); pin = ""
                        }, enabled = !busy)
                        Text(terminalOperatorLabel(manager))
                    }
                }
                OutlinedTextField(pin, { if (it.length <= 4 && it.all { c -> c in '0'..'9' }) pin = it },
                    label = { Text("Yönetici PIN") }, singleLine = true, enabled = !busy,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    visualTransformation = PasswordVisualTransformation())
                if (error.isNotBlank()) Text(error, color = MaterialTheme.colorScheme.error)
            }
        },
        confirmButton = {
            TextButton(enabled = !busy && username.isNotBlank() && validTerminalPin(pin), onClick = {
                val submittedUser = username
                val submittedPin = pin
                pin = ""; busy = true; error = ""
                scope.launch {
                    try {
                        val profile = api.login(terminal, submittedUser, submittedPin)?.let { runCatching { JSONObject(it) }.getOrNull() }
                        if (sourceScope == TerminalSession.scope(context) &&
                            companyChangeProfileApproved(profile, submittedUser, terminal)) onApproved()
                        else error = "Yönetici PIN'i doğrulanamadı. Şirket değiştirilmedi."
                    } catch (e: CancellationException) { throw e }
                    catch (_: Exception) { error = "Doğrulama yapılamadı. Şirket değiştirilmedi." }
                    finally { busy = false }
                }
            }) { Text(if (busy) "Doğrulanıyor…" else "Onayla") }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("Vazgeç") } },
    )
}
