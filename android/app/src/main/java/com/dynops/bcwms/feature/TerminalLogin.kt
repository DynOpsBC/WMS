package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.dynops.bcwms.BcApi
import kotlinx.coroutines.launch
import org.json.JSONObject

internal fun validTerminalPin(value: String): Boolean = value.length == 4 && value.all { it in '0'..'9' }
internal fun terminalPreferenceScope(tenant: String, environment: String, company: String): String =
    listOf(tenant, environment, company).joinToString(":") { "${it.length}:$it" }

internal fun terminalLoginPath(code: String): String {
    val escaped = java.net.URLEncoder.encode(code.replace("'", "''"), "UTF-8").replace("+", "%20")
    return "wmsTerminals('$escaped')/Microsoft.NAV.login"
}

internal fun terminalProfileMatches(profile: JSONObject, username: String, terminal: String): Boolean =
    profile.optString("error").isBlank() && profile.optString("userId") == username &&
        username.isNotBlank() && terminal.isNotBlank() && profile.optString("terminalCode") == terminal

internal fun terminalPrintRequestIssue(body: String?): String? {
    val json = body?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null
    if (json.has("printLabels") && !json.optBoolean("printLabels")) return null
    return if (json.has("printerId") && json.optString("printerId").isBlank())
        "Bu terminal için yazıcı seçilmemiş. BC terminal kartında yazıcı seçin ve yeniden giriş yapın."
    else null
}

internal fun terminalUsersPath(terminal: String): String {
    val escaped = java.net.URLEncoder.encode(terminal.replace("'", "''"), "UTF-8").replace("+", "%20")
    return "localUsers?\$filter=(terminalCode eq '$escaped' or terminalAdmin eq true) and disabled eq false"
}

internal fun authorizedTerminalUser(user: JSONObject, username: String, terminal: String): Boolean =
    username.isNotBlank() && terminal.isNotBlank() && user.optString("username") == username &&
        !user.optBoolean("disabled", true) &&
        (user.optString("terminalCode") == terminal || user.optBoolean("terminalAdmin", false))

internal fun terminalOperatorLabel(user: JSONObject): String =
    user.optString("displayName").ifBlank { user.optString("username") } +
        if (user.optBoolean("terminalAdmin")) " · Yönetici" else ""

internal const val TERMINAL_SESSION_MS = 30 * 60 * 1000L
internal fun terminalSessionFresh(verifiedAt: Long, now: Long): Boolean =
    verifiedAt > 0 && now >= verifiedAt && now - verifiedAt < TERMINAL_SESSION_MS

internal fun terminalSessionRequestAllowed(method: String, path: String, authenticated: Boolean): Boolean =
    authenticated || method == "GET" || method == "HEAD" ||
        (method == "POST" && ((path.startsWith("wmsTerminals('") && path.endsWith("/Microsoft.NAV.login")) ||
            path == "appUserProfiles('DEFAULT')/Microsoft.NAV.resolveCurrent"))

internal object TerminalSession {
    private fun prefs(context: Context) = context.getSharedPreferences("bcwms_prefs", Context.MODE_PRIVATE)
    fun scope(context: Context) = terminalPreferenceScope(
        BcApi.getTenant(context), BcApi.getEnvironment(context), BcApi.getCompanyId(context),
    )
    private fun key(context: Context) = "wms_terminal." + scope(context)
    fun code(context: Context): String = prefs(context).getString(key(context), "").orEmpty()
    fun select(context: Context, code: String) {
        signOut(context)
        prefs(context).edit().putString(key(context), code).apply()
    }
    fun signOut(context: Context) { BcApi.clearLocalUser(context) }

