package com.dynops.bcwms.feature

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class InquiryLabelBatchTest {
    @Test fun `same product queried by LP and item is offered once`() {
        fun entry(query: String, no: String?) = InquiryItemEntry(query,
            no?.let { JSONObject().put("no", it) }, emptyList(), emptyList(), "", "AD", "3")
        val products = inquiryLabelProducts(listOf(entry("LP1", "A"), entry("A", "a"), entry("B", "B"), entry("LP2", null)))
        assertEquals(listOf("A", "B"), products.map { it.itemNo })
        assertEquals(listOf("3", "3"), products.map { it.copies })
    }

    @Test fun `different quantities use the existing ten copy limit for each product`() = runBlocking {
        val requests = mutableListOf<Pair<String, Int>>()
        val result = sendInquiryLabelBatch(listOf(InquiryLabelJob("A", 12), InquiryLabelJob("B", 3)), send = { no, copies ->
            requests += no to copies
            Result.success(Unit)
        })
        assertEquals(listOf("A" to 10, "A" to 2, "B" to 3), requests)
        assertTrue(result.complete)
        assertEquals(mapOf("A" to 12, "B" to 3), result.sentCopies)
        assertEquals(15, result.totalSent)
    }

    @Test fun `failure stops without retrying or sending later products and retains confirmed copies`() = runBlocking {
        val requests = mutableListOf<Pair<String, Int>>()
        val result = sendInquiryLabelBatch(listOf(InquiryLabelJob("A", 2), InquiryLabelJob("B", 15), InquiryLabelJob("C", 1)), send = { no, copies ->
            requests += no to copies
            if (no == "B" && copies == 5) Result.failure(IllegalStateException("offline")) else Result.success(Unit)
        })
        assertEquals(listOf("A" to 2, "B" to 10, "B" to 5), requests)
        assertEquals(mapOf("A" to 2, "B" to 10), result.sentCopies)
        assertFalse(result.complete)
        assertEquals("B", result.failedItemNo)
    }

    @Test fun `network exception preserves earlier confirmed jobs`() = runBlocking {
        val result = sendInquiryLabelBatch(listOf(InquiryLabelJob("A", 1), InquiryLabelJob("B", 2)), send = { no, _ ->
            if (no == "B") throw java.io.IOException("timeout")
            Result.success(Unit)
        })
        assertEquals(mapOf("A" to 1), result.sentCopies)
        assertEquals("B", result.failedItemNo)
    }

    @Test fun `invalid batch is rejected before any request`() = runBlocking {
        var requests = 0
        for (jobs in listOf(emptyList(), listOf(InquiryLabelJob("A", 0)), listOf(InquiryLabelJob("A", 1), InquiryLabelJob("a", 2)))) {
            try {
                sendInquiryLabelBatch(jobs, send = { _, _ -> requests++; Result.success(Unit) })
                fail("Invalid batch accepted")
            } catch (_: IllegalArgumentException) { }
        }
        assertEquals(0, requests)
    }

    @Test fun `cancellation is not converted into success or retried`() = runBlocking {
        try {
            sendInquiryLabelBatch(listOf(InquiryLabelJob("A", 1)), send = { _, _ -> throw CancellationException() })
            fail("Cancellation swallowed")
        } catch (_: CancellationException) { }
    }
}
