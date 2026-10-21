package com.dynops.bcwms.feature

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PrintBatchOrderTest {
    private fun job(source: String, status: String, error: String = "") =
        JSONObject().put("jobId", 1).put("sourceDoc", source).put("status", status).put("lastError", error)

    private val batch = listOf("IT0051", "IT0052", "IT0100")

    @Test
    fun `batch waits until its own job leaves the queue`() {
        assertEquals(PrintBatchState.Waiting, printBatchState(emptyList(), batch))
        assertEquals(PrintBatchState.Waiting, printBatchState(listOf(job("OTHER", "Dispatched")), batch))
        assertEquals(PrintBatchState.Waiting, printBatchState(listOf(job("it0051", "Queued")), batch))
        assertEquals(PrintBatchState.Delivered, printBatchState(listOf(job("IT0051", "Dispatched")), batch))
        assertEquals(PrintBatchState.Delivered, printBatchState(listOf(job("IT0051", "Sent")), batch))
        assertEquals(PrintBatchState.Failed("blob"), printBatchState(listOf(job("IT0051", "Failed", "blob")), batch))
    }

    @Test
    fun `next batch is released only after dispatch`() = runBlocking {
        val answers = ArrayDeque(listOf(null, emptyList(), listOf(job("IT0051", "Queued")), listOf(job("IT0051", "Dispatched"))))
        var pauses = 0
        val error = awaitPrintBatch(batch, fetchJobs = { answers.removeFirst() }, pause = { pauses++ })
        assertNull(error)
        assertEquals(3, pauses)
    }

    @Test
    fun `stuck or failed batch stops the remaining batches`() = runBlocking {
        val stuck = awaitPrintBatch(batch, fetchJobs = { listOf(job("IT0051", "Queued")) }, pause = {}, pollMs = 1_000, maxWaitMs = 3_000)
        assertTrue(stuck!!.contains("kalan etiketler gönderilmedi"))
        val failed = awaitPrintBatch(batch, fetchJobs = { listOf(job("IT0051", "Failed", "HTTP 403")) }, pause = {})
        assertTrue(failed!!.contains("HTTP 403"))
    }
}
