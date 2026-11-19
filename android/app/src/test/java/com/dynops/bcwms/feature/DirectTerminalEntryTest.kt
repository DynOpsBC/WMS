package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DirectTerminalEntryTest {
    @Test
    fun `dkc without wms users enters with the terminal only`() {
        assertTrue(directTerminalEntry("emu", usersLoaded = true, userCount = 0))
    }

    @Test
    fun `dkc with wms users keeps the name list`() {
        assertFalse(directTerminalEntry("emu", usersLoaded = true, userCount = 2))
    }

    @Test
    fun `a failed user list never opens direct entry`() {
        assertFalse(directTerminalEntry("emu", usersLoaded = false, userCount = 0))
    }

    @Test
    fun `other customers keep the wms user sign in`() {
        assertFalse(directTerminalEntry("bade", usersLoaded = true, userCount = 0))
        assertFalse(directTerminalEntry("kitoko", usersLoaded = true, userCount = 0))
    }

    @Test
    fun `button names the selected terminal`() {
        assertEquals("TERMİNAL-3 ile devam et", directEntryLabel("TERMİNAL-3"))
        assertEquals("Önce terminal seçin", directEntryLabel(""))
    }
}
