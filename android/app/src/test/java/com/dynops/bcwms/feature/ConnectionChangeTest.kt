package com.dynops.bcwms.feature

import com.dynops.bcwms.BcApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class ConnectionChangeTest {
    @Test fun failedTargetNeverReplacesTheSavedConnection() = runBlocking {
        for (code in listOf(-1, 401, 403, 404, 500)) {
            var saved = false
            val failure = BcApi.ApiResult(false, code, "unavailable")
            val result = verifyConnectionChange({ failure }, { saved = true })
            assertSame(failure, result)
            assertFalse(saved)
        }
    }

    @Test fun targetIsVerifiedBeforeSavingExactlyOnce() = runBlocking {
        val events = mutableListOf<String>()
        val result = verifyConnectionChange(
            { events += "verify target"; BcApi.ApiResult(true, 200, "ok") },
            { events += "save target" },
        )
        assertTrue(result.ok)
        assertEquals(listOf("verify target", "save target"), events)
    }

    @Test fun leavingWhileVerifyingDoesNotSaveTheDraft() = runBlocking {
        var saved = false
        try {
            verifyConnectionChange({ throw CancellationException("left screen") }, { saved = true })
            fail("Expected cancellation")
        } catch (_: CancellationException) {
            assertFalse(saved)
        }
    }
}
