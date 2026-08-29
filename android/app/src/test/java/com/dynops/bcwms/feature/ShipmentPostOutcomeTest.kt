package com.dynops.bcwms.feature

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShipmentPostOutcomeTest {
    @Test
    fun `successful action is committed`() {
        assertTrue(shipmentPostCommitted(actionOk = true, verificationHttpCode = null))
    }

    @Test
    fun `missing open document after action error means post committed`() {
        assertTrue(shipmentPostCommitted(actionOk = false, verificationHttpCode = 404))
    }

    @Test
    fun `existing open document preserves original post failure`() {
        assertFalse(shipmentPostCommitted(actionOk = false, verificationHttpCode = 200))
    }
}
