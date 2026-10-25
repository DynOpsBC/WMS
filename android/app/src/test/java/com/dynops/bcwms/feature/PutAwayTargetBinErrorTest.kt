package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** BADE (25 Eki 2026): yerleştirmede olmayan / uygun olmayan hedef raf sessiz kalmamalı. */
class PutAwayTargetBinErrorTest {
    private fun bin(code: String, block: String = "", message: String = "", blockMovement: String = "_x0020_") =
        JSONObject().put("code", code).put("putAwayBlock", block).put("putAwayBlockMessage", message)
            .put("blockMovement", blockMovement)

    @Test
    fun `lokasyonda olmayan raf acik Turkce hata verir`() {
        assertEquals(
            "❌ A.A01.19 rafı MERKEZDEPO lokasyonunda yok. Raf kodunu kontrol edip tekrar okutun.",
            putAwayTargetBinError("A.A01.19", "MERKEZDEPO", null),
        )
    }

    @Test
    fun `uygun raf kabul edilir`() {
        assertNull(putAwayTargetBinError("A.A01.13", "MERKEZDEPO", bin("A.A01.13")))
    }

    @Test
    fun `sunucu mesaji varsa aynen gosterilir`() {
        val error = putAwayTargetBinError(
            "KABUL", "MERKEZDEPO",
            bin("KABUL", "receive", "KABUL rafı mal kabul gözüdür; yerleştirme hedefi olamaz. Başka bir raf okutun."),
        )
        assertEquals("❌ KABUL rafı mal kabul gözüdür; yerleştirme hedefi olamaz. Başka bir raf okutun.", error)
    }

    @Test
    fun `neden kodlari mesajsiz da anlasilir`() {
        assertTrue(putAwayTargetBinError("S1", "L", bin("S1", "ship"))!!.contains("sevkiyat gözü"))
        assertTrue(putAwayTargetBinError("D1", "L", bin("D1", "adjustment"))!!.contains("düzeltme"))
        assertTrue(putAwayTargetBinError("B1", "L", bin("B1", "blocked"))!!.contains("yerleştirmeye kapalı"))
    }

    @Test
    fun `eski BC de blockMovement ile bloke raf yakalanir`() {
        val old = JSONObject().put("code", "B1").put("blockMovement", "Inbound")
        assertTrue(putAwayTargetBinError("B1", "L", old)!!.contains("yerleştirmeye kapalı"))
        val outbound = JSONObject().put("code", "B2").put("blockMovement", "Outbound")
        assertNull(putAwayTargetBinError("B2", "L", outbound))
    }

    @Test
    fun `kalite reddi alan LP ret gozune konabilir`() {
        assertNull(putAwayTargetBinError("RET", "L", bin("RET", "blocked"), qualityRejectBin = "ret"))
    }

    @Test
    fun `tam eslesme kismi eslesmeye tercih edilir`() {
        val rows = listOf(JSONObject().put("code", "A.A01.190"), JSONObject().put("code", "A.A01.19"))
        assertEquals("A.A01.19", putAwayExactBinRow(rows, "a.a01.19")!!.optString("code"))
        assertNull(putAwayExactBinRow(listOf(JSONObject().put("code", "A.A01.190")), "A.A01.19"))
    }

    @Test
    fun `toplu yerlestirmede birden cok kismi aday secilmez`() {
        val many = listOf(JSONObject().put("code", "Y.G03.11"), JSONObject().put("code", "Y.G03.12"))
        assertNull(putAwayBatchBinRow(many, "Y.G03"))
        val one = listOf(JSONObject().put("code", "Y.G03.13"))
        assertEquals("Y.G03.13", putAwayBatchBinRow(one, "Y.G03")!!.optString("code"))
        assertEquals("Y.G03.11", putAwayBatchBinRow(many, "y.g03.11")!!.optString("code"))
    }
}
