package com.dynops.bcwms.feature

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Kitoko (21 Eki 2026): bellekte üretilen uydurma .xlsx ile; müşteri dosyası kullanılmaz. */
class ExcelLabelSyntheticImportTest {
    private data class Line(val order: String, val itemNo: String, val name: String, val bin: String)

    // 120 satır; her 4. satır bir önceki ürünü başka gözde tekrarlar.
    private val sample = (1..120).map { order ->
        val item = if (order % 4 == 0) "ORN-${order - 1}" else "ORN-$order"
        Line(order.toString(), item, "Örnek ürün $order", "R.${(order - 1) / 10 + 1}.${(order - 1) % 10 + 1}")
    }

    private fun rows() = ExcelLabelImport.read(workbook(sample).inputStream())

    @Test fun `every row is one label in Excel order and repeated items keep their bins`() {
        val rows = rows()
        assertEquals(120, rows.size)
        assertEquals((1..120).toList(), rows.map { it.order })
        assertEquals(ExcelLabelRow(1, "ORN-1", "Örnek ürün 1", "R.1.1"), rows.first())
        val repeated = rows.filter { it.itemNo == "ORN-3" }
        assertEquals(listOf(3, 4), repeated.map { it.order })
        assertEquals(listOf("R.1.3", "R.1.4"), repeated.map { it.bin })
    }

    @Test fun `payload keeps duplicates and never sends quantity or copies`() {
        val rows = rows().filter { it.itemNo == "ORN-3" }
        val payload = JSONObject(excelLabelsPayload(rows, "ZEBRA1"))
        assertEquals("ZEBRA1", payload.getString("printerId"))
        assertFalse(payload.has("copies"))
        val array = JSONArray(payload.getString("rowsJson"))
        assertEquals(2, array.length())
        rows.forEachIndexed { index, row ->
            val obj = array.getJSONObject(index)
            assertEquals(row.order, obj.getInt("order"))
            assertEquals(row.itemNo, obj.getString("itemNo"))
            assertEquals(row.bin, obj.getString("bin"))
            assertFalse(obj.has("quantity"))
        }
    }

    @Test fun `rows are sent in ordered batches of 50`() = runBlocking {
        val original = rows()
        val sent = mutableListOf<ExcelLabelRow>()
        var calls = 0
        val outcome = sendExcelLabels(original, send = { batch ->
            calls++
            assertTrue(batch.size <= ALL_ITEM_LABELS_BATCH)
            sent += batch
            Result.success(batch.size)
        }, stopRequested = { false }, onProgress = { _, _ -> })
        assertEquals(3, calls)
        assertEquals(original, sent)
        assertEquals(120, outcome.sent)
        assertNull(outcome.error)
    }

    @Test fun `uncertain or partial result stops with the exact range and stop ends after the batch`() = runBlocking {
        val rows = rows()
        var calls = 0
        val failed = sendExcelLabels(rows, send = { batch ->
            calls++
            if (calls == 2) Result.failure(IllegalStateException("timeout")) else Result.success(batch.size)
        }, stopRequested = { false }, onProgress = { _, _ -> })
        assertEquals(2, calls)
        assertEquals(50, failed.sent)
        assertTrue(failed.error!!.contains("51–100"))
        val partial = sendExcelLabels(rows, { Result.success(49) }, { false }, { _, _ -> })
        assertEquals(0, partial.sent)
        assertNotNull(partial.error)
        var stop = false
        val stopped = sendExcelLabels(rows, { stop = true; Result.success(it.size) }, { stop }, { _, _ -> })
        assertEquals(50, stopped.sent)
        assertTrue(stopped.stopped)
    }

    @Test fun `inline strings keep leading zeros and rich shared strings are read`() {
        val rows = ExcelLabelImport.read(workbook(listOf(Line("1", "00123", "", "A1")), sharedName = true).inputStream())
        assertEquals("00123", rows.single().itemNo)
        assertEquals("Ürün adı", rows.single().description)
    }

    @Test fun `wrong template, formulas, numeric item no, broken order, blank bin and DOCTYPE are rejected`() {
        val one = listOf(Line("1", "ORN-1", "Örnek", "A1"))
        listOf(
            workbook(one, header = "Başka"),
            workbook(one, sheet = "Sayfa1"),
            workbook(one, itemCell = "<c r=\"B2\"><f>1+1</f><v>2</v></c>"),
            workbook(one, itemCell = "<c r=\"B2\"><v>123</v></c>"),
            workbook(listOf(Line("2", "ORN-1", "Örnek", "A1"))),
            workbook(listOf(Line("1", "ORN-1", "Örnek", "A1"), Line("3", "ORN-2", "Örnek", "A2"))),
            workbook(listOf(Line("1", "ORN-1", "Örnek", ""))),
            workbook(one, prefix = "<!DOCTYPE worksheet [<!ENTITY x SYSTEM 'file:///etc/passwd'>]>"),
        ).forEach { bytes ->
            assertThrows(IllegalArgumentException::class.java) { ExcelLabelImport.read(bytes.inputStream()) }
        }
    }

    private fun workbook(
        lines: List<Line>,
        header: String = "Etiket Sırası",
        sheet: String = "QR → Göz",
        itemCell: String? = null,
        prefix: String = "",
        sharedName: Boolean = false,
    ): ByteArray {
        fun inline(ref: String, text: String) = """<c r="$ref" t="inlineStr"><is><t>$text</t></is></c>"""
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            fun part(name: String, text: String) {
                zip.putNextEntry(ZipEntry(name)); zip.write(text.toByteArray()); zip.closeEntry()
            }
            part("xl/workbook.xml", """<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="$sheet" r:id="rId1"/></sheets></workbook>""")
            part("xl/_rels/workbook.xml.rels", """<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>""")
            val headers = listOf(header, "Ürün QR (Madde No.)", "Ürün Adı", "Göz", "Miktar", "Birim", "Not")
                .mapIndexed { index, text -> inline("${'A' + index}1", text) }.joinToString("")
            val body = lines.mapIndexed { index, line ->
                val r = index + 2
                val name = if (sharedName) """<c r="C$r" t="s"><v>0</v></c>""" else inline("C$r", line.name)
                """<row r="$r"><c r="A$r"><v>${line.order}</v></c>${itemCell ?: inline("B$r", line.itemNo)}$name${inline("D$r", line.bin)}<c r="E$r"><v>9999</v></c></row>"""
            }.joinToString("")
            part("xl/worksheets/sheet1.xml", """$prefix<worksheet><sheetData><row r="1">$headers</row>$body</sheetData></worksheet>""")
            part("xl/sharedStrings.xml", "<sst><si><r><t>Ürün </t></r><r><t>adı</t></r></si></sst>")
        }
        return output.toByteArray()
    }
}
