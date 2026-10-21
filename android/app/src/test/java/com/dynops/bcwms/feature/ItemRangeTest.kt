package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Test

class ItemRangeTest {
    private val items = (1..1600).map { "IT%04d".format(it) }

    @Test
    fun `blocks follow item number order`() {
        assertEquals(300, itemsInRange(items, 1..300).size)
        assertEquals(listOf("IT0301", "IT0500"), itemsInRange(items, 301..500).let { listOf(it.first(), it.last()) })
        assertEquals(200, itemsInRange(items, 501..700).size)
        assertEquals(300, itemsInRange(items, 701..1000).size)
        assertEquals(listOf("IT1001", "IT1250"), itemsInRange(items, 1001..1250).let { listOf(it.first(), it.last()) })
        assertEquals(listOf("IT1251", "IT1500"), itemsInRange(items, 1251..1500).let { listOf(it.first(), it.last()) })
    }

    @Test
    fun `short list returns only what exists`() {
        assertEquals(50, itemsInRange(items.take(750), 701..1000).size)
        assertEquals(0, itemsInRange(items.take(250), 301..500).size)
        assertEquals(100, itemsInRange(items.take(1350), 1251..1500).size)
    }

    @Test
    fun `range buttons follow the design picked on top`() {
        assertEquals("İlk 300 ürünün etiketi", allItemLabelsTitle(1..300, v2Format = true, withLayoutPicker = true))
        assertEquals("Ürün 1001–1250 etiketi", allItemLabelsTitle(1001..1250, v2Format = true, withLayoutPicker = true))
        assertEquals("Ürün 301–500 · ETIKETV2 (QR + madde no)", allItemLabelsTitle(301..500, v2Format = true, withLayoutPicker = false))
        assertEquals("printLabelsV2", allItemLabelsAction(v2Format = true, layoutCode = ""))
        assertEquals("printLabelsWithLayout", allItemLabelsAction(v2Format = true, layoutCode = "URUN-01"))
        val withLayout = org.json.JSONObject(allItemLabelsPayload(listOf("A", "B"), "ZEBRA1", "URUN-01"))
        assertEquals("URUN-01", withLayout.getString("layoutCode"))
        assertEquals("[\"A\",\"B\"]", withLayout.getString("itemNosJson"))
        assertEquals(false, org.json.JSONObject(allItemLabelsPayload(listOf("A"), "ZEBRA1")).has("layoutCode"))
    }
}
