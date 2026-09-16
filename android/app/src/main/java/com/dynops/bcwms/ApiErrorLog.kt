package com.dynops.bcwms

import android.content.Context
import com.dynops.bcwms.ui.operatorSupportReference
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Son başarısız BC isteklerinin cihaz içi kaydı.
 *
 * Operatör ekranı ham BC hatasını göstermez, yalnız REF-… kodu verir. BADE
 * LP000025 (16 Eyl 2026): kod logcat olmadan çözülemiyor, yönetici sahada
 * nedeni göremiyordu. Bu liste Yardım ekranında "Son hata kayıtları" olarak
 * açılır; REF kodu burada ham BC metniyle eşleşir. Token/başlık tutulmaz.
 */
object ApiErrorLog {
    data class Entry(
        val atMillis: Long,
        val ref: String,
        val httpCode: Int,
        val method: String,
        val path: String,
        val message: String,
    ) {
        val timeLabel: String
            get() = SimpleDateFormat("dd.MM HH:mm:ss", Locale("tr")).format(Date(atMillis))
    }

    const val MAX_ENTRIES = 30
    private const val PREFS = "bcwms_api_errors"
    private const val KEY = "entries"
    private const val MAX_MESSAGE = 1500

    private val entries = ArrayDeque<Entry>()
    private var loaded = false

    /** REF kodu operatör ekranındakiyle aynı formülle üretilir (Common.operatorSupportReference). */
    fun refFor(message: String, httpCode: Int): String = operatorSupportReference(message, httpCode)

    @Synchronized
    fun record(context: Context?, method: String, path: String, httpCode: Int, message: String): Entry {
        if (context != null) ensureLoaded(context)
        val clean = message.trim().take(MAX_MESSAGE)
        val entry = Entry(System.currentTimeMillis(), refFor(message, httpCode), httpCode, method, path, clean)
        push(entry)
        if (context != null) persist(context)
        return entry
    }

    /** Test ve bellek-içi kullanım: kapasite aşımında en eski kayıt düşer. */
    @Synchronized
    internal fun push(entry: Entry) {
        entries.addFirst(entry)
        while (entries.size > MAX_ENTRIES) entries.removeLast()
    }

    @Synchronized
    fun entries(context: Context?): List<Entry> {
        if (context != null) ensureLoaded(context)
        return entries.toList()
    }

    @Synchronized
    fun clear(context: Context?) {
        entries.clear()
        loaded = true
        if (context != null) runCatching { context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY).apply() }
    }

    private fun ensureLoaded(context: Context) {
        if (loaded) return
        loaded = true
        runCatching {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return
            val arr = JSONArray(raw)
            val restored = (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                Entry(
                    o.optLong("at"), o.optString("ref"), o.optInt("code"),
                    o.optString("method"), o.optString("path"), o.optString("message"),
                )
            }
            // Bellekte zaten olanlar (bu süreçte kaydedilenler) en yeni; diskten gelenler arkaya.
            val inMemory = entries.toList()
            entries.clear()
            (inMemory + restored).take(MAX_ENTRIES).forEach { entries.addLast(it) }
        }
    }

    private fun persist(context: Context) {
        runCatching {
            val arr = JSONArray()
            entries.forEach { e ->
                arr.put(
                    JSONObject().put("at", e.atMillis).put("ref", e.ref).put("code", e.httpCode)
                        .put("method", e.method).put("path", e.path).put("message", e.message),
                )
            }
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, arr.toString()).apply()
        }
    }
}
