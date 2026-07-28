package com.dynops.bcwms.feature

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.draw.clip
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
import com.dynops.bcwms.BuildConfig
import com.dynops.bcwms.DeviceAuth
import com.dynops.bcwms.ui.StatusText
import kotlinx.coroutines.launch
import org.json.JSONObject

private enum class Step { Email, DeviceCode, SelectEnvCompany, LocalUser }

/** Girişte listelenecek kayıtlı WMS operatörü. */
data class LocalUserOption(val username: String, val displayName: String)

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

    // Kayıtlı WMS operatörleri (BC localUsers) — girişte listeden seçilir.
    var localUsers by remember { mutableStateOf<List<LocalUserOption>>(emptyList()) }
    var usersLoading by remember { mutableStateOf(false) }
    var manualUserEntry by remember { mutableStateOf(false) }
    var showPassword by remember { mutableStateOf(false) }
    var showForgotPassword by remember { mutableStateOf(false) }

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
                // ELOG multi-company: operatörün bu ortamda erişebildiği (WMS kurulu +
                // localUser kaydı olan) şirketleri hesapla → üstteki şirket değiştiricide
                // yalnız bunlar görünür (PIM vb. dışarıda kalır). Keşif listesi yoksa
                // en azından aktif şirketi kaydet ki switcher tutarlı olsun.
                val candidates = selectedEnv?.companies
                    ?: listOf(BcApi.Company(BcApi.getCompanyId(context), BcApi.getCompanyName(context), BcApi.getCompanyName(context)))
                val accessible = runCatching {
                    BcApi.probeAccessibleCompanies(context, BcApi.getEnvironment(context), rawUser, candidates)
                }.getOrDefault(emptyList())
                BcApi.saveAccessibleCompanies(
                    context,
                    accessible.ifEmpty {
                        listOf(BcApi.Company(BcApi.getCompanyId(context), BcApi.getCompanyName(context), BcApi.getCompanyName(context)))
                    },
                )
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

    // WMS giriş adımına gelince kayıtlı operatörleri çek (token varsa).
    LaunchedEffect(step) {
        if (step != Step.LocalUser || localUsers.isNotEmpty() || !BcApi.hasToken(context)) return@LaunchedEffect
        usersLoading = true
        val r = runCatching {
            BcApi.get(context, "localUsers?\$select=username,displayName,disabled&\$top=200&\$orderby=username")
        }.getOrNull()
        if (r?.ok == true) {
            val arr = runCatching { JSONObject(r.body).optJSONArray("value") }.getOrNull()
            val list = mutableListOf<LocalUserOption>()
            for (i in 0 until (arr?.length() ?: 0)) {
                val o = arr!!.optJSONObject(i) ?: continue
                if (o.optBoolean("disabled", false)) continue
                val u = o.optString("username").trim()
                if (u.isNotBlank()) list += LocalUserOption(u, o.optString("displayName").trim())
            }
            localUsers = list
            if (list.isEmpty()) manualUserEntry = true
        } else {
            // API yoksa/erişilemiyorsa elle giriş yolu açık kalsın.
            manualUserEntry = true
        }
        usersLoading = false
    }

    if (showForgotPassword) {
        ForgotPasswordSheet(
            username = localUsername,
            onDismiss = { showForgotPassword = false },
        )
    }

    Column(Modifier.fillMaxSize().padding(20.dp).verticalScroll(rememberScrollState())) {
        Text("BCWMS — Giriş", fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Text("BC · tenant ${BuildConfig.TENANT_LABEL}", fontSize = 12.sp, color = Color.Gray)
        Spacer(Modifier.height(20.dp))

        when (step) {
            Step.Email -> {
                Text("Kullanıcı bilgisiyle giriş", fontWeight = FontWeight.Medium)
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = email, onValueChange = { email = it },
                    label = { Text("E-posta (BC kullanıcısı)") },
                    placeholder = { Text(BuildConfig.LOGIN_EMAIL_HINT) },
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
                ) { Text(if (busy) "..." else "Şifre ile Bağlan", fontWeight = FontWeight.Bold) }
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
                ) { Text("Tarayıcıda Microsoft ile Giriş (MFA için)", fontSize = 13.sp) }
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
                ) { Text("WMS Hesabı ile Giriş (e-postasız)", fontSize = 13.sp) }
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
                            Text("Önce paylaşımlı erişim ayarlayın", fontWeight = FontWeight.Bold, fontSize = 13.sp)
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
                // Kayıtlı operatörler: BC'den çekilen listeden seç → şifre alanına odaklan.
                // Liste boşsa (API yok / yetki yok) elle yazma alanına düşer.
                if (localUsername.isBlank()) {
                    when {
                        usersLoading -> {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                                Spacer(Modifier.width(10.dp))
                                Text("Kullanıcılar yükleniyor...", fontSize = 12.sp, color = Color.Gray)
                            }
                            Spacer(Modifier.height(8.dp))
                        }
                        localUsers.isNotEmpty() -> {
                            Text("Kullanıcınızı seçin", fontSize = 12.sp, fontWeight = FontWeight.Medium, color = Color.Gray)
                            Spacer(Modifier.height(8.dp))
                            localUsers.forEach { u ->
                                Card(
                                    onClick = { localUsername = u.username; manualUserEntry = false; status = "" },
                                    colors = CardDefaults.cardColors(containerColor = Color(0xFFF3F0FF)),
                                    shape = RoundedCornerShape(12.dp),
                                    modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
                                ) {
                                    Row(
                                        Modifier.fillMaxWidth().padding(14.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        // Avatar: adın baş harfi (emoji yerine — kurumsal görünüm).
                                        Box(
                                            Modifier.size(38.dp).clip(RoundedCornerShape(12.dp))
                                                .background(Color(0xFF6C5CE7).copy(alpha = 0.15f)),
                                            contentAlignment = Alignment.Center,
                                        ) {
                                            Text(
                                                u.displayName.ifBlank { u.username }.take(1).uppercase(),
                                                fontSize = 17.sp,
                                                fontWeight = FontWeight.Bold,
                                                color = Color(0xFF6C5CE7),
                                            )
                                        }
                                        Spacer(Modifier.width(12.dp))
                                        Column(Modifier.weight(1f)) {
                                            Text(
                                                u.displayName.ifBlank { u.username },
                                                fontWeight = FontWeight.SemiBold,
                                                fontSize = 15.sp,
                                            )
                                            Text(u.username, fontSize = 11.sp, color = Color.Gray)
                                        }
                                        Text("›", fontSize = 20.sp, color = Color(0xFF6C5CE7))
                                    }
                                }
                            }
                            Spacer(Modifier.height(4.dp))
                            TextButton(onClick = { manualUserEntry = true }) {
                                Text("Listede yokum — elle yazayım", fontSize = 12.sp)
                            }
                        }
                        // Liste boş/çekilemedi: elle yazma alanı zaten aşağıda
                        // görünür (manualUserEntry LaunchedEffect'te açılır).
                        else -> Unit
                    }
                }

                // Seçilmiş kullanıcı rozeti + değiştir
                if (localUsername.isNotBlank() && !manualUserEntry) {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = Color(0xFFEDE7F6)),
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            val disp = localUsers.firstOrNull { it.username == localUsername }?.displayName.orEmpty()
                            Box(
                                Modifier.size(34.dp).clip(RoundedCornerShape(10.dp))
                                    .background(Color(0xFF6C5CE7).copy(alpha = 0.18f)),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    disp.ifBlank { localUsername }.take(1).uppercase(),
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color(0xFF6C5CE7),
                                )
                            }
                            Spacer(Modifier.width(10.dp))
                            Column(Modifier.weight(1f)) {
                                Text(disp.ifBlank { localUsername }, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                                if (disp.isNotBlank()) Text(localUsername, fontSize = 11.sp, color = Color.Gray)
                            }
                            TextButton(onClick = { localUsername = ""; localPassword = ""; status = "" }) {
                                Text("Değiştir", fontSize = 12.sp)
                            }
                        }
                    }
                    Spacer(Modifier.height(10.dp))
                }

                if (manualUserEntry) {
                    OutlinedTextField(
                        value = localUsername, onValueChange = { localUsername = it },
                        label = { Text("WMS Kullanıcı Adı") },
                        placeholder = { Text("wms-op-01") },
                        singleLine = true, modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(8.dp))
                }

                if (localUsername.isNotBlank() || manualUserEntry) {
                    OutlinedTextField(
                        value = localPassword, onValueChange = { localPassword = it },
                        label = { Text("Şifre") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        visualTransformation = if (showPassword) androidx.compose.ui.text.input.VisualTransformation.None
                            else PasswordVisualTransformation(),
                        trailingIcon = {
                            TextButton(onClick = { showPassword = !showPassword }) {
                                Text(if (showPassword) "Gizle" else "Göster", fontSize = 12.sp)
                            }
                        },
                        singleLine = true, modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(16.dp))
                    Button(
                        onClick = { startLocalSignIn() },
                        enabled = !busy && localUsername.isNotBlank() && localPassword.isNotBlank() && BcApi.hasToken(context),
                        modifier = Modifier.fillMaxWidth().height(52.dp)
                    ) { Text(if (busy) "..." else "Bağlan", fontWeight = FontWeight.Bold) }
                    Spacer(Modifier.height(4.dp))
                    TextButton(
                        onClick = { showForgotPassword = true },
                        modifier = Modifier.align(Alignment.CenterHorizontally),
                    ) { Text("Şifremi unuttum", fontSize = 12.sp, color = Color(0xFF6C5CE7)) }
                }
                Spacer(Modifier.height(4.dp))
                TextButton(onClick = { step = Step.Email; status = ""; manualUserEntry = false }) { Text("‹ Geri (e-posta girişine dön)") }
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
                }, modifier = Modifier.fillMaxWidth()) { Text("Tarayıcıda Aç") }
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
                    label = { Text("Ortam adı (ör. ${BuildConfig.BC_DEFAULT_ENVIRONMENT})") },
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
                                    // ELOG multi-company: WMS kullanıcı girişi ATLANSA bile (admin/AAD)
                                    // üstteki şirket değiştirici çalışsın diye erişilebilir (WMS kurulu)
                                    // şirketleri şimdi hesapla/sakla. WMS kullanıcı girişi yapılırsa
                                    // orada kullanıcı-bazlı daha dar listeyle üzerine yazılır.
                                    val wmsCompanies = runCatching {
                                        BcApi.probeWmsCompanies(context, selectedEnv!!.environment, selectedEnv!!.companies)
                                    }.getOrDefault(emptyList())
                                    BcApi.saveAccessibleCompanies(
                                        context,
                                        wmsCompanies.ifEmpty { listOf(c) },
                                    )
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
        OutlinedTextField(token, { token = it }, label = { Text("Erişim belirteci") }, modifier = Modifier.fillMaxWidth(), maxLines = 3)
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

