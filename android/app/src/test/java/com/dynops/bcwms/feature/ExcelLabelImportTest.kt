package com.dynops.bcwms.feature

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class ExcelLabelImportTest {
    private fun actualRows() = javaClass.getResourceAsStream("/dkc-labels-2026-10-15.xlsx")!!.use(ExcelLabelImport::read)

    @Test fun `actual customer file preserves all 1535 rows including 308 repeated products`() {
        val rows = actualRows()
        assertEquals(1535, rows.size)
        assertEquals(1227, rows.map { it.itemNo }.distinct().size)
        assertEquals((1..1535).toList(), rows.map { it.order })
        assertEquals(ExcelLabelRow(1, "HK0808", "HK0808 RULMAN", "A1"), rows.first())
        assertEquals("22490-003-R02", rows[1].itemNo)
        assertEquals(3, rows.count { it.itemNo == "22490-003-R02" })
        assertEquals(3, rows.filter { it.itemNo == "22490-003-R02" }.map { it.bin }.distinct().size)
    }

    @Test fun `payload preserves duplicate items and never sends stock quantity as copies`() {
        val rows = actualRows().filter { it.itemNo == "22490-003-R02" }
        val payload = JSONObject(excelLabelsPayload(rows, "P1"))
        assertEquals("P1", payload.getString("printerId"))
        assertFalse(payload.has("copies"))
        val array = JSONArray(payload.getString("rowsJson"))
        assertEquals(3, array.length())
        rows.forEachIndexed { index, row ->
            val obj = array.getJSONObject(index)
            assertEquals(row.itemNo, obj.getString("itemNo"))
            assertEquals(row.bin, obj.getString("bin"))
            assertEquals(row.order, obj.getInt("order"))
            assertFalse(obj.has("quantity"))
        }
    }

    @Test fun `1535 rows send as 31 ordered requests without duplicates being removed`() = runBlocking {
        val original = actualRows()
        val sent = mutableListOf<ExcelLabelRow>()
        var calls = 0
        val outcome = sendExcelLabels(original, send = { batch ->
            calls++
            assertTrue(batch.size <= 50)
            sent += batch
            Result.success(batch.size)
        }, stopRequested = { false }, onProgress = { _, _ -> })
        assertEquals(31, calls)
        assertEquals(original, sent)
        assertEquals(1535, outcome.sent)
        assertNull(outcome.error)
    }

    @Test fun `uncertain response stops with exact range and is never retried`() = runBlocking {
        var calls = 0
        val result = sendExcelLabels(actualRows(), send = { batch ->
            calls++
            if (calls == 2) Result.failure(IllegalStateException("timeout")) else Result.success(batch.size)
        }, stopRequested = { false }, onProgress = { _, _ -> })
        assertEquals(2, calls)
        assertEquals(50, result.sent)
        assertTrue(result.error!!.contains("51–100"))
    }

    @Test fun `partial count is uncertain and stop finishes only current batch`() = runBlocking {
        val rows = actualRows()
        val partial = sendExcelLabels(rows, { Result.success(49) }, { false }, { _, _ -> })
        assertEquals(0, partial.sent)
        assertNotNull(partial.error)
        var stop = false
        var calls = 0
        val stopped = sendExcelLabels(rows, { calls++; stop = true; Result.success(it.size) }, { stop }, { _, _ -> })
        assertEquals(1, calls)
        assertEquals(50, stopped.sent)
        assertTrue(stopped.stopped)
    }

    @Test fun `inline strings preserve leading zeros and rich shared strings are supported`() {
        val rows = ExcelLabelImport.read(workbook().inputStream())
        assertEquals("00123", rows.single().itemNo)
        assertEquals("A1", rows.single().bin)
    }

    @Test fun `missing columns formulas broken order blank bins and entity declarations are rejected`() {
        listOf(
            workbook(header = "Başka"),
            workbook(number = "<f>1+1</f><v>2</v>"),
            workbook(order = 2),
            workbook(bin = ""),
            workbook(extra = "<!DOCTYPE worksheet [<!ENTITY x SYSTEM 'file:///etc/passwd'>]>"),
        ).forEach { bytes ->
            assertThrows(IllegalArgumentException::class.java) { ExcelLabelImport.read(bytes.inputStream()) }
        }
    }

    private fun workbook(header: String = "Etiket Sırası", number: String = "<is><t>00123</t></is>", order: Int = 1, bin: String = "A1", extra: String = ""): ByteArray {
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            fun part(name: String, text: String) {
                zip.putNextEntry(ZipEntry(name)); zip.write(text.toByteArray()); zip.closeEntry()
            }
            part("xl/workbook.xml", """<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="QR → Göz" r:id="rId1"/></sheets></workbook>""")
            part("xl/_rels/workbook.xml.rels", """<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>""")
            val headers = listOf(header, "Ürün QR (Madde No.)", "Ürün Adı", "Göz", "Miktar", "Birim", "Not")
                .mapIndexed { index, text -> """<c r="${'A'+index}1" t="inlineStr"><is><t>$text</t></is></c>""" }.joinToString("")
            part("xl/worksheets/sheet1.xml", """$extra<worksheet><sheetData><row r="1">$headers</row><row r="2"><c r="A2"><v>$order</v></c><c r="B2" t="inlineStr">$number</c><c r="C2" t="s"><v>0</v></c><c r="D2" t="inlineStr"><is><t>$bin</t></is></c><c r="E2"><v>9999</v></c></row></sheetData></worksheet>""")
            part("xl/sharedStrings.xml", "<sst><si><r><t>Ürün </t></r><r><t>adı</t></r></si></sst>")
        }
        return output.toByteArray()
    }
}
