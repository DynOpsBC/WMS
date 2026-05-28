package com.dynops.bcwms

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Business Central SaaS API client.
 * Token bir kez girilir, SharedPreferences'ta kalici saklanir, tum ekranlar otomatik kullanir.
 */
object BcApi {
    const val TENANT = "7fa2357e-26f2-4174-8e16-a713981356b8"
    const val CLIENT_ID = "8193e5c6-64d2-4e6f-8992-2114e77e4f24"  // BCWMSApp Mobile (public client, device-code)
    const val BC_RESOURCE = "https://api.businesscentral.dynamics.com"

    // Defaults (used until the user picks an environment/company after email sign-in).
    const val DEFAULT_ENVIRONMENT = "SandboxUS"
    const val DEFAULT_COMPANY_ID = "1534369d-f248-f111-b478-7c1e521cfdf0"
    const val DEFAULT_COMPANY_NAME = "CRONUS USA, Inc."

    /** Environments the app can discover companies in (probed after sign-in). */
    val KNOWN_ENVIRONMENTS = listOf("SandboxUS", "CustomerSandbox")

    private const val PREFS = "bcwms_prefs"
    private const val KEY_TOKEN = "bc_access_token"
    private const val KEY_ENV = "bc_environment"
    private const val KEY_COMPANY_ID = "bc_company_id"
    private const val KEY_COMPANY_NAME = "bc_company_name"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ---- Environment / company selection (runtime-configurable) ----
    fun getEnvironment(context: Context): String = prefs(context).getString(KEY_ENV, DEFAULT_ENVIRONMENT) ?: DEFAULT_ENVIRONMENT
    fun getCompanyId(context: Context): String = prefs(context).getString(KEY_COMPANY_ID, DEFAULT_COMPANY_ID) ?: DEFAULT_COMPANY_ID
    fun getCompanyName(context: Context): String = prefs(context).getString(KEY_COMPANY_NAME, DEFAULT_COMPANY_NAME) ?: DEFAULT_COMPANY_NAME

    fun setEnvironment(context: Context, env: String) { prefs(context).edit().putString(KEY_ENV, env).apply() }
    fun setCompany(context: Context, id: String, name: String) {
        prefs(context).edit().putString(KEY_COMPANY_ID, id).putString(KEY_COMPANY_NAME, name).apply()
    }

    private fun customApiBase(context: Context) =
        "https://api.businesscentral.dynamics.com/v2.0/$TENANT/${getEnvironment(context)}/api/dynops/warehouse/v2.0/companies(${getCompanyId(context)})"

    private fun standardApiBase(context: Context) =
        "https://api.businesscentral.dynamics.com/v2.0/$TENANT/${getEnvironment(context)}/api/v2.0/companies(${getCompanyId(context)})"

    /** Standard companies endpoint for a given environment (no company segment) — used for discovery. */
    fun companiesUrl(env: String) =
        "https://api.businesscentral.dynamics.com/v2.0/$TENANT/$env/api/v2.0/companies?\$select=id,name,displayName"

    // ---- Token persistence ----
    fun saveToken(context: Context, token: String) {
        prefs(context).edit().putString(KEY_TOKEN, token.trim()).apply()
    }

    fun getToken(context: Context): String = prefs(context).getString(KEY_TOKEN, "") ?: ""

    fun hasToken(context: Context): Boolean = getToken(context).isNotBlank()

    fun clearToken(context: Context) { prefs(context).edit().remove(KEY_TOKEN).apply() }

    // ---- HTTP ----
    data class ApiResult(val ok: Boolean, val httpCode: Int, val body: String)

    suspend fun get(context: Context, path: String): ApiResult = request(context, "GET", path, null)

    suspend fun getWithStandardFallback(context: Context, path: String): ApiResult {
        val custom = get(context, path)
        if (custom.httpCode != 404) return custom
        return request(context, "GET", "${standardApiBase(context)}/$path", null)
    }

    suspend fun getWithStandardFallback(context: Context, customPath: String, standardPath: String): ApiResult {
        val custom = get(context, customPath)
        if (custom.httpCode != 404) return custom
        return request(context, "GET", "${standardApiBase(context)}/$standardPath", null)
    }

    suspend fun post(context: Context, path: String, jsonBody: String?): ApiResult =
        request(context, "POST", path, jsonBody)

    suspend fun patch(context: Context, path: String, jsonBody: String): ApiResult =
        request(context, "PATCH", path, jsonBody)

    suspend fun delete(context: Context, path: String): ApiResult =
        request(context, "DELETE", path, null)

