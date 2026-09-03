package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CountWorkflowTest {
    @Test
    fun `explicit counted flag preserves a physical zero count`() {
        assertTrue(isCountRecorded(hasExplicitFlag = true, explicitFlag = true, quantity = 0.0))
    }

    @Test
    fun `explicit false is not confused with a zero count`() {
        assertFalse(isCountRecorded(hasExplicitFlag = true, explicitFlag = false, quantity = 0.0))
    }

    @Test
    fun `legacy nonzero count remains recognized without flag`() {
        assertTrue(isCountRecorded(hasExplicitFlag = false, explicitFlag = false, quantity = 4.0))
    }

    @Test
    fun `lotless count is blocked when positive lot balances exist`() {
        assertTrue(countLineNeedsLotSelection(lineLotNo = "", positiveLotNos = listOf("LOT-A", "LOT-B")))
    }

    @Test
    fun `selected lot line accepts its own count quantity`() {
        assertFalse(countLineNeedsLotSelection(lineLotNo = "LOT-A", positiveLotNos = listOf("LOT-A", "LOT-B")))
    }

    @Test
    fun `untracked stock remains countable`() {
        assertFalse(countLineNeedsLotSelection(lineLotNo = "", positiveLotNos = emptyList()))
    }

    @Test
    fun `plain barcode matching an active count lot is resolved as lot`() {
        assertTrue(shouldResolvePlainCountBarcodeAsLot(hasLocalLotMatch = true, itemExistsInBc = false))
    }

    @Test
    fun `plain barcode not found as an item is resolved through BC lot lookup`() {
        assertTrue(shouldResolvePlainCountBarcodeAsLot(hasLocalLotMatch = false, itemExistsInBc = false))
    }

    @Test
    fun `confirmed item outside the bin keeps unexpected stock flow`() {
        assertFalse(shouldResolvePlainCountBarcodeAsLot(hasLocalLotMatch = false, itemExistsInBc = true))
    }

    @Test
    fun `empty complete sheet can generate but cannot post`() {
        val actions = countDocumentActions(0, busy = false, linesComplete = true, headerLoaded = true, activeSlotComplete = false)
        assertTrue(actions.canGenerateLines)
        assertFalse(actions.canStartRecount)
        assertFalse(actions.canPost)
    }

    @Test
    fun `loaded sheet can recount and post but cannot regenerate`() {
        val actions = countDocumentActions(12, busy = false, linesComplete = true, headerLoaded = true, activeSlotComplete = true)
        assertFalse(actions.canGenerateLines)
        assertTrue(actions.canStartRecount)
        assertTrue(actions.canPost)
    }

    @Test
    fun `posted sheet and unassigned operator cannot mutate counts`() {
        val posted = countDocumentActions(
            3, false, true, true, true,
            status = "Posted",
        )
        val unassigned = countDocumentActions(
            3, false, true, true, true,
            activeSlotAssigned = false,
        )
        assertFalse(posted.canGenerateLines || posted.canStartRecount || posted.canPost)
        assertFalse(unassigned.canGenerateLines || unassigned.canStartRecount || unassigned.canPost)
    }

    @Test
    fun `recount mismatch blocks posting but still permits a new recount`() {
        val actions = countDocumentActions(
            3, false, true, true, true,
            hasRecountRequired = true,
        )
        assertTrue(actions.canStartRecount)
        assertFalse(actions.canPost)
    }

    @Test
    fun `operator sees only their BC assigned count slot`() {
        val assignments = listOf(
            CountSlotAssignment(1, "SAYICI-A"),
            CountSlotAssignment(2, "SAYICI-B"),
        )
        assertTrue(assignedCountSlotsForOperator(assignments, "sayici-b", false) == listOf(2))
        assertTrue(assignedCountSlotsForOperator(assignments, "", true) == listOf(1, 2))
        assertTrue(assignedCountSlotsForOperator(emptyList(), "LEGACY", false) == listOf(1))
        assertTrue(assignedCountSlotsForOperator(assignments, "BASKA", false).isEmpty())
    }

    @Test
    fun `partial failed or busy load blocks every destructive count action`() {
        val partial = countDocumentActions(200, busy = false, linesComplete = false, headerLoaded = true, activeSlotComplete = true)
        val busy = countDocumentActions(200, busy = true, linesComplete = true, headerLoaded = true, activeSlotComplete = true)
        assertFalse(partial.canGenerateLines || partial.canStartRecount || partial.canPost)
        assertFalse(busy.canGenerateLines || busy.canStartRecount || busy.canPost)
    }

    @Test
    fun `explicit zero completes the active counter slot`() {
        val complete = allRequiredCountLinesExplicitlyCompleted(
            listOf(
                CountSlotLineState(hasExplicitFlag = true, explicitlyCounted = true, quantity = 0.0),
                CountSlotLineState(hasExplicitFlag = true, explicitlyCounted = true, quantity = 4.0),
            )
        )
        assertTrue(complete)
    }

    @Test
    fun `missing active slot flag blocks posting even when legacy quantity is nonzero`() {
        val complete = allRequiredCountLinesExplicitlyCompleted(
            listOf(CountSlotLineState(hasExplicitFlag = false, explicitlyCounted = false, quantity = 4.0))
        )
        val actions = countDocumentActions(1, false, true, true, activeSlotComplete = complete)
        assertFalse(complete)
        assertFalse(actions.canPost)
    }

    @Test
    fun `one incomplete line blocks the whole count document`() {
        val complete = allRequiredCountLinesExplicitlyCompleted(
            listOf(
                CountSlotLineState(hasExplicitFlag = true, explicitlyCounted = true, quantity = 1.0),
                CountSlotLineState(hasExplicitFlag = true, explicitlyCounted = false, quantity = 0.0),
            )
        )
        assertFalse(complete)
    }

    @Test
    fun `sequential write progress distinguishes partial persistence from completion`() {
        val partial = sequentialWriteProgress(total = 4, succeeded = 2)
        val complete = sequentialWriteProgress(total = 4, succeeded = 4)

        assertTrue(partial.partial)
        assertFalse(partial.complete)
        assertFalse(complete.partial)
        assertTrue(complete.complete)
    }

    @Test
    fun `sequential write progress clamps invalid counters fail closed`() {
        val negative = sequentialWriteProgress(total = 3, succeeded = -1)
        val overflow = sequentialWriteProgress(total = 3, succeeded = 99)
        val empty = sequentialWriteProgress(total = 0, succeeded = 0)

        assertFalse(negative.partial || negative.complete)
        assertFalse(overflow.partial || overflow.complete)
        assertFalse(empty.partial || empty.complete)
    }

    @Test
    fun `classic count retries without assignment when local wms user is unavailable`() {
        assertTrue(
            shouldRetryClassicCountWithoutCounter(
                "The field User ID of table Count Counter contains a value that cannot be found in the related table (Local WMS User)."
            )
        )
        assertFalse(shouldRetryClassicCountWithoutCounter("Location MERKEZDEPO does not exist."))
    }

    @Test
    fun `older AL package without terminalPostAllowed keeps posting enabled`() {
        assertTrue(terminalCountPostAllowed(hasFlag = false, flag = false))
        assertTrue(terminalCountPostAllowed(hasFlag = false, flag = true))
    }

    @Test
    fun `explicit terminalPostAllowed flag is authoritative`() {
        assertTrue(terminalCountPostAllowed(hasFlag = true, flag = true))
        assertFalse(terminalCountPostAllowed(hasFlag = true, flag = false))
    }

    @Test
    fun `classic primary button saves the round before anything else`() {
        val state = classicCountPrimaryButtonState(
            interactive = true,
            activeSlotSaved = false,
            allRequiredSaved = false,
            canPost = false,
            terminalPostAllowed = false,
        )
        assertEquals("✅ Turu Kaydet", state.label)
        assertTrue(state.enabled)
        assertFalse(state.opensPostConfirm)
    }

    @Test
    fun `classic primary button posts after save when terminal posting is allowed`() {
        val ready = classicCountPrimaryButtonState(
            interactive = true,
            activeSlotSaved = true,
            allRequiredSaved = true,
            canPost = true,
            terminalPostAllowed = true,
        )
        assertEquals("Stoklara İşle", ready.label)
        assertTrue(ready.enabled)
        assertTrue(ready.opensPostConfirm)

        val waitingForOthers = classicCountPrimaryButtonState(
            interactive = true,
            activeSlotSaved = true,
            allRequiredSaved = false,
            canPost = true,
            terminalPostAllowed = true,
        )
        assertTrue(waitingForOthers.enabled)
        assertFalse(waitingForOthers.opensPostConfirm)

        val busy = classicCountPrimaryButtonState(
            interactive = false,
            activeSlotSaved = true,
            allRequiredSaved = true,
            canPost = true,
            terminalPostAllowed = true,
        )
        assertFalse(busy.enabled)
        assertFalse(busy.opensPostConfirm)
    }

    @Test
    fun `classic primary button never opens post confirmation when terminal posting is disabled`() {
        val state = classicCountPrimaryButtonState(
            interactive = true,
            activeSlotSaved = true,
            allRequiredSaved = true,
            canPost = true,
            terminalPostAllowed = false,
        )
        assertEquals("✓ Tur Kaydedildi", state.label)
        assertFalse(state.enabled)
        assertFalse(state.opensPostConfirm)
    }

    @Test
    fun `round saved message explains BC posting only when terminal posting is disabled`() {
        val allowed = countRoundSavedMessage(slot = 2, terminalPostAllowed = true)
        val disabled = countRoundSavedMessage(slot = 2, terminalPostAllowed = false)

        assertTrue(allowed.startsWith("TAMAM: 2. sayım turu kaydedildi"))
        assertFalse(allowed.contains(COUNT_POSTED_IN_BC_NOTE))
        assertTrue(disabled.startsWith("TAMAM: 2. sayım turu kaydedildi"))
        assertTrue(disabled.contains(COUNT_POSTED_IN_BC_NOTE))
        assertFalse(disabled.contains("REF-"))
    }

    @Test
    fun `BC posting note appears once the round is saved and is not duplicated`() {
        assertTrue(showsCountPostedInBcNote(terminalPostAllowed = false, activeSlotSaved = true, documentStatus = "InProgress", currentStatusText = ""))
        assertTrue(showsCountPostedInBcNote(terminalPostAllowed = false, activeSlotSaved = true, documentStatus = "InProgress", currentStatusText = "TAMAM: Satırlar yenilendi"))
        assertFalse(showsCountPostedInBcNote(terminalPostAllowed = false, activeSlotSaved = false, documentStatus = "InProgress", currentStatusText = ""))
        assertFalse(showsCountPostedInBcNote(terminalPostAllowed = true, activeSlotSaved = true, documentStatus = "InProgress", currentStatusText = ""))
        assertFalse(showsCountPostedInBcNote(terminalPostAllowed = false, activeSlotSaved = true, documentStatus = "Posted", currentStatusText = ""))
        assertFalse(
            showsCountPostedInBcNote(
                terminalPostAllowed = false,
                activeSlotSaved = true,
                documentStatus = "InProgress",
                currentStatusText = countRoundSavedMessage(1, terminalPostAllowed = false),
            )
        )
    }

    @Test
    fun `counted LP numbers for labels are trimmed, de-duplicated and keep line order`() {
        assertEquals(
            listOf("LP-002", "LP-001"),
            countedLpNosForLabels(listOf(" LP-002 ", "", "LP-001", "LP-002", "   ")),
        )
        assertTrue(countedLpNosForLabels(emptyList()).isEmpty())
        assertTrue(countedLpNosForLabels(listOf("", " ")).isEmpty())
    }

    @Test
    fun `counted LP label reprint is offered only on a posted sheet with LP lines`() {
        assertTrue(showsCountedLpLabelReprint("Posted", 1))
        assertTrue(showsCountedLpLabelReprint("posted", 3))
        assertFalse(showsCountedLpLabelReprint("Posted", 0))
        assertFalse(showsCountedLpLabelReprint("InProgress", 2))
        assertFalse(showsCountedLpLabelReprint("Open", 2))
        assertFalse(showsCountedLpLabelReprint("", 2))
    }

    @Test
    fun `LP label print status keeps the terminal post wording and stays operator safe`() {
        assertEquals(
            "TAMAM: Sayım kaydedildi; 3 LP etiketi güncel miktarla yazdırıldı",
            countedLpLabelPrintStatus(afterPost = true, lpCount = 3, printFailures = 0),
        )
        assertEquals(
            "UYARI: Sayım kaydedildi; 1 LP etiketi yazdırılamadı",
            countedLpLabelPrintStatus(afterPost = true, lpCount = 3, printFailures = 1),
        )
        assertEquals(
            "TAMAM: 2 LP etiketi güncel miktarla yazdırıldı",
            countedLpLabelPrintStatus(afterPost = false, lpCount = 2, printFailures = 0),
        )
        assertEquals(
            "UYARI: 2 LP etiketi yazdırılamadı",
            countedLpLabelPrintStatus(afterPost = false, lpCount = 2, printFailures = 2),
        )
        assertFalse(countedLpLabelPrintStatus(afterPost = false, lpCount = 2, printFailures = 2).contains("REF-"))
    }
}
