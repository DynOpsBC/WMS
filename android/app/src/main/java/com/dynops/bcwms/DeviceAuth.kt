package com.dynops.bcwms

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Base64
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Email-based sign-in via the OAuth 2.0 Device Authorization Grant (no MSAL dependency).
 * Flow: requestCode() -> show userCode + verificationUri -> user signs in (email) in a browser ->
 * pollForToken() returns the BC access token.
 *
 * MULTI-TENANT: authority = /organizations (herhangi bir iş/okul tenant'ı).
 * Kullanıcı hangi tenant'ın hesabıyla girerse token o tenant'a ait olur;
 * BcApi.captureTenantFromToken token'daki gerçek tenant'ı kaydeder. Böylece
 * BADE, DynamicsOps vb. her müşteri aynı APK ile kendi tenant'ına bağlanır.
 * (Client, Entra'da AzureADMultipleOrgs + "allow public client flows" olmalı;
 * her müşteri yöneticisi kendi tenant'ında bu client'a bir kez onay verir.)
 */
object DeviceAuth {
    // Multi-tenant authority. Tenant, kullanıcının e-posta DOMAIN'inden türetilir
    // (badenatural.com → .../badenatural.com/...). Entra domainden tenant'ı
    // çözer; token'daki gerçek tid sonra BcApi.captureTenantFromToken ile alınır.
    //   - ROPC (password): tenant-belirsiz authority AADSTS50059 verir → domain ŞART.
    //   - device-code: domain verilebilirse tenant-özel; yoksa /organizations.
    private fun authority(path: String, tenantSegment: String) =
        "https://login.microsoftonline.com/$tenantSegment/oauth2/v2.0/$path"

    /** E-posta domainini tenant segmenti olarak döndürür; domain yoksa fallback. */
    private fun tenantFromEmail(email: String, fallback: String): String {
        val at = email.trim().substringAfter('@', "").trim()
        return if (at.isNotBlank() && at.contains('.')) at else fallback
    }

    // Request the BC delegated scope explicitly (dynamic consent) rather than ".default": the app
    // registration's static API-permission list has a stale/invalid BC permission id, which makes
    // ".default" fail with AADSTS65006. Asking for user_impersonation by URI resolves the real scope.
    private val SCOPE = "${BcApi.BC_RESOURCE}/user_impersonation offline_access"

    data class DeviceCode(
        val deviceCode: String,
        val userCode: String,
        val verificationUri: String,
        val interval: Int,
        val expiresIn: Int,
        val message: String,
        // requestCode'un kullandığı tenant segment'i — poll aynısını kullanmalı.
        val tenantSegment: String = "organizations",
    )

    sealed class TokenResult {
        data class Success(val accessToken: String, val refreshToken: String = "", val expiresInSec: Int = 3600) : TokenResult()
        data class Pending(val reason: String) : TokenResult()
        data class Failure(val error: String) : TokenResult()
    }

    /**
     * Step 1: request a device + user code. E-posta domaininden tenant türetilir
     * (badenatural.com gibi); domain yoksa /organizations. Aynı tenant segment'i
     * DeviceCode içinde taşınır ki poll da onu kullansın (yoksa AADSTS50059).
     */
    suspend fun requestCode(email: String = ""): Result<DeviceCode> = withContext(Dispatchers.IO) {
        try {
            val tenant = tenantFromEmail(email, "organizations")
            val body = "client_id=${BcApi.CLIENT_ID}&scope=${enc(SCOPE)}"
            val resp = postForm(authority("devicecode", tenant), body)
            val j = JSONObject(resp.second)
            if (resp.first !in 200..299)
                return@withContext Result.failure(Exception(j.optString("error_description", j.optString("error", "device code error"))))
            Result.success(
                DeviceCode(
                    deviceCode = j.getString("device_code"),
                    userCode = j.getString("user_code"),
                    verificationUri = j.optString("verification_uri", "https://microsoft.com/devicelogin"),
                    interval = j.optInt("interval", 5),
                    expiresIn = j.optInt("expires_in", 900),
                    message = j.optString("message"),
                    tenantSegment = tenant,
                )
            )
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Step 2: poll the token endpoint until the user completes sign-in (or it times out).
     * Honors the server interval and authorization_pending/slow_down semantics.
     */
    suspend fun pollForToken(code: DeviceCode): TokenResult = withContext(Dispatchers.IO) {
        var intervalMs = code.interval.coerceAtLeast(1) * 1000L
        val deadline = System.currentTimeMillis() + code.expiresIn * 1000L
        while (System.currentTimeMillis() < deadline) {
            delay(intervalMs)
            val body = "grant_type=urn:ietf:params:oauth:grant-type:device_code" +
                "&client_id=${BcApi.CLIENT_ID}&device_code=${enc(code.deviceCode)}"
            val (status, text) = postForm(authority("token", code.tenantSegment), body)
            val j = try { JSONObject(text) } catch (e: Exception) { JSONObject() }
            if (status in 200..299) {
                val token = j.optString("access_token")
                if (token.isNotBlank()) return@withContext TokenResult.Success(token, j.optString("refresh_token"), j.optInt("expires_in", 3600))
            }
            when (j.optString("error")) {
                "authorization_pending" -> {}                       // keep waiting
                "slow_down" -> intervalMs += 5000L                  // back off
                "expired_token", "code_expired" -> return@withContext TokenResult.Failure("Kod süresi doldu, tekrar deneyin.")
                "authorization_declined", "access_denied" -> return@withContext TokenResult.Failure("Giriş reddedildi.")
                "" -> {}
                else -> return@withContext TokenResult.Failure(j.optString("error_description", j.optString("error")))
            }
        }
        TokenResult.Failure("Zaman aşımı — giriş tamamlanmadı.")
    }

    /**
     * Direct username/password sign-in via OAuth 2.0 Resource Owner Password Credentials grant.
     * Calls AAD's /token endpoint with the user's email + password and returns a BC access token.
     *
     * Caveats:
     * - Only works for cloud-only AAD accounts (no MFA, no federated sign-in / ADFS).
     * - Recommended only for warehouse operator accounts in controlled tenants — service-style
     *   accounts where MFA is exempted by Conditional Access. For interactive users with MFA
     *   on, use [requestCode] + [pollForToken] (device code flow) instead.
     */
    suspend fun loginWithPassword(email: String, password: String): TokenResult = withContext(Dispatchers.IO) {
        try {
            // ROPC tenant-belirsiz authority ile çalışmaz (AADSTS50059) —
            // e-posta domaininden tenant türetilir.
            val tenant = tenantFromEmail(email, "organizations")
            val body = "grant_type=password" +
                "&client_id=${BcApi.CLIENT_ID}" +
                "&scope=${enc(SCOPE)}" +
                "&username=${enc(email)}" +
                "&password=${enc(password)}"
            val (status, text) = postForm(authority("token", tenant), body)
            val j = try { JSONObject(text) } catch (e: Exception) { JSONObject() }
            if (status in 200..299) {
                val token = j.optString("access_token")
                if (token.isNotBlank()) return@withContext TokenResult.Success(token, j.optString("refresh_token"), j.optInt("expires_in", 3600))
                return@withContext TokenResult.Failure("Token boş döndü.")
            }
            val err = j.optString("error")
            val desc = j.optString("error_description").substringBefore("\r").substringBefore("\n")
            val friendly = when (err) {
                "invalid_grant" -> "E-posta veya şifre hatalı. ($desc)"
                "interaction_required", "consent_required" -> "Etkileşim gerekli — Cihaz koduyla giriş yapın (MFA / koşullu erişim)."
                "unauthorized_client" -> "AAD app registration ROPC akışına izin vermiyor."
                else -> if (desc.isNotBlank()) desc else (err.ifBlank { "AAD hatası ($status)" })
            }
            TokenResult.Failure(friendly)
        } catch (e: Exception) {
            TokenResult.Failure(e.message ?: "ağ hatası")
        }
    }

    /**
     * Exchanges a refresh token for a fresh access token (blocking — call from an IO dispatcher).
     * Returns Pair(accessToken, rotatedRefreshToken) or null when AAD rejects the refresh
     * (revoked / expired refresh token) so the caller can fall back to a full re-login.
     */
    fun refreshAccessToken(refreshToken: String, tenantSegment: String = "organizations"): Triple<String, String, Int>? {
        return try {
            val body = "grant_type=refresh_token" +
                "&client_id=${BcApi.CLIENT_ID}" +
                "&scope=${enc(SCOPE)}" +
                "&refresh_token=${enc(refreshToken)}"
            val (status, text) = postForm(authority("token", tenantSegment), body)
            if (status !in 200..299) return null
            val j = JSONObject(text)
            val token = j.optString("access_token")
            if (token.isBlank()) null
            // AAD rotates refresh tokens; fall back to the old one if none returned.
            else Triple(token, j.optString("refresh_token").ifBlank { refreshToken }, j.optInt("expires_in", 3600))
        } catch (e: Exception) { null }
    }

    // ---- Browser sign-in (authorization code + PKCE) ----
    // ICT (30 Eki 2026): ICT kiracısında Microsoft güvenlik varsayılanları açık ve cihaz kodu
    // akışını engelliyor (AADSTS530035). Bu akışta giriş, cihazın tarayıcısında normal Microsoft
    // sayfasında yapılır (MFA dahil) ve tarayıcı <applicationId>://auth adresiyle uygulamaya döner.

    private class PendingBrowserSignIn(val state: String, val verifier: String, val tenant: String) {
        val code = CompletableDeferred<Result<String>>()
    }

    @Volatile private var pendingBrowser: PendingBrowserSignIn? = null

    fun browserRedirectUri(): String = "${BuildConfig.APPLICATION_ID}://auth"

    /** Opens the Microsoft sign-in page and waits (up to 10 minutes) for the app redirect. */
    suspend fun signInWithBrowser(context: Context, email: String): TokenResult {
        val verifier = randomUrlSafe(48)
        val challenge = Base64.encodeToString(
            MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)),
            Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
        )
        val tenant = tenantFromEmail(email, BuildConfig.BC_FALLBACK_TENANT)
        val pending = PendingBrowserSignIn(randomUrlSafe(16), verifier, tenant)
        pendingBrowser = pending
        val url = authority("authorize", tenant) +
            "?client_id=${enc(BcApi.CLIENT_ID)}&response_type=code" +
            "&redirect_uri=${enc(browserRedirectUri())}&response_mode=query" +
            "&scope=${enc(SCOPE)}&state=${enc(pending.state)}" +
            "&code_challenge=${enc(challenge)}&code_challenge_method=S256" +
            (if (email.isNotBlank()) "&login_hint=${enc(email.trim())}" else "") +
            "&prompt=select_account"
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val result = withTimeoutOrNull(10 * 60 * 1000L) { pending.code.await() }
        pendingBrowser = null
        val code = result ?: return TokenResult.Failure("Zaman aşımı — tarayıcıda giriş tamamlanmadı.")
        return code.fold(
            onSuccess = { redeemBrowserCode(it, pending) },
            onFailure = { TokenResult.Failure(it.message ?: "Giriş tamamlanmadı.") },
        )
    }

    /** Called by MainActivity for <applicationId>://auth intents. Returns true when handled. */
    fun handleBrowserRedirect(uri: Uri?): Boolean {
        if (uri == null || uri.scheme != BuildConfig.APPLICATION_ID || uri.host != "auth") return false
        val pending = pendingBrowser ?: return true
        if (uri.getQueryParameter("state") != pending.state) {
            pending.code.complete(Result.failure(IllegalStateException("Giriş yanıtı bu cihazın isteğine ait değil.")))
            return true
        }
        val code = uri.getQueryParameter("code")
        if (!code.isNullOrBlank()) pending.code.complete(Result.success(code))
        else pending.code.complete(Result.failure(IllegalStateException(
            uri.getQueryParameter("error_description")?.substringBefore("\r")?.substringBefore("\n")
                ?: uri.getQueryParameter("error") ?: "Giriş reddedildi.")))
        return true
    }

    private suspend fun redeemBrowserCode(code: String, pending: PendingBrowserSignIn): TokenResult = withContext(Dispatchers.IO) {
        try {
            val body = "grant_type=authorization_code" +
                "&client_id=${enc(BcApi.CLIENT_ID)}" +
                "&code=${enc(code)}" +
                "&redirect_uri=${enc(browserRedirectUri())}" +
                "&code_verifier=${enc(pending.verifier)}" +
                "&scope=${enc(SCOPE)}"
            val (status, text) = postForm(authority("token", pending.tenant), body)
            val j = try { JSONObject(text) } catch (e: Exception) { JSONObject() }
            val token = j.optString("access_token")
            if (status in 200..299 && token.isNotBlank())
                TokenResult.Success(token, j.optString("refresh_token"), j.optInt("expires_in", 3600))
            else TokenResult.Failure(j.optString("error_description").substringBefore("\r").ifBlank { "AAD hatası ($status)" })
        } catch (e: Exception) {
            TokenResult.Failure(e.message ?: "ağ hatası")
        }
    }

    private fun randomUrlSafe(bytes: Int): String {
        val b = ByteArray(bytes)
        SecureRandom().nextBytes(b)
        return Base64.encodeToString(b, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    private fun postForm(url: String, body: String): Pair<Int, String> {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            setRequestProperty("Accept", "application/json")
            doOutput = true
            connectTimeout = 15000; readTimeout = 20000
        }
        conn.outputStream.use { it.write(body.toByteArray()) }
        val code = conn.responseCode
        val text = if (code in 200..299) conn.inputStream.bufferedReader().readText()
            else conn.errorStream?.bufferedReader()?.readText() ?: "{}"
        return code to text
    }
}
