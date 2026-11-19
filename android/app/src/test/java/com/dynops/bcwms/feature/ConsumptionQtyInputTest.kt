package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Test

class ConsumptionQtyInputTest {
    @Test
    fun `initial quantity has no thousands separator`() {
        assertEquals("10000", consumptionQtyInput(10000.0))
        assertEquals("10493,5", consumptionQtyInput(10493.5))
        assertEquals("0", consumptionQtyInput(-3.0))
    }

    @Test
    fun `edited input stays the same number`() {
        val edited = com.dynops.bcwms.ui.normalizeQtyInput(consumptionQtyInput(5000.25)).replace('.', ',')
        assertEquals(5000.25, edited.replace(',', '.').toDouble(), 0.0001)
    }

    @Test
    fun `consumable limit is picked minus consumed for this order`() {
        val c = org.json.JSONObject().put("itemNo", "K").put("binCode", "B").put("qtyPicked", 10000.0).put("actConsumptionQty", 5000.0)
        assertEquals(5000.0, pickedNotConsumed(c, mapOf("K|B" to 2500000.0))!!, 0.0001)
        val notPicked = org.json.JSONObject().put("itemNo", "K").put("binCode", "B").put("qtyPicked", 0.0).put("actConsumptionQty", 0.0)
        assertEquals(0.0, pickedNotConsumed(notPicked, mapOf("K|B" to 2500000.0))!!, 0.0001)
        val oldBc = org.json.JSONObject().put("itemNo", "K").put("binCode", "B")
        assertEquals(42.0, pickedNotConsumed(oldBc, mapOf("K|B" to 42.0))!!, 0.0001)
    }
}
