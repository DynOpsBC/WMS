package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Test

class ItemRangeTest {
    private val items = (1..2400).map { "IT%04d".format(it) }

    @Test
    fun `kitoko prints four consecutive blocks with no overlap or missing boundary`() {
        val ranges = itemLabelRanges(kitoko = true)
        assertEquals(listOf(1251..1500, 1501..1750, 1751..2000, 2001..2250), ranges)
        val blocks = ranges.map { itemsInRange(items, it) }
        assertEquals(listOf(250, 250, 250, 250), blocks.map { it.size })
        assertEquals(items.slice(1250 until 2250), blocks.flatten())
        assertEquals(listOf(5, 5, 5, 5), blocks.map { allItemLabelBatches(it).size })
        assertEquals(listOf(1..300, 301..500, 501..700, 701..1000, 1001..1250, 1251..1500), itemLabelRanges(kitoko = false))
    }

    @Test
    fun `empty range names the connection and item count`() {
        assertEquals(
            "Bu aralıkta ürün yok: DemoSandbox · ELEMENT4-TR-DEMO-V1 bağlantısında 868 ürün var, aralık 1251. üründen başlıyor. Ortam / şirket seçimini kontrol edin.",
            allItemLabelsEmptyMessage(1251..1500, 868, "DemoSandbox", "ELEMENT4-TR-DEMO-V1"),
        )
        assertEquals("BC'de etiket basılacak ürün bulunamadı.", allItemLabelsEmptyMessage(null, 0, "Sand2010", "Element 4"))
        assertEquals("BC'de etiket basılacak ürün bulunamadı.", allItemLabelsEmptyMessage(1251..1500, 1300, "Sand2010", "Element 4"))
    }

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
        assertEquals(100, itemsInRange(items.take(1600), 1501..1750).size)
        assertEquals(0, itemsInRange(items.take(1750), 1751..2000).size)
        assertEquals(100, itemsInRange(items.take(2100), 2001..2250).size)
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
