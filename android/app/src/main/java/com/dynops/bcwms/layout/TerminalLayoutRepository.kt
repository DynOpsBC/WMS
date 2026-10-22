package com.dynops.bcwms.layout

import android.content.Context
import androidx.compose.runtime.mutableStateOf
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.feature.TerminalSession
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

/**
 * BC Terminal Ekran Tasarımcısı yerleşimini çeker, şirket bazında
 * SharedPreferences'ta önbelleğe alır ve Compose durumuna yayınlar.
 *
 *  * Giriş/bağlanma sonrası: refresh(force = true)
 *  * Uygulama devam ettirilince: refresh(force = false) → en fazla 5 dk'da bir
 *  * 404 (eski BC, uç nokta yok) ya da hiç önbellek yokken hata → bugünkü menü
 */
object TerminalLayoutRepository {
    private const val PREFS = "bcwms_terminal_layout"
    private val state = mutableStateOf<TerminalLayout?>(null)
    private var loadedScope: String? = null
    private val lastAttempt = HashMap<String, Long>()
    private val mutex = Mutex()

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Şirket kapsamı: aynı cihaz farklı tenant/ortam/şirkete bağlanabilir. */
    fun scope(context: Context): String =
        "${BcApi.getTenant(context)}|${BcApi.getEnvironment(context)}|${BcApi.getCompanyId(context)}"

    /** Geçerli şirketin yerleşimi (Compose içinde okunursa değişince yeniden çizer). */
    fun current(context: Context): TerminalLayout? {
        ensureLoaded(context)
        return state.value
    }

    fun isTileVisible(context: Context, tileKey: String): Boolean =
        current(context)?.isVisible(TerminalLayoutCatalog.HOME, tileKey) ?: true

    /** Ekran düğmesi görünür mü? Yerleşim yoksa her zaman true (bugünkü davranış). */
    fun buttonVisible(context: Context, screen: String, buttonKey: String): Boolean =
        current(context)?.isVisible(screen, buttonKey) ?: true

    private fun ensureLoaded(context: Context) {
        val scope = scope(context)
        if (loadedScope == scope) return
        loadedScope = scope
        state.value = prefs(context).getString("layout.$scope", null)?.let { TerminalLayout.parse(it) }
    }

    suspend fun refresh(context: Context, force: Boolean = false) {
        val app = context.applicationContext
        mutex.withLock {
            val scope = scope(app)
            val now = System.currentTimeMillis()
            if (!shouldRefreshLayout(lastAttempt[scope] ?: 0L, now, force)) return
            lastAttempt[scope] = now
            ensureLoaded(app)
            val previous = state.value
            val result = runCatching {
                val path = terminalLayoutsPath(TerminalSession.code(app), BcApi.getLocalUser(app))
                val response = BcApi.get(app, path)
                classifyLayoutResponse(response.ok, response.httpCode, response.body)
            }.getOrDefault(LayoutFetchResult.Failed)
            val next = nextCachedLayout(previous, result)
            if (result != LayoutFetchResult.Failed) store(app, scope, result, next)
            if (scope(app) == scope && next != previous) state.value = next
        }
    }

    private fun store(context: Context, scope: String, result: LayoutFetchResult, layout: TerminalLayout?) {
        val edit = prefs(context).edit()
        if (layout == null) edit.remove("layout.$scope") else edit.putString("layout.$scope", layout.toJson())
        edit.putString("status.$scope", if (result == LayoutFetchResult.NotSupported) "unsupported" else "ok")
        edit.apply()
    }

    /** Test/çıkış: bellekteki kapsamı unut (önbellek diskte kalır). */
    fun resetMemory() {
        loadedScope = null
        lastAttempt.clear()
        state.value = null
    }
}
