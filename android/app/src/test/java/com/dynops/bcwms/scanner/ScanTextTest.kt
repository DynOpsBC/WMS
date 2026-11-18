package com.dynops.bcwms.scanner

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ScanTextTest {
    private fun asLatin1(s: String) = String(s.toByteArray(Charsets.UTF_8), Charsets.ISO_8859_1)
    private fun asCp1252(s: String) = String(s.toByteArray(Charsets.UTF_8), charset("windows-1252"))

    @Test
    fun utf8ReadAsLatin1IsRepaired() {
        for (code in listOf("ÜR.0002", "KÜLÇE.HM.0001", "FMJ.NİHAİ.PİRİNÇ.9MM", "ŞEVROTİN.NİHAİ", "ÇELİK UÇ", "DMZ.12CAL.PELLAGRİ")) {
            assertEquals(code, ScanText.repair(asLatin1(code)))
        }
    }

    @Test
    fun utf8ReadAsWindows1252IsRepaired() {
        assertEquals("ÜR.0002", ScanText.repair(asCp1252("ÜR.0002")))
        assertEquals("KÜLÇE.HM.0001", ScanText.repair(asCp1252("KÜLÇE.HM.0001")))
    }

    @Test
    fun correctTextIsLeftAlone() {
        for (code in listOf("ÜR.0002", "MK.0001", "KLC-4", "SEVK.0001", "Café", "LC5.56(2.45-2.50)")) {
            assertEquals(code, ScanText.repair(code))
        }
    }

    @Test
    fun rawBytesWinOverTheScannerText() {
        val bytes = "ÜR.0002".toByteArray(Charsets.UTF_8)
        assertEquals("ÜR.0002", ScanText.best("?R.0002", bytes))
        // Bytes that are not UTF-8 are ignored and the text is repaired instead.
        assertEquals("ÜR.0002", ScanText.best(asLatin1("ÜR.0002"), byteArrayOf(0xDC.toByte(), 0x52)))
        assertEquals("MK.0001", ScanText.best("MK.0001", null))
        assertNull(ScanText.strictUtf8(byteArrayOf(0xC3.toByte())))
    }

    @Test
    fun resolverSeesTheRepairedBinCode() {
        assertEquals("ÜR.0002", BarcodeIntentResolver.resolve(asLatin1("ÜR.0002")).value)
    }
}
