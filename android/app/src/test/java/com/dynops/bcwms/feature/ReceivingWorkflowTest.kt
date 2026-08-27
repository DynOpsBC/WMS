package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceivingWorkflowTest {
    @Test
    fun `successful LP start survives an immediately stale receipt reload`() {
        assertEquals("LP000041", resolvedActiveReceiptLp("", false, "LP000041"))
    }

    @Test
    fun `server active LP wins after receipt reload`() {
        assertEquals("LP000042", resolvedActiveReceiptLp(" LP000042 ", true, "LP000041"))
    }

    @Test
    fun `normal reload clears a closed LP`() {
        assertNull(resolvedActiveReceiptLp("LP000041", false))
    }

    @Test
    fun `preflight failure reports partial reset and requires reconciliation`() {
        val status = receivingPreflightFailureStatus(resetCount = 2)

        assertTrue(status.startsWith("UYARI: 2 satır sıfırlandı"))
        assertTrue(status.contains("Belge yenilendi"))
        assertTrue(status.contains("mal kabul kaydedilmedi"))
    }

    @Test
    fun `preflight failure without writes remains fail closed`() {
        val status = receivingPreflightFailureStatus(resetCount = 0)

        assertTrue(status.startsWith("HATA:"))
        assertTrue(status.contains("mal kabul kaydedilmedi"))
    }
}
