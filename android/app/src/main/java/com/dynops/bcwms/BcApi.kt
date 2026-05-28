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

    private suspend fun request(context: Context, method: String, path: String, jsonBody: String?): ApiResult =
        withContext(Dispatchers.IO) {
            val token = getToken(context)
            if (token.isBlank()) return@withContext ApiResult(false, 0, "Token yok — Connection ekranindan token girin")
            try {
                val rawUrl = if (path.startsWith("http")) path else "${customApiBase()}/$path"
                val url = URL(rawUrl.replace(" ", "%20").replace("'", "%27"))
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = method
                    setRequestProperty("Authorization", "Bearer $token")
                    setRequestProperty("Accept", "application/json")
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
