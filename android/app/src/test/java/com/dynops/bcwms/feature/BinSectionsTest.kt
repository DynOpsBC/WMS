package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class BinSectionsTest {
    private fun row(code: String) = JSONObject().put("code", code).put("locationCode", "WMS")

    @Test fun `X W and XY each contain only their own 26 bins`() {
        val rows = listOf("X", "W", "XY").flatMap { section ->
            (1..26).map { row("$section${it.toString().padStart(2, '0')}") }
        }
        assertEquals(listOf("W" to "26 raf", "X" to "26 raf", "XY" to "26 raf"), binSectionChoices(rows))
        for (section in listOf("X", "W", "XY")) {
            val filtered = filterBinSection(rows, section)
            assertEquals(26, filtered.size)
            assertEquals("${section}01", filtered.first().optString("code"))
            assertEquals("${section}26", filtered.last().optString("code"))
        }
        assertFalse(filterBinSection(rows, "X").any { it.optString("code").startsWith("XY") })
        assertEquals(78, filterBinSection(rows, "").size)
        assertTrue(filterBinSection(rows, "UNKNOWN").isEmpty())
    }

    @Test fun `section filtering preserves row data and natural ordering`() {
        val rows = listOf(row("X10"), row("X2"), row("X1"), row("XY1"))
        val filtered = filterBinSection(rows, " x ")
        assertEquals(listOf("X1", "X2", "X10"), filtered.map { it.optString("code") })
        assertSame(rows[2], filtered.first())
        assertEquals("WMS", filtered.first().optString("locationCode"))
    }

    @Test fun `section supports separators whitespace and ungrouped bins`() {
        assertEquals("XY", binSection(" xy-01 "))
        assertEquals("X", binSection("X-01"))
        val rows = listOf(row("001"), row("X01"))
        assertEquals("001", filterBinSection(rows, "Diğer").single().optString("code"))
    }
}
