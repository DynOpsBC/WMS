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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.DeviceAuth
import com.dynops.bcwms.ui.StatusText
import kotlinx.coroutines.launch
import org.json.JSONObject

private enum class Step { Email, DeviceCode, SelectEnvCompany }

/**
 * Email-based sign-in: email → device-code (browser) → environment + company selection → connect.
 * No token paste required. Token-paste remains available as an "advanced" fallback.
 */
@Composable
fun LoginFlow(onConnected: (Boolean) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var step by remember { mutableStateOf(Step.Email) }
    var email by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var showAdvanced by remember { mutableStateOf(false) }

    var deviceCode by remember { mutableStateOf<DeviceAuth.DeviceCode?>(null) }
    var envList by remember { mutableStateOf<List<BcApi.EnvCompanies>>(emptyList()) }
    var selectedEnv by remember { mutableStateOf<BcApi.EnvCompanies?>(null) }

    fun startSignIn() {
        scope.launch {
            busy = true; status = "Giriş kodu alınıyor..."
            val res = DeviceAuth.requestCode()
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
                            status = "Token alındı, ortamlar keşfediliyor..."
                            envList = BcApi.discoverEnvironments(t.accessToken)
                            busy = false
                            if (envList.isEmpty()) {
                                status = "🔴 Erişilebilir ortam bulunamadı. Yetkileri kontrol edin."
                            } else {
                                selectedEnv = envList.first()
                                step = Step.SelectEnvCompany
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
                Text("E-posta ile giriş yapın", fontWeight = FontWeight.Medium)
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = email, onValueChange = { email = it },
                    label = { Text("E-posta") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    singleLine = true, modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(16.dp))
                Button(
                    onClick = { startSignIn() },
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth().height(52.dp)
                ) { Text(if (busy) "..." else "🔐 Giriş Yap", fontWeight = FontWeight.Bold) }
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
                                if (r.ok) { status = "🟢 Bağlandı: ${selectedEnv!!.environment} / ${c.displayName}"; onConnected(true) }
                                else { status = "🔴 Bağlanılamadı (HTTP ${r.httpCode})"; onConnected(false) }
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
