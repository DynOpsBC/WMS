package com.dynops.bcwms.feature

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.dynops.bcwms.BcApi
import com.dynops.bcwms.ui.WmsGlyph
import com.dynops.bcwms.ui.WmsIcon
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

// Kitoko (21 Eki 2026): "terminalden hangi etiket tasarımıyla basılacağını seçeyim".
// BADE (25 Eki 2026): Kitoko hattından alındı; ürün, raf ve LP etiketinde kullanılır.
// BC'de kayıtlı Etiket Tasarımları (labelLayouts) türüne göre listelenir; seçim
// cihazda tür ve şirket başına hatırlanır. Varsayılan = BC'de aktif tasarım, yani
// eski aksiyonlar (printLabel/printLabels) aynen kullanılır. Tasarım seçilince
// *WithLayout aksiyonlarına layoutCode gider. BC eskiyse (labelLayouts 404) seçici
// hiç görünmez.

/** BC "DOPSWHS Label Kind" enum değer adları (API'de labelKind). */
internal enum class LabelLayoutKind(val bcName: String) {
    Item("Item"),
    Bin("Bin"),
    Zone("Zone"),
    LP("LP"),
    // Kitoko (22 Eki 2026): lot etiketi (BC 1.14.3.17+); eski BC'de bu türde tasarım yok → gizli.
    Lot("Lot"),
}

internal data class LabelLayoutOption(
    val code: String,
    val description: String,
    val kind: String,
    val widthMm: Double,
    val heightMm: Double,
    val dpi: Int,
    val active: Boolean,
)

internal const val LABEL_LAYOUT_DEFAULT_TITLE = "Varsayılan (BC'de aktif)"
internal const val LABEL_LAYOUTS_PATH = "labelLayouts?\$orderby=code&\$top=200"

internal sealed interface LabelLayoutLoad {
    data object NotLoaded : LabelLayoutLoad
    data object Loading : LabelLayoutLoad
    /** BC bu sürümü tanımıyor (404) ya da bu türde tasarım yok: seçici gizli, eski aksiyonlar. */
    data object Hidden : LabelLayoutLoad
    /** Liste okunamadı (ağ/geçici hata): seçici gizli, hatırlanan tasarım kullanılmaya devam eder. */
    data object Failed : LabelLayoutLoad
    data class Ready(val options: List<LabelLayoutOption>) : LabelLayoutLoad
}

internal fun parseLabelLayoutOptions(rows: List<JSONObject>): List<LabelLayoutOption> =
    rows.mapNotNull { row ->
        val code = row.optString("code").trim().takeIf { it.isNotEmpty() } ?: return@mapNotNull null
        LabelLayoutOption(
            code = code,
            description = row.optString("description").trim(),
            kind = row.optString("labelKind").trim(),
            widthMm = row.optDouble("widthMm", 0.0).takeUnless { it.isNaN() } ?: 0.0,
            heightMm = row.optDouble("heightMm", 0.0).takeUnless { it.isNaN() } ?: 0.0,
            dpi = row.optInt("dpi", 0),
            active = row.optBoolean("active", false),
        )
    }

/** labelLayouts yanıtından bu türün seçici durumu; 404 = eski BC → gizli. */
internal fun labelLayoutsLoad(kind: LabelLayoutKind, page: BcApi.PagedItemsResult): LabelLayoutLoad {
    if (!page.complete) return if (page.error?.httpCode == 404) LabelLayoutLoad.Hidden else LabelLayoutLoad.Failed
    val options = parseLabelLayoutOptions(page.rows).filter { it.kind.equals(kind.bcName, ignoreCase = true) }
    return if (options.isEmpty()) LabelLayoutLoad.Hidden else LabelLayoutLoad.Ready(options)
}

/** "80", "101,6": ölçü sondaki sıfırlar olmadan, Türkçe ondalık virgülle. */
internal fun labelLayoutMm(value: Double): String {
    val rounded = Math.round(value * 10) / 10.0
    return if (rounded == Math.floor(rounded)) rounded.toLong().toString()
    else rounded.toString().replace('.', ',')
}

