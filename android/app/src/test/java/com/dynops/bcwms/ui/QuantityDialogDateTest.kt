package com.dynops.bcwms.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

class QuantityDialogDateTest {
    @Test
    fun `eight expiry digits are formatted while typing`() {
        assertEquals("11.12.2028", formatExpiryDateInput("11122028"))
        assertEquals("11.1", formatExpiryDateInput("111"))
        assertEquals("11.12", formatExpiryDateInput("1112"))
    }

    @Test
    fun `pasted expiry date is normalized and limited to eight digits`() {
        assertEquals("11.12.2028", formatExpiryDateInput("11/12/2028"))
        assertEquals("11.12.2028", formatExpiryDateInput("1112202899"))
    }

    @Test
    fun `turkish expiry input is converted to BC ISO date`() {
        assertEquals("2027-12-31", normalizeExpiryDate("31.12.2027"))
        assertEquals("2027-12-31", normalizeExpiryDate("31/12/2027"))
    }

    @Test
    fun `invalid calendar date is rejected`() {
        assertNull(normalizeExpiryDate("31.02.2027"))
        assertNull(normalizeExpiryDate(""))
    }

    @Test
    fun `BC ISO date is displayed in terminal format`() {
        assertEquals("31.12.2027", expiryDateForDisplay("2027-12-31"))
        assertEquals("", expiryDateForDisplay("0001-01-01"))
    }

    @Test
    fun `expired receipt date is rejected while today and future remain valid`() {
        val today = LocalDate.of(2026, 8, 28)

        assertEquals(false, expiryDateIsTodayOrFuture("2026-08-27", today))
        assertEquals(true, expiryDateIsTodayOrFuture("2026-08-28", today))
        assertEquals(true, expiryDateIsTodayOrFuture("2027-01-01", today))
        assertEquals(true, expiryDateIsTodayOrFuture(null, today))
    }
}
