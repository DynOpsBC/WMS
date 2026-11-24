package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PreparedItemLabelsTest {
    private fun original() = javaClass.getResourceAsStream("/dkc-labels-2026-10-15.xlsx")!!.use(ExcelLabelImport::read)
    private fun apiRows() = original().map { row -> JSONObject()
        .put("listCode", PreparedItemLabels.LIST_CODE).put("sourceDate", PreparedItemLabels.SOURCE_DATE)
        .put("lineNo", row.order).put("itemNo", row.itemNo).put("description", row.description).put("binCode", row.bin) }

    @Test fun `prepared BC list is identical to all 1535 original rows without file input`() {
        val rows = PreparedItemLabels.read(apiRows())
        assertEquals(original(), rows)
        assertEquals(1227, rows.map { it.itemNo }.distinct().size)
        assertEquals(31, rows.chunked(50).size)
    }

    @Test fun `missing extra reordered and changed rows stop before printing`() {
        val rows = apiRows()
        listOf(rows.dropLast(1), rows + rows.last(), rows.reversed(),
            apiRows().apply { this[100].put("binCode", "OTHER") }).forEach {
            assertThrows(IllegalArgumentException::class.java) { PreparedItemLabels.read(it) }
        }
    }

    @Test fun `another list code or source date cannot silently replace the requested snapshot`() {
        listOf("listCode" to "OTHER", "sourceDate" to "2026-10-19").forEach { (key, value) ->
            val rows = apiRows().apply { this[0].put(key, value) }
            assertThrows(IllegalArgumentException::class.java) { PreparedItemLabels.read(rows) }
        }
    }

    @Test fun `query requests only this company snapshot in line order`() {
        assertTrue(PreparedItemLabels.QUERY.contains("listCode eq 'DKC-GOZ-20261015'"))
        assertTrue(PreparedItemLabels.QUERY.endsWith("\$orderby=lineNo"))
    }
}