    /** Reopening preserves only the remaining PIN session; it never extends the deadline. */
    suspend fun resume(context: Context): Boolean {
        if (!authenticated(context)) return false
        val terminal = code(context)
        val username = BcApi.getLocalUser(context)
        val terminals = BcApi.getAllPages(context, "wmsTerminals?\$filter=disabled eq false")
        if (!terminals.complete) return false
        val terminalRow = terminals.rows.firstOrNull { it.optString("code") == terminal }
        if (terminalRow == null) { signOut(context); return false }
        val users = BcApi.getAllPages(context, terminalUsersPath(terminal))
        if (!users.complete) return false
        val user = users.rows.firstOrNull { authorizedTerminalUser(it, username, terminal) }
        if (user == null) { signOut(context); return false }
        val profile = JSONObject(BcApi.getLocalProfileJson(context))
            .put("displayName", user.optString("displayName"))
            .put("terminalAdmin", user.optBoolean("terminalAdmin"))
        BcApi.saveLocalUser(context, username, profile.toString())
        setDefaultPrinter(context, terminalRow.optString("labelPrinterCode"), PRINTER_USAGE_LABEL)
        setDefaultPrinter(context, terminalRow.optString("documentPrinterCode"), PRINTER_USAGE_DOCUMENT)
        return true
    }
    // Identity remains readable under the lock for in-flight document refreshes.
    // Warehouse writes still require authenticated(), including its PIN deadline.
    fun hasSelectedIdentity(context: Context): Boolean = runCatching {
        val profile = JSONObject(BcApi.getLocalProfileJson(context))
        code(context).isNotBlank() && BcApi.hasLocalUser(context) &&
            profile.optString("terminalCode") == code(context) && profile.optString("terminalScope") == scope(context)
    }.getOrDefault(false)

    fun authenticated(context: Context): Boolean = runCatching {
        val profile = JSONObject(BcApi.getLocalProfileJson(context))
        hasSelectedIdentity(context) && terminalSessionFresh(profile.optLong("pinVerifiedAt"), System.currentTimeMillis()) &&
            terminalSessionFresh(profile.optLong("pinVerifiedElapsed"), android.os.SystemClock.elapsedRealtime())
    }.getOrDefault(false)
}

internal interface TerminalLoginGateway {
    suspend fun terminals(): List<JSONObject>?
    suspend fun users(terminal: String): List<JSONObject>?
    suspend fun login(terminal: String, username: String, pin: String): String?
}

private class BcTerminalLoginGateway(private val context: Context) : TerminalLoginGateway {
    override suspend fun terminals(): List<JSONObject>? =
        BcApi.getAllPages(context, "wmsTerminals?\$filter=disabled eq false").let { if (it.complete) it.rows else null }
    override suspend fun users(terminal: String): List<JSONObject>? =
        BcApi.getAllPages(context, terminalUsersPath(terminal)).let { if (it.complete) it.rows else null }
    override suspend fun login(terminal: String, username: String, pin: String): String? {
        val response = BcApi.post(context, terminalLoginPath(terminal),
            JSONObject().put("username", username).put("pin", pin).toString())
        return if (response.ok) BcApi.scalarValue(response.body) else null
    }
}

