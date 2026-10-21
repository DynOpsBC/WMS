package com.dynops.bcwms.feature

import org.json.JSONArray
import org.json.JSONObject
import org.w3c.dom.Element
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.util.zip.ZipInputStream
import javax.xml.parsers.DocumentBuilderFactory

// Kitoko (21 Eki 2026): EMU 1.14.164'ten. 'QR → Göz' sayfalı .xlsx şablonu okunur.

/** Quantity is informational. Each spreadsheet row always produces exactly one label. */
internal data class ExcelLabelRow(val order: Int, val itemNo: String, val description: String, val bin: String)

internal object ExcelLabelImport {
    private const val MAX_BYTES = 32 * 1024 * 1024
    private const val MAX_ROWS = 10000

    fun read(input: InputStream): List<ExcelLabelRow> {
        val parts = mutableMapOf<String, ByteArray>()
        var expanded = 0
        var entries = 0
        ZipInputStream(input).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                require(++entries <= 2000) { "Excel dosyasında çok fazla bölüm var." }
                val bytes = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = zip.read(buffer)
                    if (count < 0) break
                    expanded += count
                    require(expanded <= MAX_BYTES) { "Excel dosyası çok büyük (en fazla 32 MB açılmış içerik)." }
                    if (entry.name.endsWith(".xml") || entry.name.endsWith(".rels")) bytes.write(buffer, 0, count)
                }
                require(!parts.containsKey(entry.name)) { "Excel dosyasında yinelenen bölüm var." }
                if (bytes.size() > 0) parts[entry.name] = bytes.toByteArray()
            }
        }
        fun xml(path: String): Element {
            val bytes = requireNotNull(parts[path]) { "Geçerli bir .xlsx dosyası seçin ($path bulunamadı)." }
            // Reject declarations before parsing, including UTF-16/32 encodings. Never resolve external entities.
            val source = Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString()
            require(!source.contains('\u0000') && !Regex("""encoding\s*=\s*["'](?!UTF-?8["'])""", RegexOption.IGNORE_CASE).containsMatchIn(source.take(200))) {
                "Excel XML içeriği UTF-8 olmalı. Dosyayı .xlsx olarak yeniden kaydedin."
            }
            require(!source.contains("<!DOCTYPE", true) && !source.contains("<!ENTITY", true)) { "Excel XML bildirimi desteklenmiyor." }
            val factory = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            return factory.newDocumentBuilder().apply {
                setEntityResolver { _, _ -> throw IllegalArgumentException("Dış XML kaynağı desteklenmiyor.") }
            }.parse(ByteArrayInputStream(bytes)).documentElement
        }
        val workbook = xml("xl/workbook.xml")
        val sheets = workbook.elements("sheet")
        val sheet = sheets.firstOrNull { it.getAttribute("name") == "QR → Göz" }
            ?: throw IllegalArgumentException("Excel'de 'QR → Göz' sayfası bulunamadı.")
        val relation = sheet.getAttributeNS("http://schemas.openxmlformats.org/officeDocument/2006/relationships", "id")
        val target = xml("xl/_rels/workbook.xml.rels").elements("Relationship")
            .singleOrNull { it.getAttribute("Id") == relation }?.getAttribute("Target")
            ?: throw IllegalArgumentException("Excel sayfa bağlantısı okunamadı.")
        val path = if (target.startsWith("/")) target.removePrefix("/") else "xl/$target"
        require(!path.contains("..")) { "Excel sayfa yolu geçersiz." }
        val strings = if (parts.containsKey("xl/sharedStrings.xml")) xml("xl/sharedStrings.xml").elements("si")
            .map { it.elements("t").joinToString("") { text -> text.textContent } } else emptyList()
        fun cellValue(cell: Element): String {
            require(cell.elements("f").isEmpty()) { "Etiket verilerinde formül yerine sabit değer kullanın." }
            val value = cell.elements("v").firstOrNull()?.textContent.orEmpty()
            return when (cell.getAttribute("t")) {
                "s" -> strings.getOrNull(value.toIntOrNull() ?: -1)
                    ?: throw IllegalArgumentException("Excel metin hücresi okunamadı.")
                "inlineStr" -> cell.elements("t").joinToString("") { it.textContent }
                "e" -> throw IllegalArgumentException("Excel'de hatalı hücre var.")
                else -> value
            }.trim()
        }
        val rows = xml(path).elements("row")
        require(rows.size <= MAX_ROWS + 1) { "En fazla $MAX_ROWS etiket satırı yüklenebilir." }
        fun cells(row: Element): Map<String, Element> = row.elements("c").associateBy { it.getAttribute("r").takeWhile(Char::isLetter) }
        val headers = cells(rows.firstOrNull() ?: throw IllegalArgumentException("Excel sayfası boş."))
        val expected = listOf("Etiket Sırası", "Ürün QR (Madde No.)", "Ürün Adı", "Göz", "Miktar", "Birim", "Not")
        require(expected.withIndex().all { (index, value) -> headers[('A' + index).toString()]?.let(::cellValue) == value }) {
            "QR → Göz sayfasının sütunları beklenen etiket şablonuyla eşleşmiyor."
        }
        val result = mutableListOf<ExcelLabelRow>()
        for (row in rows.drop(1)) {
            val cells = cells(row)
            fun value(column: String) = cells[column]?.let(::cellValue).orEmpty()
            if (listOf("A", "B", "C", "D").all { value(it).isBlank() }) continue
            val order = value("A").toBigDecimalOrNull()?.let { runCatching { it.intValueExact() }.getOrNull() }
            require(order == result.size + 1) { "Etiket sırası kesintisiz 1, 2, 3… olmalı (Excel satırı ${row.getAttribute("r")})." }
            val itemNo = value("B")
            val bin = value("D")
            require(cells["B"]?.getAttribute("t") in setOf("s", "inlineStr", "str")) {
                "Etiket $order: ürün numarası metin olmalı; baştaki sıfırların korunması gerekir."
            }
            require(itemNo.isNotBlank() && itemNo.length <= 20 && itemNo.none(Char::isISOControl)) { "Etiket $order: ürün numarası boş veya geçersiz." }
            require(bin.isNotBlank() && bin.length <= 20 && bin.none(Char::isISOControl)) { "Etiket $order: göz boş veya geçersiz." }
            result += ExcelLabelRow(order!!, itemNo, value("C").take(100), bin)
        }
        require(result.isNotEmpty()) { "Excel'de basılacak etiket satırı yok." }
        return result
    }

    private fun Element.elements(name: String): List<Element> = getElementsByTagNameNS("*", name).let { nodes ->
        (0 until nodes.length).map { nodes.item(it) as Element }
    }
}

