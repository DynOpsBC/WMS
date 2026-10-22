package com.dynops.bcwms.scanner

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScanFieldKeyboardPolicyTest {
    @Test
    fun `scan fields suppress the soft keyboard only on Kitoko`() {
        assertTrue(scanFieldSuppressesKeyboard("kitoko"))
        assertTrue(scanFieldSuppressesKeyboard("KITOKO"))
        assertFalse(scanFieldSuppressesKeyboard("bade"))
        assertFalse(scanFieldSuppressesKeyboard("emu"))
        assertFalse(scanFieldSuppressesKeyboard("dynops"))
    }
}
