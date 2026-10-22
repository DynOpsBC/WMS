package com.dynops.bcwms.layout

import org.json.JSONArray
import org.json.JSONObject

/**
 * BC'de tasarlanan ve terminalLayouts API'sinden gelen geçerli yerleşim.
 * Yerleşim yalnız GİZLER, SIRALAR ve YENİDEN ADLANDIRIR: terminalin kendi
 * yetki kuralları (canOpenOperationalScreen, operatorHomeScreens) her zaman
 * önce uygulanır, yerleşim hiçbir ekranı açmaz.
 */
data class LayoutItem(
    val screen: String,
    val key: String,
    val visible: Boolean = true,
    val sort: Int? = null,
    val label: String? = null,
    val note: String? = null,
    val require: Set<String> = emptySet(),
)

data class TerminalLayout(
    val code: String,
    val version: String,
    val items: Map<String, LayoutItem>,
) {
    fun item(screen: String, key: String): LayoutItem? = items[id(screen, key)]

    /** Bilinmeyen öğe = bugünkü davranış (görünür). Kilitli kutular gizlenemez. */
    fun isVisible(screen: String, key: String): Boolean {
        if (screen == TerminalLayoutCatalog.HOME && key in TerminalLayoutCatalog.lockedTiles) return true
        return item(screen, key)?.visible ?: true
    }

    fun label(screen: String, key: String): String? = item(screen, key)?.label?.trim()?.takeIf { it.isNotEmpty() }
    fun note(screen: String, key: String): String? = item(screen, key)?.note?.trim()?.takeIf { it.isNotEmpty() }
    fun requires(screen: String, key: String, flag: String): Boolean = item(screen, key)?.require?.contains(flag) == true

    /** Önbellek biçimi (parse ile geri okunur). */
    fun toJson(): String {
        val arr = JSONArray()
        items.values.forEach { i ->
            arr.put(JSONObject().apply {
                put("screen", i.screen)
                put("key", i.key)
                put("visible", i.visible)
                i.sort?.let { put("sort", it) }
                i.label?.let { put("label", it) }
                i.note?.let { put("note", it) }
                if (i.require.isNotEmpty()) put("require", JSONArray(i.require.toList()))
            })
        }
        return JSONObject().put("code", code).put("version", version).put("items", arr).toString()
    }

    companion object {
        fun id(screen: String, key: String) = "${screen.uppercase()}|${key.uppercase()}"

        /** layoutJson gövdesini çözer; bozuk veride null (çağıran bugünkü davranışa döner). */
        fun parse(json: String): TerminalLayout? = runCatching {
            val root = JSONObject(json)
            val arr = root.optJSONArray("items") ?: JSONArray()
            val items = LinkedHashMap<String, LayoutItem>()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val screen = o.optString("screen").trim().uppercase()
                val key = o.optString("key").trim().uppercase()
                if (screen.isEmpty() || key.isEmpty()) continue
                val req = o.optJSONArray("require")
                val require = buildSet { if (req != null) for (j in 0 until req.length()) add(req.optString(j).uppercase()) }
                items[id(screen, key)] = LayoutItem(
                    screen = screen,
                    key = key,
                    visible = o.optBoolean("visible", true),
                    sort = if (o.has("sort")) o.optInt("sort") else null,
                    label = o.optString("label").takeIf { o.has("label") },
                    note = o.optString("note").takeIf { o.has("note") },
                    require = require,
                )
            }
            TerminalLayout(root.optString("code"), root.optString("version"), items)
        }.getOrNull()

        /**
         * terminalLayouts yanıtı: {"value":[{"version":"..","layoutJson":"{..}"}]}.
         * Satır yoksa null (yerleşim yok = bugünkü menü).
         */
        fun parseApiResponse(body: String): TerminalLayout? {
            val row = JSONObject(body).optJSONArray("value")?.optJSONObject(0) ?: return null
            val parsed = parse(row.optString("layoutJson")) ?: throw IllegalArgumentException("layoutJson")
            val version = row.optString("version").ifBlank { parsed.version }
            return parsed.copy(version = version)
        }
    }
}

