package com.dynops.bcwms.feature

import kotlinx.coroutines.*
import org.junit.Assert.assertEquals
import org.junit.Test

class LatestStockInquiryTest {
    @Test fun `rapid scans cancel previous results and complete cleanup before latest`() = runBlocking {
        val loader = LatestStockInquiry(this)
        val started = CompletableDeferred<Unit>()
        val done = CompletableDeferred<Unit>()
        val events = mutableListOf<String>()
        loader.submit {
            try {
                started.complete(Unit)
                awaitCancellation()
            } finally {
                withContext(NonCancellable) { delay(20); events += "old-cleanup" }
            }
        }
        started.await()
        loader.submit { events += "superseded" }
        yield()
        loader.submit { events += "latest-result"; done.complete(Unit) }
        done.await()
        assertEquals(listOf("old-cleanup", "latest-result"), events)
    }
}