/** Seçicide görünen ad: "Ürün V2 · 80×40". */
internal fun labelLayoutOptionTitle(option: LabelLayoutOption): String {
    val name = option.description.ifBlank { option.code }
    if (option.widthMm <= 0.0 || option.heightMm <= 0.0) return name
    return "$name · ${labelLayoutMm(option.widthMm)}×${labelLayoutMm(option.heightMm)}"
}

/** Hatırlanan kod listede yoksa (silinmiş/başka tür) varsayılana döner. */
internal fun rememberedLabelLayout(remembered: String, load: LabelLayoutLoad): String = when (load) {
    is LabelLayoutLoad.Ready -> load.options.firstOrNull { it.code.equals(remembered.trim(), ignoreCase = true) }?.code.orEmpty()
    LabelLayoutLoad.Failed -> remembered.trim()
    else -> ""
}

/** Baskıda gönderilecek tasarım; boş = varsayılan (eski aksiyon). */
internal fun effectiveLabelLayoutCode(load: LabelLayoutLoad, selectedCode: String): String = when (load) {
    is LabelLayoutLoad.Ready -> load.options.firstOrNull { it.code == selectedCode }?.code.orEmpty()
    LabelLayoutLoad.Failed -> selectedCode
    else -> ""
}

/** printLabel → printLabelWithLayout, printLabels → printLabelsWithLayout; boş tasarımda eski aksiyon. */
internal fun labelPrintAction(layoutCode: String, defaultAction: String = "printLabel"): String =
    if (layoutCode.isBlank()) defaultAction else defaultAction + "WithLayout"

/** Eski aksiyonun gövdesi aynen; tasarım seçiliyse layoutCode eklenir. */
internal fun labelPrintPayload(printerId: String, copies: Int, layoutCode: String): String =
    JSONObject().put("printerId", printerId).put("copies", copies)
        .apply { if (layoutCode.isNotBlank()) put("layoutCode", layoutCode) }
        .toString()

internal const val LP_LABEL_WITH_LAYOUT_ACTION = "printLabelWithLayout"

/** LP listesinde yalnız boş LP'nin LP etiketi (printLabel) tasarıma uyar; MTE ve belge yolu değişmez. */
internal fun lpLabelRouteWithLayout(route: LpPrintRoute, layoutCode: String): LpPrintRoute =
    if (route.action == "printLabel" && layoutCode.isNotBlank()) route.copy(action = LP_LABEL_WITH_LAYOUT_ACTION) else route

/** Başarı mesajına eklenen kısa not; varsayılanda boş. */
internal fun labelLayoutNote(layoutCode: String): String =
    if (layoutCode.isBlank()) "" else " Tasarım: $layoutCode."

internal fun labelLayoutPrefKey(scope: String, kind: LabelLayoutKind): String =
    "bcwms.labelLayout.$scope:${kind.bcName}"

/** Son seçilen tasarım; cihazda tür ve şirket (tenant/ortam/şirket) başına. */
internal object LabelLayoutPrefs {
    private fun prefs(context: Context) = context.getSharedPreferences("bcwms_prefs", Context.MODE_PRIVATE)
    private fun key(context: Context, kind: LabelLayoutKind) = labelLayoutPrefKey(TerminalSession.scope(context), kind)

    fun get(context: Context, kind: LabelLayoutKind): String =
        prefs(context).getString(key(context, kind), "").orEmpty()

    fun set(context: Context, kind: LabelLayoutKind, code: String) {
        val editor = prefs(context).edit()
        if (code.isBlank()) editor.remove(key(context, kind)) else editor.putString(key(context, kind), code)
        editor.apply()
    }
}

