package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Test

class ExcelLabelSkipTest {
    private val rows = listOf(
        ExcelLabelRow(531, "A-1", "Ürün A", "Z16"),
        ExcelLabelRow(532, "L.C.124 GR PİRİNÇ.", "YARI MAMUL", "Z17"),
        ExcelLabelRow(533, "a-1", "Ürün A tekrar", "Z18"),
    )

    @Test
    fun `only rows whose item is missing or blocked are skipped, order kept`() {
        val available = setOf("A-1")
        val missing = unavailableLabelRows(rows, available)
        assertEquals(listOf(532), missing.map { it.order })
        assertEquals(listOf(531, 533), (rows - missing.toSet()).map { it.order })
    }

    @Test
    fun `turkish dotted capital I matches the BC item number`() {
        assertEquals(emptyList<ExcelLabelRow>(), unavailableLabelRows(rows, setOf("A-1", "L.C.124 GR PİRİNÇ.")))
    }
}
