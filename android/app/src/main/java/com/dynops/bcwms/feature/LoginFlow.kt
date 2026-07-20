package com.dynops.bcwms.feature

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.DeviceAuth
import com.dynops.bcwms.ui.StatusText
import kotlinx.coroutines.launch
import org.json.JSONObject

private enum class Step { Email, DeviceCode, SelectEnvCompany, LocalUser }

/**
 * Email-based sign-in: email → device-code (browser) → environment + company selection → connect.
 * No token paste required. Token-paste remains available as an "advanced" fallback.
 */
@Composable
fun LoginFlow(onConnected: (Boolean) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // Paylaşımlı BC lisansı modeli: BC servis hesabı + ortam zaten bağlıysa
    // ekran doğrudan WMS operatör girişinden başlar (vardiya/kullanıcı değişimi
    // de "Bağlı" rozetine dokunup buradan yapılır).
    var step by remember { mutableStateOf(if (BcApi.hasToken(context)) Step.LocalUser else Step.Email) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var localUsername by remember { mutableStateOf("") }
    var localPassword by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var showAdvanced by remember { mutableStateOf(false) }

    var deviceCode by remember { mutableStateOf<DeviceAuth.DeviceCode?>(null) }
    var envList by remember { mutableStateOf<List<BcApi.EnvCompanies>>(emptyList()) }
    var selectedEnv by remember { mutableStateOf<BcApi.EnvCompanies?>(null) }
    var manualEnv by remember { mutableStateOf("") }
    var lastToken by remember { mutableStateOf("") }

    /**
     * Direct username/password sign-in via AAD ROPC. Bypasses browser; works for cloud-only
     * accounts without MFA / Conditional Access blocks. On success: flows into the same
     * env+company selector as the browser path.
     */
    fun startPasswordSignIn() {
        scope.launch {
            busy = true; status = "BC'ye bağlanılıyor..."
            when (val t = DeviceAuth.loginWithPassword(email.trim(), password)) {
                is DeviceAuth.TokenResult.Success -> {
                    BcApi.saveToken(context, t.accessToken)
                    BcApi.saveRefreshToken(context, t.refreshToken)
                    BcApi.saveTokenExpiry(context, t.expiresInSec)
                    status = "Token alındı, ortamlar keşfediliyor..."
                    lastToken = t.accessToken
                    envList = BcApi.discoverEnvironments(t.accessToken)
                    busy = false
                    // Ortam otomatik bulunamasa bile ekrana geç: kullanıcı ortam
                    // adını (ör. "Production") elle girip yoklayabilir.
                    selectedEnv = envList.firstOrNull()
                    step = Step.SelectEnvCompany
                    status = if (envList.isEmpty())
                        "⚠️ Otomatik ortam bulunamadı — ortam adınızı aşağıya yazıp 'Ortamı Bul' deyin"
                    else ""
                }
                is DeviceAuth.TokenResult.Failure -> { busy = false; status = "🔴 ${t.error}" }
                is DeviceAuth.TokenResult.Pending -> { busy = false; status = t.reason }
            }
        }
    }

    /**
     * Local WMS user (no email/AAD) sign-in. Requires that an admin/service AAD token is already
     * saved in BcApi prefs — that token is used as the carrier for the BC API call; BC server
     * verifies the local username/password and returns a resolved profile with roles.
     */
    fun startLocalSignIn() {
        scope.launch {
            if (!BcApi.hasToken(context)) {
                status = "🔴 Önce admin/servis erişim ayarlayın (Gelişmiş → token paste veya e-posta ile giriş)."
                return@launch
            }
            // Sanitize the username before interpolating into the OData URL key. Reject any
            // character outside the lowercase-alphanumeric + .-_ allowlist so an attacker
            // cannot break out of the single-quoted key and inject extra path segments or
            // OData functions. Matches BC's "DOPSWHS Local User".Username (Code[20]) shape.
            val rawUser = localUsername.trim().lowercase()
            if (!rawUser.matches(Regex("^[a-z0-9._-]{1,20}$"))) {
                status = "🔴 Kullanıcı adı geçersiz (sadece a-z, 0-9, . _ - karakterleri ve 1-20 karakter)."
                return@launch
            }
            // Even with allowlist there is no apostrophe possible, but escape per OData v4
            // spec (single-quote → double single-quote) for defence in depth and URL-encode.
            val safeKey = java.net.URLEncoder.encode(rawUser.replace("'", "''"), "UTF-8")
            busy = true; status = "WMS hesabı doğrulanıyor..."
            val body = JSONObject().apply { put("password", localPassword) }.toString()
            val r = BcApi.post(context, "localUsers('$safeKey')/Microsoft.NAV.verify", body)
            busy = false
            if (r.ok) {
                val resolved = BcApi.scalarValue(r.body)
                BcApi.saveLocalUser(context, rawUser, resolved)
                status = "🟢 ${displayNameFromJson(resolved) ?: rawUser} olarak bağlandı."
                onConnected(true)
            } else {
                val msg = BcApi.errorMessage(r.body).ifBlank { "HTTP ${r.httpCode}" }
                status = "🔴 ${if (msg.contains("Invalid username")) "Kullanıcı adı veya şifre hatalı." else msg}"
            }
        }
    }

    fun startSignIn() {
        scope.launch {
            busy = true; status = "Giriş kodu alınıyor..."
            val res = DeviceAuth.requestCode(email.trim())
            busy = false
            res.onSuccess { code ->
                deviceCode = code
                step = Step.DeviceCode
                status = ""
                // (User taps "Tarayıcıda Aç" to open the browser — keeps the code visible in-app first.)
                // Poll for completion.
                scope.launch {
                    busy = true; status = "Tarayıcıda giriş bekleniyor..."
                    when (val t = DeviceAuth.pollForToken(code)) {
                        is DeviceAuth.TokenResult.Success -> {
                            BcApi.saveToken(context, t.accessToken)
                    BcApi.saveRefreshToken(context, t.refreshToken)
                    BcApi.saveTokenExpiry(context, t.expiresInSec)
                            status = "Token alındı, ortamlar keşfediliyor..."
                            lastToken = t.accessToken
                            envList = BcApi.discoverEnvironments(t.accessToken)
                            busy = false
                            selectedEnv = envList.firstOrNull()
                            step = Step.SelectEnvCompany
                            if (envList.isEmpty()) {
                                status = "⚠️ Otomatik ortam bulunamadı — ortam adınızı yazıp 'Ortamı Bul' deyin"
                            } else {
                                status = ""
                            }
                        }
                        is DeviceAuth.TokenResult.Failure -> { busy = false; status = "🔴 ${t.error}" }
                        is DeviceAuth.TokenResult.Pending -> { busy = false; status = t.reason }
                    }
                }
            }.onFailure { busy = false; status = "🔴 ${it.message}" }
        }
    }

    Column(Modifier.fillMaxSize().padding(20.dp).verticalScroll(rememberScrollState())) {
        Text("BCWMS — Giriş", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Text("BC Sandbox · tenant dynamicsops", fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(20.dp))

        when (step) {
            Step.Email -> {
                Text("Kullanıcı bilgisiyle giriş", fontWeight = FontWeight.Medium)
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = email, onValueChange = { email = it },
                    label = { Text("E-posta (BC kullanıcısı)") },
                    placeholder = { Text("ornek@dynamicsops.com") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    singleLine = true, modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = password, onValueChange = { password = it },
                    label = { Text("Şifre") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true, modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(12.dp))
                // Primary: username + password direct (no browser, no token paste)
                Button(
                    onClick = { startPasswordSignIn() },
                    enabled = !busy && email.isNotBlank() && password.isNotBlank(),
                    modifier = Modifier.fillMaxWidth().height(52.dp)
                ) { Text(if (busy) "..." else "🔑 Şifre ile Bağlan", fontWeight = FontWeight.Bold) }
                Spacer(Modifier.height(10.dp))
                Text(
                    "ya da",
                    fontSize = 11.sp,
                    color = Color.Gray,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(10.dp))
                // Alt: device-code (browser) flow — for MFA / federated accounts
                OutlinedButton(
                    onClick = { startSignIn() },
                    enabled = !busy && email.isNotBlank(),
                    modifier = Modifier.fillMaxWidth().height(48.dp)
                ) { Text("🌐 Tarayıcıda Microsoft ile Giriş (MFA için)", fontSize = 13.sp) }
                Spacer(Modifier.height(8.dp))
                Text(
                    "Not: ROPC (Şifre ile Bağlan) sadece MFA / koşullu erişim olmayan hesaplar için. " +
                        "MFA'lı kullanıcılar için tarayıcı yolunu kullanın.",
                    fontSize = 10.sp,
                    color = Color.Gray
                )
                Spacer(Modifier.height(20.dp))
                HorizontalDivider()
                Spacer(Modifier.height(16.dp))
                // 3rd option: local WMS user (no AAD email)
                OutlinedButton(
                    onClick = { step = Step.LocalUser; status = "" },
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth().height(48.dp)
                ) { Text("👷 WMS Hesabı ile Giriş (e-postasız)", fontSize = 13.sp) }
                Spacer(Modifier.height(4.dp))
                Text(
                    "Depo operatörleri için BC içinde tanımlı yerel kullanıcı + şifre.",
                    fontSize = 10.sp,
                    color = Color.Gray
                )
            }

            Step.LocalUser -> {
                Text("WMS Hesabı ile Giriş", fontWeight = FontWeight.Medium)
                Text(
                    "BC'de admin tarafından oluşturulmuş yerel WMS kullanıcısı.",
                    fontSize = 11.sp,
                    color = Color.Gray
                )
                Spacer(Modifier.height(12.dp))
                if (!BcApi.hasToken(context)) {
                    Card(colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF3E0))) {
                        Column(Modifier.fillMaxWidth().padding(12.dp)) {
                            Text("⚠️ Önce paylaşımlı erişim ayarlayın", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                            Text(
                                "WMS Hesabı girişi BC'ye admin/servis AAD token üzerinden yapılır. " +
                                    "Önce \"Gelişmiş: token ile giriş\" ya da e-posta ile bir admin/servis hesabı bağlantısı yapılmalı. " +
                                    "Sonra operatörler burada kendi WMS hesaplarıyla giriş yapar.",
                                fontSize = 11.sp,
                                color = Color(0xFF6D4C41)
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }
                OutlinedTextField(
                    value = localUsername, onValueChange = { localUsername = it },
                    label = { Text("WMS Kullanıcı Adı") },
                    placeholder = { Text("wms-op-01") },
                    singleLine = true, modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = localPassword, onValueChange = { localPassword = it },
                    label = { Text("Şifre") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true, modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(16.dp))
                Button(
                    onClick = { startLocalSignIn() },
                    enabled = !busy && localUsername.isNotBlank() && localPassword.isNotBlank() && BcApi.hasToken(context),
                    modifier = Modifier.fillMaxWidth().height(52.dp)
                ) { Text(if (busy) "..." else "🚪 Bağlan", fontWeight = FontWeight.Bold) }
                Spacer(Modifier.height(8.dp))
                TextButton(onClick = { step = Step.Email; status = "" }) { Text("‹ Geri (e-posta girişine dön)") }
                // Kurulum/yönetici kaçış yolu: operatör hesabı henüz tanımlı
                // değilken cihazı BC servis kimliğiyle kullanmaya izin verir.
                TextButton(onClick = {
                    BcApi.clearLocalUser(context)
                    status = "⚠️ WMS girişi atlandı — BC hesabıyla devam ediliyor."
                    onConnected(true)
                }) { Text("Yönetici: WMS girişini atla", fontSize = 11.sp, color = Color.Gray) }
            }

            Step.DeviceCode -> {
                val code = deviceCode
                Card(colors = CardDefaults.cardColors(containerColor = Color(0xFFEDE7F6))) {
                    Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("Tarayıcıda şu kodu girin:", fontSize = 13.sp)
                        Spacer(Modifier.height(8.dp))
                        Text(code?.userCode ?: "", fontWeight = FontWeight.Bold, fontSize = 30.sp, color = Color(0xFF4527A0))
                        Spacer(Modifier.height(8.dp))
                        Text(code?.verificationUri ?: "", fontSize = 13.sp, color = Color(0xFF4527A0), textAlign = TextAlign.Center)
                    }
                }
                Spacer(Modifier.height(12.dp))
                OutlinedButton(onClick = {
                    code?.let { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it.verificationUri)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } }
                }, modifier = Modifier.fillMaxWidth()) { Text("🌐 Tarayıcıda Aç") }
                Spacer(Modifier.height(12.dp))
                if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                Spacer(Modifier.height(8.dp))
                TextButton(onClick = { step = Step.Email; status = "" }) { Text("‹ Geri") }
            }

            Step.SelectEnvCompany -> {
                Text("Ortam seçin", fontWeight = FontWeight.Medium)
                Spacer(Modifier.height(6.dp))
                // Otomatik keşif her müşterinin ortam adını bilemez (BADE =
                // "Production" vb.) — kullanıcı ortam adını elle yoklayabilir.
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = manualEnv, onValueChange = { manualEnv = it },
                        label = { Text("Ortam adı (ör. Production)") },
                        singleLine = true, modifier = Modifier.weight(1f),
                    )
                    Spacer(Modifier.width(8.dp))
                    Button(
                        enabled = !busy && manualEnv.isNotBlank() && lastToken.isNotBlank(),
                        onClick = {
                            scope.launch {
                                busy = true; status = "'${manualEnv.trim()}' yoklanıyor..."
                                val ec = BcApi.probeEnvironment(BcApi.getTenant(context), manualEnv.trim(), lastToken)
                                busy = false
                                if (ec != null) {
                                    if (envList.none { it.environment == ec.environment }) envList = envList + ec
                                    selectedEnv = ec
                                    status = "🟢 ${ec.environment} bulundu (${ec.companies.size} şirket)"
                                } else status = "🔴 '${manualEnv.trim()}' bulunamadı ya da şirket yok — ortam adını kontrol edin"
                            }
                        },
                    ) { Text("Bul") }
                }
                Spacer(Modifier.height(10.dp))
                envList.forEach { ec ->
                    val sel = ec.environment == selectedEnv?.environment
                    Card(
                        onClick = { selectedEnv = ec },
                        modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
                        colors = CardDefaults.cardColors(containerColor = if (sel) Color(0xFFD1C4E9) else Color(0xFFF5F5F5))
                    ) {
                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            RadioButton(selected = sel, onClick = { selectedEnv = ec })
                            Text("${ec.environment} (${ec.companies.size} şirket)", fontWeight = FontWeight.Medium)
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
                Text("Şirket seçin", fontWeight = FontWeight.Medium)
                Spacer(Modifier.height(6.dp))
                selectedEnv?.companies?.forEach { c ->
                    Card(
                        onClick = {
                            scope.launch {
                                busy = true; status = "Bağlanılıyor: ${c.displayName}..."
                                BcApi.setEnvironment(context, selectedEnv!!.environment)
                                BcApi.setCompany(context, c.id, c.displayName)
                                val r = BcApi.testConnection(context)
                                busy = false
                                if (r.ok) {
                                    // Paylaşımlı BC lisansı: ortam bağlantısı servis hesabıyla
                                    // yapıldı; oturum ancak WMS operatörü kendi kullanıcı adı +
                                    // şifresiyle doğrulanınca açılır (BC → WMS Users / Local User).
                                    status = "🟢 Ortam bağlandı: ${selectedEnv!!.environment} / ${c.displayName} — şimdi WMS kullanıcınızla giriş yapın"
                                    step = Step.LocalUser
                                } else { status = "🔴 Bağlanılamadı (HTTP ${r.httpCode})"; onConnected(false) }
                            }
                        },
                        modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp), shape = RoundedCornerShape(10.dp)
                    ) {
                        Column(Modifier.padding(12.dp)) {
                            Text(c.displayName, fontWeight = FontWeight.Medium)
                            Text("Seçmek için dokunun →", fontSize = 11.sp, color = Color(0xFF6A1B9A))
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(16.dp))
        StatusText(status)

        Spacer(Modifier.height(24.dp))
        TextButton(onClick = { showAdvanced = !showAdvanced }) { Text(if (showAdvanced) "Token girişini gizle" else "Gelişmiş: token ile giriş") }
        if (showAdvanced) TokenPasteFallback(onConnected = onConnected)
    }
}

/** Parses the inner displayName from the resolveProfile JSON envelope. */
private fun displayNameFromJson(jsonText: String): String? = try {
    JSONObject(jsonText.replace("{,", "{")).optString("displayName").ifBlank { null }
} catch (_: Exception) { null }

/** Advanced fallback: paste an az-CLI access token directly (the prior flow). */
@Composable
private fun TokenPasteFallback(onConnected: (Boolean) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var token by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    Column(Modifier.fillMaxWidth()) {
        Text("az account get-access-token --resource https://api.businesscentral.dynamics.com --query accessToken -o tsv",
            fontSize = 10.sp, color = Color.Gray)
        Spacer(Modifier.height(6.dp))
        OutlinedTextField(token, { token = it }, label = { Text("Access token") }, modifier = Modifier.fillMaxWidth(), maxLines = 3)
        Spacer(Modifier.height(8.dp))
        Button(enabled = token.isNotBlank(), onClick = {
            BcApi.saveToken(context, token)
            scope.launch {
                val r = BcApi.testConnection(context)
                status = if (r.ok) "🟢 Bağlandı (HTTP ${r.httpCode})" else "🔴 HTTP ${r.httpCode}"
                onConnected(r.ok)
            }
        }) { Text("Token ile Bağlan") }
        StatusText(status)
    }
}
