package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Test

class ItemRangeTest {
    private val items = (1..1200).map { "IT%04d".format(it) }

    @Test
    fun `blocks follow item number order`() {
        assertEquals(300, itemsInRange(items, 1..300).size)
        assertEquals(listOf("IT0301", "IT0500"), itemsInRange(items, 301..500).let { listOf(it.first(), it.last()) })
        assertEquals(200, itemsInRange(items, 501..700).size)
        assertEquals(300, itemsInRange(items, 701..1000).size)
    }

    @Test
    fun `short list returns only what exists`() {
        assertEquals(50, itemsInRange(items.take(750), 701..1000).size)
        assertEquals(0, itemsInRange(items.take(250), 301..500).size)
    }
}
