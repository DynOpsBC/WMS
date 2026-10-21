package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LabelRangeTest {
    private val rows = (1..1535).map { ExcelLabelRow(it, "ITEM${it % 7}", "Ürün $it", "A.${it}") }

    @Test
    fun `range keeps order and includes both ends`() {
        val chosen = labelRange(rows, "498", "500").getOrThrow()
        assertEquals(listOf(498, 499, 500), chosen.map { it.order })
        assertEquals(1535, labelRange(rows, "1", "1535").getOrThrow().size)
        assertEquals(listOf(1535), labelRange(rows, "1535", "1535").getOrThrow().map { it.order })
    }

    @Test
    fun `invalid ranges are rejected with a Turkish message`() {
        assertTrue(labelRange(rows, "", "10").exceptionOrNull()!!.message!!.contains("İlk ve son"))
        assertTrue(labelRange(rows, "0", "10").exceptionOrNull()!!.message!!.contains("1 ile 1535"))
        assertTrue(labelRange(rows, "10", "1600").exceptionOrNull()!!.message!!.contains("1 ile 1535"))
        assertTrue(labelRange(rows, "600", "500").exceptionOrNull()!!.message!!.contains("büyük olamaz"))
    }

    @Test
    fun `resume is offered only for the same list`() {
        val saved = labelResumeValue("Hazır liste", 1535, 701, 1535)
        assertEquals(701..1535, labelResumeRange(saved, "Hazır liste", 1535))
        assertNull(labelResumeRange(saved, "Excel sırası korunur.", 1535))
        assertNull(labelResumeRange(saved, "Hazır liste", 1200))
        assertNull(labelResumeRange("", "Hazır liste", 1535))
    }
}
