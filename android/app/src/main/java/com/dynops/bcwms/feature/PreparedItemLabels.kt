package com.dynops.bcwms.feature

import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.MessageDigest

/** The fixed 15 October snapshot is private BC company data, never bundled in the public APK. */
internal object PreparedItemLabels {
    const val LIST_CODE = "DKC-GOZ-20261015"
    const val SOURCE_DATE = "2026-10-15"
    const val EXPECTED_ROWS = 1535
    const val BUTTON = "Hazır göz listesi — 1.535 etiket"
    const val QUERY = "preparedItemLabelRows?\$filter=listCode eq '$LIST_CODE'&\$orderby=lineNo"
    private const val EXPECTED_SHA256 = "77537e2401d625e189763aae1c779819d7659453fa799a9d6f3ae07e7da6e379"

    fun read(apiRows: List<JSONObject>): List<ExcelLabelRow> {
        require(apiRows.size == EXPECTED_ROWS) { "Hazır göz listesi eksik (${apiRows.size}/$EXPECTED_ROWS). Hiçbir etiket gönderilmedi." }
        val rows = apiRows.mapIndexed { index, row ->
            require(row.optString("listCode") == LIST_CODE && row.optString("sourceDate") == SOURCE_DATE) {
                "Hazır listenin kodu veya kaynak tarihi eşleşmiyor."
            }
            val order = row.optInt("lineNo")
            require(order == index + 1) { "Hazır listenin satır sırası eksik veya değişmiş." }
            ExcelLabelRow(order, row.optString("itemNo"), row.optString("description"), row.optString("binCode"))
        }
        require(fingerprint(rows) == EXPECTED_SHA256) {
            "Hazır liste 15.10.2026 listesinden farklı. Yazdırmadan önce listeyi yöneticinize kontrol ettirin."
        }
        return rows
    }

    internal fun fingerprint(rows: List<ExcelLabelRow>): String {
        val hash = MessageDigest.getInstance("SHA-256")
        rows.forEach { row ->
            listOf(row.order.toString(), row.itemNo, row.description, row.bin).forEach { value ->
                val bytes = value.toByteArray(Charsets.UTF_8)
                hash.update(ByteBuffer.allocate(4).putInt(bytes.size).array())
                hash.update(bytes)
            }
        }
        return hash.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }
}