/**
 * "Şifremi unuttum" — WMS operatör şifreleri BC'de hash'li tutulur, terminalden
 * sıfırlanamaz. Bu sayfa operatöre kimden yardım isteyeceğini net söyler ve
 * yöneticiye BC'deki adımı hatırlatır.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ForgotPasswordSheet(username: String, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 28.dp)) {
            Text("Şifremi unuttum", fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Spacer(Modifier.height(6.dp))
            Text(
                if (username.isNotBlank()) "Kullanıcı: $username" else "WMS operatör şifresi",
                fontSize = 12.sp, color = Color.Gray,
            )
            Spacer(Modifier.height(16.dp))
            Card(
                colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF8E1)),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(Modifier.padding(14.dp)) {
                    Text("Şifreniz terminalden sıfırlanamaz", fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "Güvenlik gereği WMS şifreleri Business Central'da şifrelenmiş saklanır. " +
                            "Depo sorumlunuz size yeni bir şifre belirlemeli.",
                        fontSize = 12.sp, color = Color(0xFF6D4C41),
                    )
                }
            }
            Spacer(Modifier.height(16.dp))
            Text("Depo sorumlusu için adımlar", fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
            Spacer(Modifier.height(8.dp))
            listOf(
                "1. Business Central'da \"Local WMS Users\" sayfasını açın",
                "2. İlgili kullanıcıyı seçip Düzenle deyin",
                "3. \"Şifre\" bölümüne yeni şifreyi yazın (kaydedilince hash'lenir)",
                "4. Yeni şifreyi operatöre güvenli kanaldan iletin",
            ).forEach {
                Text(it, fontSize = 12.sp, modifier = Modifier.padding(vertical = 3.dp))
            }
            Spacer(Modifier.height(20.dp))
            Button(onClick = onDismiss, modifier = Modifier.fillMaxWidth().height(48.dp)) {
                Text("Anladım")
            }
        }
    }
}
