package com.dynops.bcwms.scanner

/**
 * Classifies a scanned barcode string into a warehouse intent.
 *
 * Mirrors the 5 default barcode rules from the AdvWMS spec:
 *   1. EAN-13 (13 digits)            -> Item
 *   2. GS1-128 (FNC / AI prefixes)   -> Item (+ optional Lot / Expiry / Serial parsed from AIs)
 *   3. SSCC-18 (18 digits, AI 00)    -> License Plate
 *   4. B-* prefix                    -> Bin
 *   5. TPL-* prefix                  -> LP Template
 *
 * A document screen declares which [BarcodeKind]s it accepts; [resolve] returns a
 * [ResolvedBarcode] the screen can accept or reject.
 */
enum class BarcodeKind { Item, Bin, Lp, LpTemplate, Lot, Serial, Unknown }

data class ResolvedBarcode(
    val kind: BarcodeKind,
    /** Primary value (item no, bin code, LP no, template code, ...). */
    val value: String,
    /** Raw scanned text. */
    val raw: String,
    /** Extra fields parsed from GS1-128 application identifiers. */
    val itemNo: String? = null,
    val lotNo: String? = null,
    val serialNo: String? = null,
    val expiry: String? = null,
)

object BarcodeIntentResolver {

    fun resolve(raw0: String): ResolvedBarcode {
        val raw = raw0.trim()
        if (raw.isEmpty()) return ResolvedBarcode(BarcodeKind.Unknown, "", raw)

        // Rule 4 & 5: explicit prefixes
        when {
            raw.startsWith("B-", ignoreCase = true) ->
                return ResolvedBarcode(BarcodeKind.Bin, raw, raw)
            raw.startsWith("TPL-", ignoreCase = true) ->
                return ResolvedBarcode(BarcodeKind.LpTemplate, raw, raw)
            raw.startsWith("LP", ignoreCase = true) && raw.drop(2).all { it.isDigit() } && raw.length >= 4 ->
                return ResolvedBarcode(BarcodeKind.Lp, raw, raw)
        }

        // Rule 2: GS1-128 — contains application identifiers like (01), (10), (17), (21) or FNC1 group separators
        if (looksLikeGs1(raw)) {
            return parseGs1(raw)
        }

        // Rule 3: SSCC-18 — 18 digits, often prefixed by AI 00
        val digits = raw.filter { it.isDigit() }
        if (raw.all { it.isDigit() } && raw.length == 18) {
            return ResolvedBarcode(BarcodeKind.Lp, raw, raw)
        }

        // Rule 1: EAN-13 / pure numeric -> item
        if (raw.all { it.isDigit() } && (raw.length == 13 || raw.length == 12 || raw.length == 8)) {
            return ResolvedBarcode(BarcodeKind.Item, raw, raw, itemNo = raw)
        }

        // Default: treat as item code (alphanumeric item no like "1896-S")
        return ResolvedBarcode(BarcodeKind.Item, raw, raw, itemNo = raw)
    }

    private fun looksLikeGs1(raw: String): Boolean {
        if (raw.contains("(01)") || raw.contains("(10)") || raw.contains("(17)") || raw.contains("(21)") || raw.contains("(00)")) return true
        // FNC1 group separator (GS, ASCII 29) present
        if (raw.contains('\u001D')) return true
        return false
    }

    /** Parse a subset of GS1 AIs: 00=SSCC, 01=GTIN(item), 10=lot, 17=expiry, 21=serial. */
    private fun parseGs1(raw: String): ResolvedBarcode {
        // Normalise both parenthesised "(01)..." and FNC1-delimited forms.
        val ais = mutableMapOf<String, String>()
        val gs = '\u001D'
        if (raw.contains('(')) {
            val regex = Regex("\\((\\d{2,4})\\)([^()]*)")
            for (m in regex.findAll(raw)) ais[m.groupValues[1]] = m.groupValues[2].trim()
        } else {
            // Best-effort fixed-length parse for common AIs in FNC1 streams.
            var rest = raw
            val fixed = mapOf("00" to 18, "01" to 14, "17" to 6)
            while (rest.length >= 2) {
                val ai = rest.take(2)
                when {
                    fixed.containsKey(ai) -> {
                        val len = fixed[ai]!!
                        ais[ai] = rest.drop(2).take(len)
                        rest = rest.drop(2 + len)
                    }
                    ai == "10" || ai == "21" -> {
                        val seg = rest.drop(2).substringBefore(gs)
                        ais[ai] = seg
                        rest = rest.drop(2 + seg.length).removePrefix(gs.toString())
                    }
                    else -> break
                }
            }
        }

        val sscc = ais["00"]
        val gtin = ais["01"]
        val lot = ais["10"]?.ifBlank { null }
        val expiry = ais["17"]?.ifBlank { null }
        val serial = ais["21"]?.ifBlank { null }

        return when {
            sscc != null -> ResolvedBarcode(BarcodeKind.Lp, sscc, raw, lotNo = lot, serialNo = serial, expiry = expiry)
            gtin != null -> ResolvedBarcode(BarcodeKind.Item, gtin, raw, itemNo = gtin, lotNo = lot, serialNo = serial, expiry = expiry)
            else -> ResolvedBarcode(BarcodeKind.Unknown, raw, raw, lotNo = lot, serialNo = serial, expiry = expiry)
        }
    }
}
