package com.dynops.bcwms

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * Business Central SaaS API client.
 * Token bir kez girilir, SharedPreferences'ta kalici saklanir, tum ekranlar otomatik kullanir.
 */
object BcApi {
    // Multi-tenant: uygulama artık tek bir tenant'a sabitlenmez. Giriş
    // "common" authority ile yapılır (aşağıda DeviceAuth), gerçek tenant ID
    // token'dan (tid claim) çıkarılıp cihaza kaydedilir; tüm BC API çağrıları
    // o kayıtlı tenant'ı kullanır. Böylece her müşteri için ayrı APK gerekmez.
    // FALLBACK_TENANT yalnızca token okunamazsa / geçiş dönemindeki eski
    // kurulumlar için — DynamicsOps sandbox'ı.
    val FALLBACK_TENANT = BuildConfig.BC_FALLBACK_TENANT
    // Multi-tenant public client. AzureADMultipleOrgs olarak kayıtlı olmalı;
    // her müşteri yöneticisi kendi tenant'ında bu client'a onay verir.
    val CLIENT_ID = BuildConfig.BC_CLIENT_ID  // Tenant flavor public client (device-code)
    const val BC_RESOURCE = "https://api.businesscentral.dynamics.com"

    // Defaults (used until the user picks an environment/company after email sign-in).
    val DEFAULT_ENVIRONMENT = BuildConfig.BC_DEFAULT_ENVIRONMENT
    const val DEFAULT_COMPANY_ID = "1534369d-f248-f111-b478-7c1e521cfdf0"
    const val DEFAULT_COMPANY_NAME = "CRONUS USA, Inc."

    /** Sign-in sonrası yoklanan ortam adları. Multi-tenant: her müşterinin
     *  ortam adı farklı olabildiğinden en yaygın adlar denenir; bulunamazsa
     *  kullanıcı LoginFlow'da ortam adını elle girebilir (probeEnvironment). */
    val KNOWN_ENVIRONMENTS = buildList {
        add(DEFAULT_ENVIRONMENT)
        addAll(listOf("Sandbox", "SandboxUS", "CustomerSandbox"))
        if (BuildConfig.BC_ALLOW_PRODUCTION) add("Production")
    }.distinct()

    private const val PREFS = "bcwms_prefs"
    private const val KEY_TOKEN = "bc_access_token"
    private const val KEY_REFRESH = "bc_refresh_token"
    private const val KEY_EXPIRY = "bc_token_expiry_ms"
    private const val KEY_ENV = "bc_environment"
    private const val KEY_COMPANY_ID = "bc_company_id"
    private const val KEY_COMPANY_NAME = "bc_company_name"
    private const val KEY_LOCAL_USER = "local_user_id"
    private const val KEY_LOCAL_PROFILE = "local_user_profile_json"
    private const val KEY_BC_USER = "bc_user_id"
    private const val KEY_TENANT = "bc_tenant_id"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ---- Tenant (runtime, multi-tenant) ----
    /** Kayıtlı tenant ID; henüz giriş yapılmadıysa fallback (eski davranış). */
    fun getTenant(context: Context): String = prefs(context).getString(KEY_TENANT, FALLBACK_TENANT) ?: FALLBACK_TENANT
    fun setTenant(context: Context, tenantId: String) {
        if (tenantId.isNotBlank()) prefs(context).edit().putString(KEY_TENANT, tenantId).apply()
    }

    /**
     * Access token'ın "tid" (tenant id) claim'ini okur ve kaydeder. Giriş
     * başarılı olunca çağrılır — sonraki tüm BC çağrıları doğru tenant'a gider.
     * JWT payload = base64url(2. bölüm); tenant çözülemezse kayıt değişmez.
     */
    fun captureTenantFromToken(context: Context, accessToken: String) {
        val tid = tenantIdFromJwt(accessToken)
        if (!tid.isNullOrBlank()) setTenant(context, tid)
    }

    private fun tenantIdFromJwt(jwt: String): String? = try {
        val parts = jwt.split(".")
        if (parts.size < 2) null else {
            val payload = String(
                android.util.Base64.decode(parts[1], android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP)
            )
            JSONObject(payload).optString("tid").takeIf { it.isNotBlank() }
        }
    } catch (e: Exception) { null }

    // ---- Environment / company selection (runtime-configurable) ----
    fun getEnvironment(context: Context): String = prefs(context).getString(KEY_ENV, DEFAULT_ENVIRONMENT) ?: DEFAULT_ENVIRONMENT
    fun getCompanyId(context: Context): String = prefs(context).getString(KEY_COMPANY_ID, DEFAULT_COMPANY_ID) ?: DEFAULT_COMPANY_ID
    fun getCompanyName(context: Context): String = prefs(context).getString(KEY_COMPANY_NAME, DEFAULT_COMPANY_NAME) ?: DEFAULT_COMPANY_NAME

