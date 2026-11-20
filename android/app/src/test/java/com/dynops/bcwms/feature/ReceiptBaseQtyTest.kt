package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReceiptBaseQtyTest {
    private fun line(unit: String, base: String, factor: Double) =
        JSONObject().put("itemNo", "9MM KOVAN KASE(AKS)").put("unitOfMeasureCode", unit)
            .put("baseUnitOfMeasure", base).put("qtyPerUnitOfMeasure", factor).put("qtyToReceive", 14100.0)

    @Test
    fun `kg line of an adet item shows the adet equivalent`() {
        val l = line("KG", "ADET", 211.86)
        assertEquals(14100.0 * 211.86, receiptBaseQuantity(l, 14100.0)!!, 0.001)
        assertEquals("2.987.226 ADET", receiptBaseQtyText(l, 14100.0))
    }

    @Test
    fun `same unit or unknown factor shows nothing`() {
        assertNull(receiptBaseQuantity(line("ADET", "ADET", 1.0), 10.0))
        assertNull(receiptBaseQuantity(line("KG", "", 211.86), 10.0))
        assertNull(receiptBaseQuantity(line("KG", "ADET", 0.0), 10.0))
        assertEquals("", receiptBaseQtyText(line("ADET", "ADET", 1.0), 10.0))
    }

    @Test
    fun `label puts adet first and keeps kg in brackets`() {
        val row = receiptLabelRows(listOf(line("KG", "ADET", 5.0))).single()
        assertEquals("70.500 ADET (14.100 KG)", receiptLabelQuantityText(row))
        val plain = receiptLabelRows(listOf(line("ADET", "ADET", 1.0))).single()
        assertEquals("14.100 ADET", receiptLabelQuantityText(plain))
    }

    @Test
    fun `too long label text keeps only the adet quantity`() {
        val row = ReceiptLabelRow("X", "", "", "", 123456789.123, "KILOGRAM", baseQuantity = 98765432109.5, baseUnit = "ADET")
        assertEquals(receiptLabelQtyText(98765432109.5, "ADET"), receiptLabelQuantityText(row))
    }

    @Test
    fun `adet entry converts back to kg`() {
        assertEquals(14100.0, com.dynops.bcwms.ui.convertFromBase(14100.0 * 211.8644, 211.8644), 0.00001)
        assertEquals(0.0, com.dynops.bcwms.ui.convertFromBase(10.0, 0.0), 0.0)
    }

    @Test
    fun `tolerance raises the receivable maximum`() {
        val withTolerance = JSONObject().put("quantity", 14100.0).put("qtyReceived", 0.0).put("maxQtyToReceive", 28200.0)
        assertEquals(28200.0, receiptMaxQty(withTolerance), 0.0001)
        val oldBc = JSONObject().put("quantity", 14100.0).put("qtyReceived", 100.0)
        assertEquals(14000.0, receiptMaxQty(oldBc), 0.0001)
    }

    @Test
    fun `adet typed in is shown back exactly`() {
        val kg = com.dynops.bcwms.ui.convertFromBase(3000000.0, 211.8644)
        assertEquals("3.000.000", com.dynops.bcwms.ui.quantityConversionText(kg * 211.8644))
        assertEquals(2987288.04, displayBaseQty(2987288.04), 0.0001)
    }
}