    /**
     * Bound action: POST .../{entitySet}({key})/Microsoft.NAV.{action}
     * BC custom-API string keys MUST be single-quoted, e.g. licensePlates('LP000001').
     * Multi-segment keys (composite) may be passed already-formatted; we only quote when
     * the key is not already wrapped in parentheses-style segments.
     */
    suspend fun boundAction(
        context: Context,
        entitySet: String,
        key: String,
        action: String,
        body: String = "{}"
    ): ApiResult {
        val keySegment = if (key.contains("=") || key.startsWith("'")) key else "'${key.replace("'", "''")}'"
        val path = "$entitySet($keySegment)/Microsoft.NAV.$action"
        return request(context, "POST", path, body)
    }

    private suspend fun request(context: Context, method: String, path: String, jsonBody: String?): ApiResult =
        withContext(Dispatchers.IO) {
            val token = getToken(context)
            if (token.isBlank()) return@withContext ApiResult(false, 0, "Token yok — Connection ekranindan token girin")
            try {
                val rawUrl = if (path.startsWith("http")) path else "${customApiBase(context)}/$path"
                val url = URL(rawUrl.replace(" ", "%20").replace("'", "%27"))
                // HttpURLConnection cannot send PATCH natively; tunnel it via POST + override header.
                val needsOverride = method == "PATCH"
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = if (needsOverride) "POST" else method
                    if (needsOverride) setRequestProperty("X-HTTP-Method-Override", "PATCH")
                    setRequestProperty("Authorization", "Bearer $token")
                    setRequestProperty("Accept", "application/json")
                    // BC requires If-Match for PATCH/DELETE; "*" skips optimistic-concurrency check.
                    if (method == "PATCH" || method == "DELETE") setRequestProperty("If-Match", "*")
                    if (jsonBody != null) {
                        setRequestProperty("Content-Type", "application/json")
                        doOutput = true
                    }
                    connectTimeout = 15000
                    readTimeout = 20000
                }
                if (jsonBody != null) conn.outputStream.use { it.write(jsonBody.toByteArray()) }
                val code = conn.responseCode
                val body = if (code in 200..299)
                    conn.inputStream.bufferedReader().readText()
                else
                    conn.errorStream?.bufferedReader()?.readText() ?: "(no body)"
                ApiResult(code in 200..299, code, body)
            } catch (e: Exception) {
                ApiResult(false, -1, "Hata: ${e.message}")
            }
        }

    // ---- Connection test ----
    suspend fun testConnection(context: Context): ApiResult = get(context, "licensePlates?\$top=1")

    /** Bound actions that return Edm.String wrap the result as {"value":"..."}; extract it. */
    fun scalarValue(body: String): String =
        try { JSONObject(body).optString("value") } catch (e: Exception) { "" }

    /** Pull a human-readable message out of a BC error body (or fall back to raw). */
    fun errorMessage(body: String): String =
        try {
            JSONObject(body).getJSONObject("error").optString("message").ifBlank { body }
        } catch (e: Exception) {
            body.take(300)
        }

    // ---- Helper: JSON value array parse ----
    fun parseValueArray(body: String): List<JSONObject> {
        return try {
            val arr = JSONObject(body).getJSONArray("value")
            (0 until arr.length()).map { arr.getJSONObject(it) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    // ---- Environment / company discovery (after email sign-in) ----
    data class Company(val id: String, val name: String, val displayName: String)
    data class EnvCompanies(val environment: String, val companies: List<Company>)

    /** Probes each known environment with the token; returns those that respond with companies. */
    suspend fun discoverEnvironments(token: String): List<EnvCompanies> = withContext(Dispatchers.IO) {
        KNOWN_ENVIRONMENTS.mapNotNull { env ->
            val r = httpGet(companiesUrl(env), token)
            if (!r.ok) return@mapNotNull null
            val companies = parseValueArray(r.body).map {
                Company(it.optString("id"), it.optString("name"), it.optString("displayName").ifBlank { it.optString("name") })
            }
            if (companies.isEmpty()) null else EnvCompanies(env, companies)
        }
    }

    /** Plain authenticated GET with an explicit token (used by discovery / sign-in verification). */
    suspend fun httpGet(url: String, token: String): ApiResult = withContext(Dispatchers.IO) {
        try {
            val conn = (URL(url.replace(" ", "%20")).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("Accept", "application/json")
                connectTimeout = 15000; readTimeout = 20000
            }
            val code = conn.responseCode
            val body = if (code in 200..299) conn.inputStream.bufferedReader().readText()
                else conn.errorStream?.bufferedReader()?.readText() ?: "(no body)"
            ApiResult(code in 200..299, code, body)
        } catch (e: Exception) { ApiResult(false, -1, "Hata: ${e.message}") }
    }
}
