package com.dynops.bcwms.feature

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AllItemLabelsTest {
    @Test fun `2054 items become 42 requests of at most 50`() {
        val nos = (1..2054).map { "ITEM-$it" }
        val batches = allItemLabelBatches(nos)
        assertEquals(42, batches.size)
        assertTrue(batches.all { it.size <= ALL_ITEM_LABELS_BATCH })
        assertEquals(2054, batches.sumOf { it.size })
    }

    @Test fun `blank and repeated numbers are dropped, real numbers kept as is`() {
        val batches = allItemLabelBatches(listOf("( DKC 9X19 )", " ", "şevrotin 9.10 mm", "( dkc 9x19 )", "ŞEVROTİN 9.10 MM"))
        assertEquals(listOf("( DKC 9X19 )", "şevrotin 9.10 mm", "ŞEVROTİN 9.10 MM"), batches.single())
    }

    @Test fun `payload carries the item list as a JSON string`() {
        val body = JSONObject(allItemLabelsPayload(listOf("A", "( B )"), "P1"))
        assertEquals("P1", body.getString("printerId"))
        assertEquals(listOf("A", "( B )"), JSONArray(body.getString("itemNosJson")).let { a -> (0 until a.length()).map(a::getString) })
    }

    @Test fun `stop ends after the batch in flight`() = runBlocking {
        var stop = false
        var calls = 0
        val outcome = sendAllItemLabels(
            listOf(listOf("A", "B"), listOf("C"), listOf("D")),
            send = { batch -> calls++; stop = true; Result.success(batch.size) },
            stopRequested = { stop },
        )
        assertEquals(1, calls)
        assertEquals(2, outcome.sent)
        assertTrue(outcome.stopped)
        assertNull(outcome.error)
    }

    @Test fun `an error stops without retrying and reports what was sent`() = runBlocking {
        var calls = 0
        val outcome = sendAllItemLabels(
            listOf(listOf("A"), listOf("B"), listOf("C")),
            send = { calls++; if (calls == 2) Result.failure(IllegalStateException("yazıcı yok")) else Result.success(1) },
            stopRequested = { false },
        )
        assertEquals(2, calls)
        assertEquals(1, outcome.sent)
        assertFalse(outcome.stopped)
        assertEquals("yazıcı yok", outcome.error)
    }
}