    fun setEnvironment(context: Context, env: String) { prefs(context).edit().putString(KEY_ENV, env).apply() }
    fun setCompany(context: Context, id: String, name: String) {
        prefs(context).edit().putString(KEY_COMPANY_ID, id).putString(KEY_COMPANY_NAME, name).apply()
    }

    // ---- Multi-company switcher (BADE / BS / ... aynı ortamda) ----
    // ELOG: operatör aynı ortamdaki farklı BC şirketleri arasında login yapmadan
    // geçebilsin. Yalnız erişilebilir (WMS kurulu + operatörün localUser'ı olan)
    // şirketler saklanır; PIM gibi WMS'siz/kullanıcısız şirketler dışarıda kalır.
    private const val KEY_ACCESSIBLE_COMPANIES = "accessible_companies_json"

    /** Girişte hesaplanan erişilebilir şirketleri (aktif ortam için) saklar. */
    fun saveAccessibleCompanies(context: Context, companies: List<Company>) {
        val arr = JSONArray()
        companies.forEach { arr.put(JSONObject().apply { put("id", it.id); put("name", it.name); put("displayName", it.displayName) }) }
        prefs(context).edit().putString(KEY_ACCESSIBLE_COMPANIES, arr.toString()).apply()
    }

    fun getAccessibleCompanies(context: Context): List<Company> {
        val raw = prefs(context).getString(KEY_ACCESSIBLE_COMPANIES, null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).map {
                val o = arr.getJSONObject(it)
                Company(o.optString("id"), o.optString("name"), o.optString("displayName").ifBlank { o.optString("name") })
            }
        }.getOrDefault(emptyList())
    }

    /**
     * Verilen şirket listesinden operatörün erişebildiklerini döndürür.
     * Kriter: o şirketin DOPSWHS WMS API'sinde `localUsers('<username>')` kaydı
     * bulunur (HTTP 200) → WMS kurulu VE kullanıcı var. WMS yok (404 host/app)
     * ya da kullanıcı yok (404) → şirket elenir. Aktif token ile çağrılır.
     */
    suspend fun probeAccessibleCompanies(
        context: Context, env: String, username: String, companies: List<Company>,
    ): List<Company> = withContext(Dispatchers.IO) {
        val token = getToken(context)
        val tenant = getTenant(context)
        val safeUser = java.net.URLEncoder.encode(username.trim().lowercase().replace("'", "''"), "UTF-8")
        // PARALEL yoklama: sıralı filter'da 10 şirket = 10 ardışık istek (~3-6 sn).
        // Hepsi aynı anda gider, süre en yavaş isteğe iner.
        companies.map { c ->
            async {
                val base = "https://api.businesscentral.dynamics.com/v2.0/$tenant/$env/api/dynops/warehouse/v2.0/companies(${c.id})"
                // Önce kullanıcı-bazlı yokla. Operatörün o şirkette localUser kaydı
                // yoksa da şirket ERİŞİLEBİLİR sayılır (WMS kurulu olması yeterli):
                // BC'de tek kullanıcı kaydıyla birden çok şirkete girilebiliyor,
                // eski katı kriter bu şirketleri listeden düşürüyordu.
                val hasUser = httpGet("$base/localUsers('$safeUser')", token).ok
                val wmsInstalled = hasUser || httpGet("$base/localUsers?\$top=1", token).ok
                if (wmsInstalled) c else null
            }
        }.awaitAll().filterNotNull()
    }

    /**
     * WMS kullanıcı adı olmadan (AAD/admin girişi) erişilebilir şirketleri bulur:
     * kriter yalnız "DOPSWHS WMS API'si o şirkette yanıt veriyor" — localUsers
     * entity set'i sorgulanır (HTTP 200 → WMS kurulu). PIM gibi WMS'siz şirketler
     * elenir; kullanıcı-bazlı filtre yoktur (username bilinmiyor).
     */
    suspend fun probeWmsCompanies(
        context: Context, env: String, companies: List<Company>,
    ): List<Company> = withContext(Dispatchers.IO) {
        val token = getToken(context)
        val tenant = getTenant(context)
        // Paralel yoklama (bkz. probeAccessibleCompanies).
        companies.map { c ->
            async {
                val url = "https://api.businesscentral.dynamics.com/v2.0/$tenant/$env/api/dynops/warehouse/v2.0/companies(${c.id})/localUsers?\$top=1"
                if (httpGet(url, token).ok) c else null
            }
        }.awaitAll().filterNotNull()
    }

    /**
     * Erişilebilir şirket listesi boşsa (ör. login akışı switcher eklenmeden
     * yapılmış) mevcut ortamdaki tüm şirketleri çekip WMS kurulu olanları
     * hesaplar ve saklar. Home ekranı ilk açılışta çağırır. Zaten liste doluysa
     * ya da token yoksa no-op. Sonuç doluysa true döner (UI tazelemek için).
     */
    suspend fun refreshAccessibleCompaniesIfEmpty(context: Context): Boolean {
        if (getAccessibleCompanies(context).isNotEmpty()) return false
        return rediscoverAccessibleCompanies(context)
    }

    /**
     * Erişilebilir şirketleri KOŞULSUZ yeniden keşfeder ve kaydeder.
     * Şirket değiştirici her açıldığında çağrılır: kayıtlı liste eski olabilir
     * (yeni şirket eklenmiş ya da ilk keşif tek şirketle sonuçlanmış olabilir).
     * Dönüş: birden çok şirkete erişim var mı.
     */
    suspend fun rediscoverAccessibleCompanies(context: Context): Boolean = withContext(Dispatchers.IO) {
        val token = getToken(context)
        if (token.isBlank()) return@withContext false
        val tenant = getTenant(context)
        val env = getEnvironment(context)
        val r = httpGet(companiesUrl(tenant, env), token)
        if (!r.ok) return@withContext false
        val all = parseValueArray(r.body).map {
            Company(it.optString("id"), it.optString("name"), it.optString("displayName").ifBlank { it.optString("name") })
        }
        // WMS operatörü girişliyse kullanıcı-bazlı, değilse yalnız WMS-kurulu filtresi.
        val localUser = getLocalUser(context)
        val accessible = if (localUser.isNotBlank())
            runCatching { probeAccessibleCompanies(context, env, localUser, all) }.getOrDefault(emptyList())
        else
            runCatching { probeWmsCompanies(context, env, all) }.getOrDefault(emptyList())
        val result = accessible.ifEmpty {
            listOf(Company(getCompanyId(context), getCompanyName(context), getCompanyName(context)))
        }
        saveAccessibleCompanies(context, result)
        result.size > 1
    }

    private fun customApiBase(context: Context) =
        "https://api.businesscentral.dynamics.com/v2.0/${getTenant(context)}/${getEnvironment(context)}/api/dynops/warehouse/v2.0/companies(${getCompanyId(context)})"

    private fun standardApiBase(context: Context) =
        "https://api.businesscentral.dynamics.com/v2.0/${getTenant(context)}/${getEnvironment(context)}/api/v2.0/companies(${getCompanyId(context)})"

    /** Standard companies endpoint — discovery için tenant'ı açıkça alır (giriş
     *  anında henüz kayıtlı değildir; token'dan çözülüp buraya geçirilir). */
    fun companiesUrl(tenant: String, env: String) =
        "https://api.businesscentral.dynamics.com/v2.0/$tenant/$env/api/v2.0/companies?\$select=id,name,displayName"

    // ---- Token persistence ----
    fun saveToken(context: Context, token: String) {
        val t = token.trim()
        prefs(context).edit().putString(KEY_TOKEN, t).apply()
        // Multi-tenant: her token kaydında gerçek tenant'ı (tid claim) yakala —
        // device-code, ROPC, refresh ve manuel token-paste yollarının hepsi
        // buradan geçtiği için tek noktada doğru tenant sabitlenir.
        captureTenantFromToken(context, t)
    }

    fun getToken(context: Context): String = prefs(context).getString(KEY_TOKEN, "") ?: ""

    fun hasToken(context: Context): Boolean = getToken(context).isNotBlank()

    // Çıkış: tenant/env/company da temizlenir — farklı müşteri hesabıyla
    // yeniden girildiğinde eski tenant'a takılıp kalmayı önler (multi-tenant).
    fun clearToken(context: Context) {
        prefs(context).edit()
            .remove(KEY_TOKEN).remove(KEY_REFRESH).remove(KEY_BC_USER)
            .remove(KEY_TENANT).remove(KEY_ENV).remove(KEY_COMPANY_ID).remove(KEY_COMPANY_NAME)
            .remove(KEY_ACCESSIBLE_COMPANIES)
            .apply()
    }

    fun saveRefreshToken(context: Context, token: String) {
        if (token.isBlank()) return
        prefs(context).edit().putString(KEY_REFRESH, token.trim()).apply()
    }

    fun getRefreshToken(context: Context): String = prefs(context).getString(KEY_REFRESH, "") ?: ""

    /** Persists the absolute epoch-ms at which the current access token expires. */
    fun saveTokenExpiry(context: Context, expiresInSec: Int) {
        val at = System.currentTimeMillis() + expiresInSec * 1000L
        prefs(context).edit().putLong(KEY_EXPIRY, at).apply()
    }

    private fun tokenExpiryMs(context: Context): Long = prefs(context).getLong(KEY_EXPIRY, 0L)

    /**
     * Proactively renews the access token when it is within [skewMs] of expiry (or already
     * expired) and a refresh token is available. Runs before each request so an operator's
     * session lasts as long as the AAD refresh token (hours → all shift), not the ~1h access
     * token. Silent no-op when there is nothing to refresh or the refresh is rejected — the
     * request then proceeds and the reactive 401 path is the final fallback.
     */
    private fun ensureFreshToken(context: Context, skewMs: Long = 5 * 60 * 1000L) {
        val expiry = tokenExpiryMs(context)
        if (expiry == 0L || System.currentTimeMillis() < expiry - skewMs) return
        synchronized(this) {
            // Re-check inside the lock: another thread may have just refreshed.
            if (System.currentTimeMillis() < tokenExpiryMs(context) - skewMs) return
            val rt = getRefreshToken(context)
            if (rt.isBlank()) return
            val refreshed = DeviceAuth.refreshAccessToken(rt, getTenant(context)) ?: return
            saveToken(context, refreshed.first)
            saveRefreshToken(context, refreshed.second)
            saveTokenExpiry(context, refreshed.third)
        }
    }

    // ---- Local WMS user (no AAD) overlay ----
    /** Saves the locally-authenticated WMS username + resolved profile JSON. The AAD access token
     * still carries the request to BC; this overlay just tells the app which local persona to
     * display / filter for in the UI. */
    fun saveLocalUser(context: Context, username: String, profileJson: String) {
        prefs(context).edit()
            .putString(KEY_LOCAL_USER, username)
            .putString(KEY_LOCAL_PROFILE, profileJson)
            .apply()
    }
    fun getLocalUser(context: Context): String = prefs(context).getString(KEY_LOCAL_USER, "") ?: ""
    fun getLocalProfileJson(context: Context): String = prefs(context).getString(KEY_LOCAL_PROFILE, "") ?: ""
    fun hasLocalUser(context: Context): Boolean = getLocalUser(context).isNotBlank()
    fun clearLocalUser(context: Context) {
        prefs(context).edit().remove(KEY_LOCAL_USER).remove(KEY_LOCAL_PROFILE).apply()
    }

    /**
     * Effective operator identity for "assigned to me" filters: the local WMS username when the
     * operator signed in with a WMS account, otherwise the BC User ID of the AAD token — resolved
     * once via appUserProfiles resolveCurrent and cached until sign-out. BC's "Assigned User ID"
     * fields hold exactly this value, so list filters compare against it. Returns "" when BC is
     * unreachable; callers should then fall back to an unfiltered list.
     */
    suspend fun currentUserId(context: Context): String {
        val local = getLocalUser(context)
        if (local.isNotBlank()) return local
        val cached = prefs(context).getString(KEY_BC_USER, "") ?: ""
        if (cached.isNotBlank()) return cached
        val r = boundAction(context, "appUserProfiles", "DEFAULT", "resolveCurrent")
        if (!r.ok) return ""
        val userId = try { JSONObject(scalarValue(r.body)).optString("userId") } catch (e: Exception) { "" }
        if (userId.isNotBlank()) prefs(context).edit().putString(KEY_BC_USER, userId).apply()
        return userId
    }

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

    private val httpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            // Depo hızı: kopuk/zayıf bağlantıda operatör 20 sn beklemesin.
            // BC normalde <1 sn yanıtlar; bu değerler "gerçekten sorun var"ı
            // hızla ortaya çıkarır, kullanıcı erken hata görüp tekrar dener.
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(12, TimeUnit.SECONDS)
            .writeTimeout(12, TimeUnit.SECONDS)
            // Depoda her okutma bir HTTP çağrısı: TLS el sıkışmasını her seferinde
            // tekrarlamamak için bağlantıları uzun süre havuzda tut (aksi halde
            // her scan'de ~300-600 ms sadece handshake'e gidiyor).
            .connectionPool(okhttp3.ConnectionPool(12, 10, TimeUnit.MINUTES))
            .retryOnConnectionFailure(true)
            // Şirket keşfi gibi paralel yoklamalarda host başına eşzamanlılık
            // varsayılan 5'te sıkışmasın.
            .dispatcher(okhttp3.Dispatcher().apply {
                maxRequests = 32
                maxRequestsPerHost = 16
            })
            .build()
    }

    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()

    private suspend fun request(context: Context, method: String, path: String, jsonBody: String?): ApiResult =
        withContext(Dispatchers.IO) {
            ensureFreshToken(context)
            val token = getToken(context)
            if (token.isBlank()) return@withContext ApiResult(false, 0, "Token yok — Bağlantı Ayarları ekranından token girin")
            try {
                val rawUrl = if (path.startsWith("http")) path else "${customApiBase(context)}/$path"
                val url = rawUrl.replace(" ", "%20").replace("'", "%27")
                // OkHttp sends real PATCH/DELETE verbs. Android's HttpURLConnection cannot do PATCH, and
                // BC's API endpoint ignores the X-HTTP-Method-Override fallback → POST-tunneled PATCH lands
                // as a literal POST to a keyed entity and is rejected with HTTP 405 on line updates.
                val requestBody = when {
                    jsonBody != null -> jsonBody.toRequestBody(jsonMediaType)
                    // OkHttp requires a (possibly empty) body for POST/PATCH/PUT.
                    method == "POST" || method == "PATCH" || method == "PUT" -> ByteArray(0).toRequestBody(jsonMediaType)
                    else -> null
                }
                val builder = Request.Builder()
                    .url(url)
                    .method(method, requestBody)
                    .header("Authorization", "Bearer $token")
                    .header("Accept", "application/json")
                // BC requires If-Match for PATCH/DELETE; "*" skips optimistic-concurrency check.
                if (method == "PATCH" || method == "DELETE") builder.header("If-Match", "*")
                httpClient.newCall(builder.build()).execute().use { resp ->
                    val code = resp.code
                    val body = resp.body?.string().let { if (it.isNullOrEmpty()) "(no body)" else it }
                    if (code != 401) return@use ApiResult(code in 200..299, code, body)
                    // Access token expired (~1h). Try a silent refresh once, then replay the request,
                    // so the operator is not silently logged out mid-shift.
                    val refreshed = synchronized(this@BcApi) {
                        val rt = getRefreshToken(context)
                        if (rt.isBlank()) null else DeviceAuth.refreshAccessToken(rt, getTenant(context))
                    } ?: return@use ApiResult(false, code, body)
                    saveToken(context, refreshed.first)
                    saveRefreshToken(context, refreshed.second)
                    saveTokenExpiry(context, refreshed.third)
                    val retry = builder.header("Authorization", "Bearer ${refreshed.first}").build()
                    httpClient.newCall(retry).execute().use { r2 ->
                        val b2 = r2.body?.string().let { if (it.isNullOrEmpty()) "(no body)" else it }
                        ApiResult(r2.code in 200..299, r2.code, b2)
                    }
                }
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

    /**
     * Token'ın tenant'ında bilinen ortamları yoklar; şirket dönenleri listeler.
     * Multi-tenant: tenant token'dan (tid) çözülür — BADE token'ıyla BADE
     * tenant'ı, DynamicsOps token'ıyla DynamicsOps tenant'ı sorgulanır.
     */
    suspend fun discoverEnvironments(token: String): List<EnvCompanies> = withContext(Dispatchers.IO) {
        val tenant = tenantIdFromJwt(token) ?: FALLBACK_TENANT
        KNOWN_ENVIRONMENTS.mapNotNull { env -> probeEnvironment(tenant, env, token) }
    }

    /** Tek bir ortamı yoklar; şirket dönerse EnvCompanies, yoksa null.
     *  Otomatik keşif ortamı bulamazsa kullanıcının elle girdiği ortam adı için. */
    suspend fun probeEnvironment(tenant: String, env: String, token: String): EnvCompanies? = withContext(Dispatchers.IO) {
        val cleanEnv = env.trim()
        if (!BuildConfig.BC_ALLOW_PRODUCTION && cleanEnv.equals("Production", ignoreCase = true)) {
            return@withContext null
        }
        val r = httpGet(companiesUrl(tenant, cleanEnv), token)
        if (!r.ok) return@withContext null
        val companies = parseValueArray(r.body).map {
            Company(it.optString("id"), it.optString("name"), it.optString("displayName").ifBlank { it.optString("name") })
        }
        if (companies.isEmpty()) null else EnvCompanies(cleanEnv, companies)
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