/**
 * Ekran ömrü boyunca bir etiket türünün tasarım seçimi. Liste ilk gösterimde
 * (ya da baskıdan hemen önce [awaitLayoutCode] ile) bir kez okunur.
 */
@Stable
internal class LabelLayoutChoice(val kind: LabelLayoutKind) {
    var load by mutableStateOf<LabelLayoutLoad>(LabelLayoutLoad.NotLoaded)
        private set
    var selectedCode by mutableStateOf("")
        private set
    private val mutex = Mutex()

    val layoutCode: String get() = effectiveLabelLayoutCode(load, selectedCode)

    suspend fun ensureLoaded(context: Context) {
        mutex.withLock {
            if (load is LabelLayoutLoad.Ready || load == LabelLayoutLoad.Hidden) return
            load = LabelLayoutLoad.Loading
            val result = try {
                labelLayoutsLoad(kind, BcApi.getAllPages(context, LABEL_LAYOUTS_PATH, maxPages = 5))
            } catch (cancelled: CancellationException) {
                load = LabelLayoutLoad.NotLoaded
                throw cancelled
            } catch (_: Exception) {
                LabelLayoutLoad.Failed
            }
            selectedCode = rememberedLabelLayout(LabelLayoutPrefs.get(context, kind), result)
            load = result
        }
    }

    /** Baskıdan önce: liste yükleniyorsa bitmesini bekler, sonra gönderilecek kodu verir. */
    suspend fun awaitLayoutCode(context: Context): String {
        ensureLoaded(context)
        return layoutCode
    }

    fun select(context: Context, code: String) {
        selectedCode = code
        LabelLayoutPrefs.set(context, kind, code)
    }
}

@Composable
internal fun rememberLabelLayoutChoice(kind: LabelLayoutKind): LabelLayoutChoice = remember(kind) { LabelLayoutChoice(kind) }

/**
 * Kompakt "Etiket tasarımı" satırı: dokununca açılan listede önce
 * "Varsayılan (BC'de aktif)", sonra bu türün tasarımları. Eski BC'de veya bu
 * türde tasarım yoksa hiçbir şey çizmez.
 */
@Composable
internal fun LabelLayoutSelector(
    choice: LabelLayoutChoice,
    enabled: Boolean = true,
    note: String = "",
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    LaunchedEffect(choice) { choice.ensureLoaded(context) }
    val ready = choice.load as? LabelLayoutLoad.Ready
    if (ready != null) {
        var open by remember { mutableStateOf(false) }
        val selected = ready.options.firstOrNull { it.code == choice.layoutCode }
        Box(modifier.fillMaxWidth()) {
            Surface(
                onClick = { open = true },
                enabled = enabled,
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Etiket tasarımı seç" },
            ) {
                Row(
                    Modifier.padding(start = 12.dp, end = 12.dp, top = 8.dp, bottom = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    WmsIcon(WmsGlyph.PRINTER, MaterialTheme.colorScheme.primary, Modifier.size(22.dp))
                    Column(Modifier.weight(1f)) {
                        Text("Etiket tasarımı", style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(selected?.let(::labelLayoutOptionTitle) ?: LABEL_LAYOUT_DEFAULT_TITLE,
                            style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (note.isNotBlank()) Text(note, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text("Değiştir", style = MaterialTheme.typography.labelLarge,
                        color = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            DropdownMenu(expanded = open && enabled, onDismissRequest = { open = false }) {
                LabelLayoutMenuItem(LABEL_LAYOUT_DEFAULT_TITLE, selected == null) {
                    choice.select(context, ""); open = false
                }
                ready.options.forEach { option ->
                    LabelLayoutMenuItem(labelLayoutOptionTitle(option), option.code == selected?.code) {
                        choice.select(context, option.code); open = false
                    }
                }
            }
        }
    }
}

@Composable
private fun LabelLayoutMenuItem(title: String, selected: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(title, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal) },
        leadingIcon = { RadioButton(selected = selected, onClick = null) },
        onClick = onClick,
    )
}