internal fun excelLabelsPayload(rows: List<ExcelLabelRow>, printerId: String): String = JSONObject()
    .put("rowsJson", JSONArray().apply {
        rows.forEach { row -> put(JSONObject().put("order", row.order).put("itemNo", row.itemNo).put("bin", row.bin)) }
    }.toString()).put("printerId", printerId).toString()

/** No deduplication, sorting, quantity expansion or automatic retry. */
internal suspend fun sendExcelLabels(
    rows: List<ExcelLabelRow>,
    send: suspend (List<ExcelLabelRow>) -> Result<Int>,
    stopRequested: () -> Boolean,
    onProgress: (Int, Int) -> Unit,
): AllItemLabelsOutcome {
    var sent = 0
    onProgress(0, rows.size)
    for (batch in rows.chunked(ALL_ITEM_LABELS_BATCH)) {
        if (stopRequested()) return AllItemLabelsOutcome(sent, rows.size, true)
        val result = try { send(batch) } catch (cancelled: kotlinx.coroutines.CancellationException) {
            throw cancelled
        } catch (error: Exception) { Result.failure(error) }
        if (result.isFailure || result.getOrNull() != batch.size) {
            return AllItemLabelsOutcome(sent, rows.size, false,
                "${batch.first().order}–${batch.last().order} aralığının sonucu doğrulanamadı. " +
                    "Yeniden göndermeden önce yazıcı kuyruğunu kontrol edin. " +
                    (result.exceptionOrNull()?.message ?: "Sunucu eksik etiket sayısı döndürdü."))
        }
        sent += batch.size
        onProgress(sent, rows.size)
    }
    return AllItemLabelsOutcome(sent, rows.size, false)
}