/** Terminal selection is retained on this device; a handover only clears the employee. */
@Composable
internal fun TerminalOperatorLogin(onConnected: (Boolean) -> Unit, onConnectionSettings: () -> Unit, gateway: TerminalLoginGateway? = null) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val api = remember(context, gateway) { gateway ?: BcTerminalLoginGateway(context) }
    var terminal by remember { mutableStateOf(TerminalSession.code(context)) }
    var terminals by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var users by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var selectedUser by remember { mutableStateOf<JSONObject?>(null) }
    var pin by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    var revision by remember { mutableIntStateOf(0) }
    var loaded by remember { mutableStateOf(false) }

    LaunchedEffect(terminal, revision) {
        busy = true
        loaded = false
        error = ""
        users = emptyList()
        selectedUser = null
        pin = ""
        try {
            val terminalPage = api.terminals()
            if (terminalPage == null) {
                error = "Terminal listesi alınamadı. Bağlantıyı ve BC güncellemesini kontrol edin."
                return@LaunchedEffect
            }
            terminals = terminalPage
            if (terminal.isBlank()) {
                loaded = true
                return@LaunchedEffect
            }
            if (terminals.none { it.optString("code") == terminal }) {
                BcApi.clearLocalUser(context)
                error = "Bu terminal etkin değil. Başka terminal seçin."
                return@LaunchedEffect
            }
            val page = api.users(terminal)
            if (page == null) {
                error = "Kullanıcılar alınamadı. Tekrar deneyin."
                return@LaunchedEffect
            }
            users = page.sortedBy { it.optString("displayName") }
            loaded = true
        } finally { busy = false }
    }

    androidx.activity.compose.BackHandler(enabled = selectedUser != null) {
        if (!busy) { selectedUser = null; pin = ""; error = "" }
    }

    Column(Modifier.fillMaxSize().imePadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(if (terminal.isBlank()) "Terminal seçin" else terminal, style = MaterialTheme.typography.headlineSmall)
        if (terminal.isNotBlank()) Text("Kullanıcınızı seçip PIN girin.")
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (error.isNotBlank()) Text(error, color = MaterialTheme.colorScheme.error)
        if (selectedUser == null) {
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (terminal.isBlank()) {
                    items(terminals, key = { it.optString("code") }) { row ->
                        FilledTonalButton(onClick = {
                            terminal = row.optString("code")
                            TerminalSession.select(context, terminal)
                        }, enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) {
                            Text(row.optString("code"))
                        }
                    }
                    if (loaded && terminals.isEmpty()) item { Text("BC’de önce terminal oluşturun.") }
                } else {
                    items(users, key = { it.optString("username") }) { row ->
                        FilledTonalButton(onClick = { selectedUser = row; pin = ""; error = "" },
                            enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) {
                            Text(terminalOperatorLabel(row))
                        }
                    }
                    if (loaded && users.isEmpty()) item { Text("Bu terminale BC’den kullanıcı ekleyin.") }
                }
            }
        } else {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(terminalOperatorLabel(selectedUser!!), style = MaterialTheme.typography.titleLarge)
            OutlinedTextField(
                value = pin,
                onValueChange = { value -> if (value.length <= 4 && value.all { it in '0'..'9' }) pin = value },
                label = { Text("4 haneli PIN") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            )
            Button(onClick = {
                val username = selectedUser!!.optString("username")
                val submittedPin = pin
                pin = ""
                busy = true
                error = ""
                scope.launch {
                    try {
                        val profileText = api.login(terminal, username, submittedPin)
                        if (profileText == null) {
                            error = "Giriş yapılamadı. Bağlantıyı kontrol edip tekrar deneyin."
                            return@launch
                        }
                        val profile = runCatching { JSONObject(profileText) }.getOrNull()
                        if (profile == null || profile.optString("error").isNotBlank()) {
                            error = profile?.optString("error").orEmpty().ifBlank { "Giriş doğrulanamadı." }
                            return@launch
                        }
                        if (!terminalProfileMatches(profile, username, terminal)) {
                            error = "Kullanıcı doğrulanamadı."
                            return@launch
                        }
                        BcApi.saveLocalUser(context, username, profile.put("terminalScope", TerminalSession.scope(context))
                            .put("pinVerifiedAt", System.currentTimeMillis())
                            .put("pinVerifiedElapsed", android.os.SystemClock.elapsedRealtime()).toString())
                        setDefaultPrinter(context, profile.optString("labelPrinterCode"), PRINTER_USAGE_LABEL)
                        setDefaultPrinter(context, profile.optString("documentPrinterCode"), PRINTER_USAGE_DOCUMENT)
                        onConnected(true)
                    } finally { busy = false }
                }
            }, enabled = !busy && validTerminalPin(pin), modifier = Modifier.fillMaxWidth().height(52.dp)) {
                Text("Giriş yap")
            }
            TextButton(onClick = { selectedUser = null; pin = ""; error = "" }, enabled = !busy) { Text("Başka kullanıcı seç") }
            }
        }
        if (selectedUser == null) TextButton(onClick = { revision++ }, enabled = !busy) { Text("Yenile") }
        if (terminal.isNotBlank()) TextButton(onClick = {
            TerminalSession.select(context, "")
            terminal = ""
        }, enabled = !busy) { Text("Terminal değiştir") }
        TextButton(onClick = onConnectionSettings, enabled = !busy) { Text("Bağlantı ayarları") }
    }
}

/** Display over the existing content so remembered document/quantity/step state stays mounted. */
@Composable
internal fun TerminalReauthenticationDialog(
    previousOperator: String,
    onVerified: (operatorChanged: Boolean) -> Unit,
    onConnectionSettings: () -> Unit,
    gateway: TerminalLoginGateway? = null,
) {
    val context = LocalContext.current
    androidx.compose.ui.window.Dialog(onDismissRequest = {}, properties = androidx.compose.ui.window.DialogProperties(
        dismissOnBackPress = false, dismissOnClickOutside = false, usePlatformDefaultWidth = false,
    )) {
        Surface(Modifier.fillMaxSize()) {
            Column {
                Text("30 dakika doldu. Kullanıcınızı seçip PIN girin.", modifier = Modifier.padding(16.dp),
                    style = MaterialTheme.typography.titleMedium)
                TerminalOperatorLogin(onConnected = { ok ->
                    if (ok) onVerified(previousOperator != BcApi.getLocalUser(context))
                }, onConnectionSettings = onConnectionSettings, gateway = gateway)
            }
        }
    }
}
