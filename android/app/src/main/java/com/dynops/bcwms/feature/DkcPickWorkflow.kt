package com.dynops.bcwms.feature

import com.dynops.bcwms.ui.pickLineCapacity
import org.json.JSONObject
import kotlin.math.abs

/**
 * DKÇ parçalı toplama (18 Kas 2026): mal kabuldeki parçalı kabulün toplama karşılığı.
 *
 * BC, toplama belgesi oluşurken "Qty. to Handle" alanını kalan miktarla ÖNCEDEN
 * doldurur; bu yüzden alanın dolu olması "operatör bu satırı topladı" demek
 * değildir. Operatörün bu cihazda girdiği miktarlar ayrıca tutulur ve kayıt
 * yalnız bu satırları kapsar; dokunulmayan satırlar kayıttan önce sıfırlanır,
 * kalan miktar belgede kalır.
 */
internal const val PICK_QTY_EPSILON = 0.00001

/**
 * Operatörün bir Take satırına girdiği miktar. [handledAtEntry] girişin yapıldığı
 * andaki "Qty. Handled" değeridir: satır başka bir yerden (BC ya da diğer
 * terminal) kaydedilince değişir ve giriş geçersiz sayılır — yanıtı kaybolan
 * bir kayıttan sonra kalan miktar "girilmiş" gibi görünüp ikinci kez
 * kaydedilemesin.
 */
internal data class PickEntry(val qty: Double, val handledAtEntry: Double)

internal fun pickTakeLines(lines: List<JSONObject>): List<JSONObject> =
    lines.filter { !BcEnum.decodeOData(it.optString("actionType")).equals("Place", ignoreCase = true) }

/** Operatörün girdiği ve sunucudaki satırla hâlâ birebir örtüşen miktar; yoksa 0. */
internal fun pickEnteredQty(line: JSONObject, entries: Map<Int, PickEntry>): Double {
    val entry = entries[line.optInt("lineNo")] ?: return 0.0
    if (entry.qty <= PICK_QTY_EPSILON) return 0.0
    val serverQty = line.optDouble("qtyToHandle", 0.0)
    val serverHandled = line.optDouble("qtyHandled", 0.0)
    val same = abs(serverQty - entry.qty) < PICK_QTY_EPSILON &&
        abs(serverHandled - entry.handledAtEntry) < PICK_QTY_EPSILON
    return if (same) entry.qty else 0.0
}

/** Satırın kalanının tamamı girildi. */
internal fun pickRowDone(line: JSONObject, entries: Map<Int, PickEntry>): Boolean {
    val entered = pickEnteredQty(line, entries)
    return entered > 0.0 && entered >= pickLineCapacity(line) - PICK_QTY_EPSILON
}

/** Satırın kalanının yalnız bir kısmı girildi. */
internal fun pickRowPartial(line: JSONObject, entries: Map<Int, PickEntry>): Boolean {
    val entered = pickEnteredQty(line, entries)
    return entered > 0.0 && entered < pickLineCapacity(line) - PICK_QTY_EPSILON
}

/** Kaydedilecek satırlar: operatörün miktar girdiği Take satırları. */
internal fun pickPostLines(takeLines: List<JSONObject>, entries: Map<Int, PickEntry>): List<JSONObject> =
    takeLines.filter { pickEnteredQty(it, entries) > 0.0 }

/**
 * Kayıttan önce sıfırlanması gereken satırlar: operatör miktar girmemiş ama
 * sunucuda "Qty. to Handle" dolu (BC varsayılanı). Sıfırlanmazsa kayıt bu
 * satırları da toplanmış sayar.
 */
internal fun pickLinesToClear(takeLines: List<JSONObject>, entries: Map<Int, PickEntry>): List<JSONObject> =
    takeLines.filter { pickEnteredQty(it, entries) <= 0.0 && it.optDouble("qtyToHandle", 0.0) > PICK_QTY_EPSILON }

/**
 * Kayıttan hemen önceki son kontrol: sunucudaki her Take satırının miktarı,
 * operatörün girdiğine (girmediyse 0'a) eşit olmalı. Uymayan satır numaraları döner.
 */
internal fun pickPostMismatches(takeLines: List<JSONObject>, entries: Map<Int, PickEntry>): List<Int> =
    takeLines.filter {
        abs(it.optDouble("qtyToHandle", 0.0) - pickEnteredQty(it, entries)) >= PICK_QTY_EPSILON
    }.map { it.optInt("lineNo") }

/** Sunucuyla artık örtüşmeyen (kaydedilmiş, değişmiş ya da silinmiş satıra ait) girişleri atar. */
internal fun prunePickEntries(takeLines: List<JSONObject>, entries: Map<Int, PickEntry>): Map<Int, PickEntry> {
    val valid = takeLines.filter { pickEnteredQty(it, entries) > 0.0 }.map { it.optInt("lineNo") }.toSet()
    return entries.filterKeys { it in valid }
}

internal fun encodePickEntries(entries: Map<Int, PickEntry>): String =
    entries.entries.sortedBy { it.key }.joinToString(";") { "${it.key}:${it.value.qty}:${it.value.handledAtEntry}" }

internal fun decodePickEntries(raw: String): Map<Int, PickEntry> =
    raw.split(';').mapNotNull { part ->
        val f = part.trim().split(':')
        if (f.size != 3) return@mapNotNull null
        val lineNo = f[0].toIntOrNull() ?: return@mapNotNull null
        val qty = f[1].toDoubleOrNull()?.takeIf { it.isFinite() && it > 0.0 } ?: return@mapNotNull null
        val handled = f[2].toDoubleOrNull()?.takeIf { it.isFinite() } ?: return@mapNotNull null
        lineNo to PickEntry(qty, handled)
    }.toMap()

/** Girilen miktarlar cihazda saklanır: ekrandan çıkıp dönünce hazırlanan satırlar unutulmasın. */
internal object PickEntryStore {
    private const val PREFS = "bcwms_pick_entries"
    fun load(context: android.content.Context, no: String): Map<Int, PickEntry> =
        runCatching {
            decodePickEntries(
                context.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE).getString("pick:$no", "").orEmpty(),
            )
        }.getOrDefault(emptyMap())

    fun save(context: android.content.Context, no: String, entries: Map<Int, PickEntry>) {
        runCatching {
            val editor = context.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE).edit()
            if (entries.isEmpty()) editor.remove("pick:$no") else editor.putString("pick:$no", encodePickEntries(entries))
            editor.apply()
        }
    }
}
