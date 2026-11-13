package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ItemBinStockTest {
    private fun row(bin: String, qty: Int, uom: String = "ADET") = JSONObject()
        .put("locationCode", "WMS").put("binCode", bin).put("quantity", qty).put("unitOfMeasureCode", uom)

    @Test fun `each stocked bin is shown separately and zero stock is hidden`() {
        val a = row("HM1", 500)
        val b = row("MONT", 100)
        val actual = stockedItemBins(listOf(b, row("EMPTY", 0), a))
        assertEquals(listOf(a, b), actual)
        assertEquals(500, actual[0].getInt("quantity"))
        assertEquals(100, actual[1].getInt("quantity"))
    }

    @Test fun `different units and negative stock are preserved without summing`() {
        val rows = listOf(row("A", 5, "KOLI"), row("A", 10), row("B", -2))
        val actual = stockedItemBins(rows)
        assertEquals(3, actual.size)
        assertEquals(setOf("ADET", "KOLI"), actual.map { it.getString("unitOfMeasureCode") }.toSet())
        assertEquals(-2, actual.last().getInt("quantity"))
    }

    @Test fun `locations and bins form separate branches retaining zones and variants`() {
        val a = row("A", 10).put("zoneCode", "Z1").put("variantCode", "RED").put("qtyBaseUoM", 10)
        val b = row("A", 2, "KOLI").put("zoneCode", "Z1").put("variantCode", "BLUE").put("qtyBaseUoM", 20)
        val c = row("A", -3).put("locationCode", "SECOND").put("zoneCode", "Z2").put("qtyBaseUoM", -3)
        val result = itemStockLocations(listOf(b, row("EMPTY", 0), c, a))
        assertEquals(listOf("SECOND", "WMS"), result.map { it.code })
        assertEquals(-3.0, result[0].baseQuantity!!, 0.0)
        assertEquals(30.0, result[1].baseQuantity!!, 0.0)
        assertEquals(1, result[1].bins.size)
        assertEquals(setOf("BLUE", "RED"), result[1].bins.single().rows.map { it.getString("variantCode") }.toSet())
        assertEquals("Z2", result[0].bins.single().rows.single().getString("zoneCode"))
    }

    @Test fun `missing base quantity does not invent mixed unit totals`() {
        val result = itemStockLocations(listOf(row("A", 3), row("A", 2, "KOLI").put("qtyBaseUoM", 20)))
        assertNull(result.single().baseQuantity)
        assertEquals(2, result.single().bins.single().rows.size)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `missing quantity is a failed result not empty inventory`() {
        itemStockLocations(listOf(JSONObject().put("binCode", "A")))
    }

    @Test fun `fractional quantities retain BC precision`() {
        assertEquals("0,00001", formatStockQuantity(0.00001))
        assertEquals("-1,23456", formatStockQuantity(-1.23456))
    }

    @Test fun `item filter escapes quotes and never restricts location or positive quantities`() {
        assertEquals("binContents?\$filter=itemNo eq 'A''B'", itemStockPath("A'B"))
    }
}
