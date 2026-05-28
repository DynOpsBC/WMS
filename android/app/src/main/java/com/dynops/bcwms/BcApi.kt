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
    const val ENVIRONMENT = "CustomerSandbox"
    const val COMPANY_ID = "e83a57e9-38c9-f011-8542-6045bd6aeb9e"
    const val COMPANY_NAME = "Demo Business Central"

    private const val PREFS = "bcwms_prefs"
    private const val KEY_TOKEN = "bc_access_token"

    private fun customApiBase() =
        "https://api.businesscentral.dynamics.com/v2.0/$TENANT/$ENVIRONMENT/api/dynops/warehouse/v2.0/companies($COMPANY_ID)"

    private fun standardApiBase() =
        "https://api.businesscentral.dynamics.com/v2.0/$TENANT/$ENVIRONMENT/api/v2.0/companies($COMPANY_ID)"

    // ---- Token persistence ----
    fun saveToken(context: Context, token: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_TOKEN, token.trim()).apply()
    }

    fun getToken(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_TOKEN, "") ?: ""

    fun hasToken(context: Context): Boolean = getToken(context).isNotBlank()

    fun clearToken(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().remove(KEY_TOKEN).apply()
    }

    // ---- HTTP ----
    data class ApiResult(val ok: Boolean, val httpCode: Int, val body: String)

    suspend fun get(context: Context, path: String): ApiResult = request(context, "GET", path, null)

    suspend fun getWithStandardFallback(context: Context, path: String): ApiResult {
        val custom = get(context, path)
        if (custom.httpCode != 404) return custom
        return request(context, "GET", "${standardApiBase()}/$path", null)
    }

    suspend fun getWithStandardFallback(context: Context, customPath: String, standardPath: String): ApiResult {
        val custom = get(context, customPath)
        if (custom.httpCode != 404) return custom
        return request(context, "GET", "${standardApiBase()}/$standardPath", null)
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
                val rawUrl = if (path.startsWith("http")) path else "${customApiBase()}/$path"
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
}
