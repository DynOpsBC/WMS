package com.dynops.bcwms

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

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
        "$loginHost/$tenantSegment/oauth2/v2.0/$path"

    /** Entra sign-in host; unit tests point it at a local mock server. */
    @Volatile
    internal var loginHost = "https://login.microsoftonline.com"

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

    /** Result of a single token-endpoint poll during the device-code flow. */
    sealed class PollResult {
        data class Success(val token: TokenResult.Success) : PollResult()
        /** authorization_pending / slow_down: the user has not finished in the browser yet. */
        data class Waiting(val slowDown: Boolean = false) : PollResult()
        /**
         * The request never reached Entra (no network, DNS, timeout). Not an answer
         * from the server, so the caller keeps the code and simply polls again.
         */
        data class Offline(val reason: String) : PollResult()
        data class Failed(val error: String, val expired: Boolean = false) : PollResult()
    }

    /** Maps one token-endpoint response to a [PollResult]. Pure, unit-tested. */
    internal fun interpretTokenResponse(status: Int, text: String): PollResult {
        val j = try { JSONObject(text) } catch (e: Exception) { JSONObject() }
        if (status in 200..299) {
            val token = j.optString("access_token")
            if (token.isNotBlank())
                return PollResult.Success(TokenResult.Success(token, j.optString("refresh_token"), j.optInt("expires_in", 3600)))
        }
        return when (val error = j.optString("error")) {
            "authorization_pending" -> PollResult.Waiting()
            "slow_down" -> PollResult.Waiting(slowDown = true)
            "expired_token", "code_expired" -> PollResult.Failed("Kod süresi doldu, tekrar deneyin.", expired = true)
            "authorization_declined", "access_denied" -> PollResult.Failed("Giriş reddedildi.")
            // A body without an OAuth error (proxy page, 5xx) is not a final answer.
            "" -> if (status >= 500 || status in 200..299) PollResult.Waiting() else PollResult.Offline("HTTP $status")
            else -> PollResult.Failed(j.optString("error_description", error).substringBefore("\r").substringBefore("\n"))
        }
    }

    /**
     * One poll of the token endpoint. Never throws for network problems:
     * a terminal that is in the background (Android 15+ cuts network for
     * cached apps), roaming between access points or briefly offline must
     * not crash the app while the user approves in Authenticator.
     */
    suspend fun pollOnce(code: DeviceCode): PollResult = withContext(Dispatchers.IO) {
        try {
            val body = "grant_type=urn:ietf:params:oauth:grant-type:device_code" +
                "&client_id=${BcApi.CLIENT_ID}&device_code=${enc(code.deviceCode)}"
            val (status, text) = postForm(authority("token", code.tenantSegment), body)
            interpretTokenResponse(status, text)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PollResult.Offline(e.message ?: e.javaClass.simpleName)
        }
    }

    /**
     * Step 2: poll the token endpoint until the user completes sign-in (or it times out).
     * Honors the server interval and authorization_pending/slow_down semantics.
     * Network errors are retried until the code expires (they used to escape
     * as an uncaught IOException and close the app).
     */
    suspend fun pollForToken(code: DeviceCode): TokenResult = withContext(Dispatchers.IO) {
        var intervalMs = code.interval.coerceAtLeast(1) * 1000L
        val deadline = System.currentTimeMillis() + code.expiresIn * 1000L
        while (System.currentTimeMillis() < deadline) {
            delay(intervalMs)
            when (val r = pollOnce(code)) {
                is PollResult.Success -> return@withContext r.token
                is PollResult.Waiting -> if (r.slowDown) intervalMs += 5000L
                is PollResult.Offline -> {}                                 // try again next interval
                is PollResult.Failed -> return@withContext TokenResult.Failure(r.error)
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
