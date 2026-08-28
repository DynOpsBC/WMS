package com.dynops.bcwms.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QuantityDialogSheetTest {
    @Test
    fun `pick quantity can explicitly allow zero`() {
        assertTrue(validQuantityInput("0", allowZeroQuantity = true, quantityExactlyOne = false))
        assertFalse(validQuantityInput("0", allowZeroQuantity = false, quantityExactlyOne = false))
    }

    @Test
    fun `empty invalid and negative quantities remain blocked`() {
        assertFalse(validQuantityInput("", allowZeroQuantity = true, quantityExactlyOne = false))
        assertFalse(validQuantityInput("abc", allowZeroQuantity = true, quantityExactlyOne = false))
        assertFalse(validQuantityInput("-1", allowZeroQuantity = true, quantityExactlyOne = false))
    }

    @Test
    fun `exactly one rule is not weakened by zero support`() {
        assertTrue(validQuantityInput("1", allowZeroQuantity = true, quantityExactlyOne = true))
        assertFalse(validQuantityInput("0", allowZeroQuantity = true, quantityExactlyOne = true))
    }
}
