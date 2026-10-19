package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class LabelCopiesTest {
    @Test fun `label count is split into jobs the print agent accepts`() {
        assertEquals(listOf(1), labelCopyBatches(1))
        assertEquals(listOf(10), labelCopyBatches(10))
        assertEquals(listOf(10, 1), labelCopyBatches(11))
        assertEquals(listOf(10, 10, 5), labelCopyBatches(25))
        assertEquals(99, labelCopyBatches(99).sum())
        assertTrue(labelCopyBatches(99).all { it in 1..LABEL_COPIES_PER_JOB })
        assertEquals(listOf(1), labelCopyBatches(0))
        assertEquals(99, labelCopyBatches(500).sum())
    }

    @Test fun `only whole counts between 1 and 99 are accepted`() {
        assertEquals(5, parseLabelCopies("5"))
        assertEquals(12, parseLabelCopies(" 12 "))
        assertEquals(99, parseLabelCopies("99"))
        assertNull(parseLabelCopies(""))
        assertNull(parseLabelCopies("0"))
        assertNull(parseLabelCopies("100"))
        assertNull(parseLabelCopies("3,5"))
    }

    @Test fun `zones keep their description and bins sort the way the aisle runs`() {
        val zones = inquiryZoneChoices(listOf(
            JSONObject().put("code", "HAMMADDE").put("description", "HAMMADDE"),
            JSONObject().put("code", "AKILLI DOL").put("description", "AKILLI DOLAP SİSTEMİ"),
            JSONObject().put("code", "").put("description", "Kodsuz"),
            JSONObject().put("code", "akilli dol").put("description", "Tekrar"),
        ))
        assertEquals(listOf("AKILLI DOL" to "AKILLI DOLAP SİSTEMİ", "HAMMADDE" to "HAMMADDE"), zones)

        val bins = sortedBinCodes(listOf("A10", "A2", "A100", "A1", "B1").map { JSONObject().put("code", it) })
        assertEquals(listOf("A1", "A2", "A10", "A100", "B1"), bins.map { it.optString("code") })
        val numbered = sortedBinCodes(listOf("RAF001", "RAF120", "RAF089", "RAF002")
            .map { JSONObject().put("code", it) })
        assertEquals(listOf("RAF001", "RAF002", "RAF089", "RAF120"), numbered.map { it.optString("code") })
    }

    @Test fun `locations come from the BCWMS API or the standard API`() {
        val bcwms = listOf(
            JSONObject().put("code", "DKC").put("name", "DKÇ Merkez").put("useAsInTransit", false),
            JSONObject().put("code", "YOLDA").put("name", "Transfer").put("useAsInTransit", true),
        )
        assertEquals(listOf("DKC" to "DKÇ Merkez"), inquiryLocationChoices(bcwms))
        val standard = listOf(
            JSONObject().put("code", "DKC").put("displayName", "DKÇ Merkez"),
            JSONObject().put("code", "").put("displayName", "Boş kod"),
            JSONObject().put("code", "dkc").put("displayName", "Tekrar"),
        )
        assertEquals(listOf("DKC" to "DKÇ Merkez"), inquiryLocationChoices(standard))
    }
}