/**
 * Ana menü kategorisindeki kutulara yerleşimi uygular: gizlenenleri çıkarır ve
 * BC sırasına dizer. [layout] null ise liste AYNEN döner. Katalogda olmayan
 * kutular (yeni sürümde eklenmiş) gizlenmez ve kendilerinden önceki kutunun
 * hemen arkasında kalır. Sıralama kararlıdır.
 */
fun <T> applyHomeLayout(tiles: List<T>, layout: TerminalLayout?, keyOf: (T) -> String?): List<T> {
    if (layout == null) return tiles
    val visible = tiles.filter { tile -> keyOf(tile)?.let { layout.isVisible(TerminalLayoutCatalog.HOME, it) } ?: true }
    var previous = Int.MIN_VALUE
    val keyed = visible.map { tile ->
        val key = keyOf(tile)
        val sort = key?.let { layout.item(TerminalLayoutCatalog.HOME, it)?.sort ?: TerminalLayoutCatalog.defaultTileSort(it) } ?: previous
        previous = sort
        tile to sort
    }
    return keyed.sortedBy { it.second }.map { it.first }
}

/** API çağrısının sonucu (saf, birim testli). */
sealed interface LayoutFetchResult {
    /** BC yanıt verdi; layout null = BC'de yerleşim yok. */
    data class Loaded(val layout: TerminalLayout?) : LayoutFetchResult
    /** Eski BC: terminalLayouts uç noktası yok (404). */
    data object NotSupported : LayoutFetchResult
    /** Ağ / yetki / sunucu hatası ya da bozuk gövde. */
    data object Failed : LayoutFetchResult
}

fun classifyLayoutResponse(ok: Boolean, httpCode: Int, body: String): LayoutFetchResult = when {
    ok -> runCatching { LayoutFetchResult.Loaded(TerminalLayout.parseApiResponse(body)) }.getOrDefault(LayoutFetchResult.Failed)
    httpCode == 404 -> LayoutFetchResult.NotSupported
    else -> LayoutFetchResult.Failed
}

/**
 * Önbelleğe yazılacak yerleşim. 404 (eski BC) önbelleği temizler → bugünkü
 * davranış. Geçici hatada son bilinen yerleşim korunur (menü titremesin);
 * hiç önbellek yoksa yine bugünkü davranış.
 */
fun nextCachedLayout(previous: TerminalLayout?, result: LayoutFetchResult): TerminalLayout? = when (result) {
    is LayoutFetchResult.Loaded -> result.layout
    LayoutFetchResult.NotSupported -> null
    LayoutFetchResult.Failed -> previous
}

const val TERMINAL_LAYOUT_REFRESH_MS = 5 * 60 * 1000L

/** Devam ettirmede en fazla 5 dakikada bir sorulur; giriş sonrası [force] ile hemen. */
fun shouldRefreshLayout(lastAttemptAt: Long, now: Long, force: Boolean): Boolean =
    force || lastAttemptAt <= 0L || now < lastAttemptAt || now - lastAttemptAt >= TERMINAL_LAYOUT_REFRESH_MS

/** OData filtresi: yalnız dolu alanlar; tek tırnak kaçışlı. */
fun terminalLayoutsPath(terminalCode: String, userName: String): String {
    fun q(v: String) = v.trim().replace("'", "''")
    val filters = buildList {
        if (terminalCode.isNotBlank()) add("terminalCode eq '${q(terminalCode)}'")
        if (userName.isNotBlank()) add("userName eq '${q(userName)}'")
    }
    return if (filters.isEmpty()) "terminalLayouts" else "terminalLayouts?\$filter=" + filters.joinToString(" and ")
}
