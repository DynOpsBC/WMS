package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DkcPickWorkflowTest {
    private fun line(
        lineNo: Int,
        quantity: Double,
        toHandle: Double,
        handled: Double = 0.0,
        action: String = "Take",
    ) = JSONObject()
        .put("lineNo", lineNo)
        .put("actionType", action)
        .put("itemNo", "KLC-4")
        .put("quantity", quantity)
        .put("qtyOutstanding", quantity - handled)
        .put("qtyToHandle", toHandle)
        .put("qtyHandled", handled)

    @Test
    fun bcPrefilledQuantityIsNotAnOperatorEntry() {
        // BC fills Qty. to Handle with the outstanding quantity when the pick is created.
        val prefilled = line(10000, 525.0, 525.0)
        val entries = emptyMap<Int, PickEntry>()
        assertEquals(0.0, pickEnteredQty(prefilled, entries), 0.0)
        assertFalse(pickRowDone(prefilled, entries))
        assertFalse(pickRowPartial(prefilled, entries))
        assertTrue(pickPostLines(listOf(prefilled), entries).isEmpty())
        assertEquals(listOf(10000), pickLinesToClear(listOf(prefilled), entries).map { it.optInt("lineNo") })
    }

    @Test
    fun partialEntryIsPartialAndFullEntryIsDone() {
        val partial = line(10000, 525.0, 200.0)
        val full = line(30000, 40.0, 40.0)
        val entries = mapOf(10000 to PickEntry(200.0, 0.0), 30000 to PickEntry(40.0, 0.0))
        assertTrue(pickRowPartial(partial, entries))
        assertFalse(pickRowDone(partial, entries))
        assertTrue(pickRowDone(full, entries))
        assertFalse(pickRowPartial(full, entries))
        assertEquals(listOf(10000, 30000), pickPostLines(listOf(partial, full), entries).map { it.optInt("lineNo") })
    }

    @Test
    fun onlyUntouchedPrefilledLinesAreCleared() {
        val entered = line(10000, 525.0, 200.0)
        val untouchedPrefilled = line(30000, 40.0, 40.0)
        val untouchedZero = line(50000, 12.0, 0.0)
        val entries = mapOf(10000 to PickEntry(200.0, 0.0))
        assertEquals(
            listOf(30000),
            pickLinesToClear(listOf(entered, untouchedPrefilled, untouchedZero), entries).map { it.optInt("lineNo") },
        )
    }

    @Test
    fun postIsBlockedUntilServerMatchesTheEntries() {
        val entered = line(10000, 525.0, 200.0)
        val stillPrefilled = line(30000, 40.0, 40.0)
        val entries = mapOf(10000 to PickEntry(200.0, 0.0))
        assertEquals(listOf(30000), pickPostMismatches(listOf(entered, stillPrefilled), entries))
        val cleared = line(30000, 40.0, 0.0)
        assertTrue(pickPostMismatches(listOf(entered, cleared), entries).isEmpty())
    }

    @Test
    fun entryIsDroppedWhenTheServerQuantityChangedElsewhere() {
        val changed = line(10000, 525.0, 300.0)
        val entries = mapOf(10000 to PickEntry(200.0, 0.0))
        assertEquals(0.0, pickEnteredQty(changed, entries), 0.0)
        // A changed line is treated like an untouched one: it is cleared, never posted.
        assertEquals(listOf(10000), pickLinesToClear(listOf(changed), entries).map { it.optInt("lineNo") })
        assertTrue(prunePickEntries(listOf(changed), entries).isEmpty())
    }

    @Test
    fun entryIsDroppedAfterTheLineWasRegistered() {
        // 525 ordered, the operator entered 262.5 and the register answer was lost. BC registered
        // it and refilled Qty. to Handle with the new outstanding 262.5 — the same number.
        val afterRegister = line(10000, 525.0, 262.5, handled = 262.5)
        val entries = mapOf(10000 to PickEntry(262.5, 0.0))
        assertEquals(0.0, pickEnteredQty(afterRegister, entries), 0.0)
        assertTrue(pickPostLines(listOf(afterRegister), entries).isEmpty())
        assertTrue(prunePickEntries(listOf(afterRegister), entries).isEmpty())
    }

    @Test
    fun remainderOfAPartlyRegisteredLineCanBeEnteredAgain() {
        val remainder = line(10000, 525.0, 325.0, handled = 200.0)
        val entries = mapOf(10000 to PickEntry(325.0, 200.0))
        assertTrue(pickRowDone(remainder, entries))
        val part = line(10000, 525.0, 100.0, handled = 200.0)
        assertTrue(pickRowPartial(part, mapOf(10000 to PickEntry(100.0, 200.0))))
    }

    @Test
    fun placeLinesAreNotPickedByTheOperator() {
        val take = line(10000, 525.0, 525.0)
        val place = line(20000, 525.0, 525.0, action = "Place")
        assertEquals(listOf(10000), pickTakeLines(listOf(take, place)).map { it.optInt("lineNo") })
    }

    @Test
    fun entriesSurviveTheDeviceStore() {
        val entries = mapOf(10000 to PickEntry(200.0, 0.0), 30000 to PickEntry(12.345, 7.5))
        assertEquals(entries, decodePickEntries(encodePickEntries(entries)))
        assertTrue(decodePickEntries("").isEmpty())
        assertTrue(decodePickEntries("abc;10000:x:0;20000:5").isEmpty())
        assertEquals(mapOf(10000 to PickEntry(5.0, 0.0)), decodePickEntries("10000:5.0:0.0;30000:0.0:0.0;bad"))
    }
}
