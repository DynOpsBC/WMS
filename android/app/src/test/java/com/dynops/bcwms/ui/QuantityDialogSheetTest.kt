package com.dynops.bcwms.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QuantityDialogSheetTest {
    @Test fun `group quantity cannot exceed available stock or use an invalid limit`() {
        assertTrue(validQuantityInput("5", false, false, 5.0))
        assertFalse(validQuantityInput("5.1", false, false, 5.0))
        assertTrue(validQuantityInput("0", true, false, 0.0))
        assertFalse(validQuantityInput("1", true, true, 0.0))
        assertFalse(validQuantityInput("1", false, false, Double.NaN))
    }
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
