package com.dynops.bcwms.feature

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExcelLabelResumeTest {
    private fun rows(vararg orders: Int) = orders.map { ExcelLabelRow(it, "IT$it", "Ürün $it", "Z$it") }

    @Test
    fun `batches split at a skipped row so BC sees consecutive orders`() {
        val list = rows(*((501..531) + (533..600)).toIntArray())
        val batches = excelLabelBatches(list)
        assertEquals(listOf(501 to 531, 533 to 582, 583 to 600), batches.map { it.first().order to it.last().order })
        batches.forEach { b -> b.zipWithNext().forEach { (a, c) -> assertEquals(a.order + 1, c.order) } }
    }

    @Test
    fun `resume continues after the last confirmed order`() {
        val list = rows(*(1..1535).toList().toIntArray())
        val rest = rowsAfterOrder(list, 500)
        assertEquals(501, rest.first().order)
        assertEquals(1035, rest.size)
        assertEquals(501, uncertainRangeStart("501–551"))
        assertNull(uncertainRangeStart(""))
    }

    private fun job(status: String, source: String = "EXCEL") =
        JSONObject().put("jobId", 1).put("sourceDoc", source).put("status", status).put("lastError", "")

    @Test
    fun `next batch waits until the EXCEL job leaves the queue`() = runBlocking {
        val answers = ArrayDeque(listOf(null, listOf(job("Dispatched", "OTHER")), listOf(job("Queued")), listOf(job("Dispatched"))))
        var pauses = 0
        assertNull(awaitExcelJob("501–531", fetchJobs = { answers.removeFirst() }, pause = { pauses++ }))
        assertEquals(3, pauses)
        val stuck = awaitExcelJob("501–531", fetchJobs = { listOf(job("Queued")) }, pause = {}, pollMs = 1_000, maxWaitMs = 2_000)
        assertTrue(stuck!!.contains("kalanlar gönderilmedi"))
    }
}
