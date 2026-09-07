package com.dynops.bcwms.ui

import org.junit.Assert.*
import org.junit.Test

class NumericInputTest {
    @Test
    fun `non finite and overflowing quantities cannot reach JSON write requests`() {
        for (value in listOf("NaN", "Infinity", "-Infinity", "1e309", "-1e309", "", "abc")) {
            assertNull(value, value.toFiniteDoubleOrNull())
        }
    }

    @Test
    fun `finite values retain existing zero and sign semantics for caller validation`() {
        assertEquals(0.0, "0".toFiniteDoubleOrNull()!!, 0.0)
        assertEquals(1.25, "1.25".toFiniteDoubleOrNull()!!, 0.0)
        assertEquals(-5.0, "-5".toFiniteDoubleOrNull()!!, 0.0)
        assertEquals(1000.0, "1e3".toFiniteDoubleOrNull()!!, 0.0)
    }
}
