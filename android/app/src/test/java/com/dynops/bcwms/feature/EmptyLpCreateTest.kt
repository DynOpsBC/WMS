package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EmptyLpCreateTest {
    private val locations = listOf(BulkLpLocationOption("DEPO1", "Ana"), BulkLpLocationOption("DEPO2", ""))

    @Test
    fun `offered only on Kitoko`() {
        assertTrue(emptyLpCreateOffered("kitoko"))
        assertFalse(emptyLpCreateOffered("bade"))
    }

    @Test
    fun `count is limited to 1 to 50`() {
        assertEquals(1, parseEmptyLpCount("1"))
        assertEquals(50, parseEmptyLpCount(" 50 "))
        assertNull(parseEmptyLpCount("0"))
        assertNull(parseEmptyLpCount("51"))
        assertNull(parseEmptyLpCount("abc"))
    }

    @Test
    fun `payload omits blank bin`() {
        val withBin = JSONObject(emptyLpCreatePayload("PALLET-EUR", "DEPO1", "A-01"))
        assertEquals("A-01", withBin.getString("binCode"))
        val noBin = JSONObject(emptyLpCreatePayload(" PALLET-EUR ", "DEPO1", " "))
        assertFalse(noBin.has("binCode"))
        assertEquals("PALLET-EUR", noBin.getString("templateCode"))
        assertEquals("DEPO1", noBin.getString("locationCode"))
    }

    @Test
    fun `default location prefers user setup then last used then single`() {
        assertEquals("DEPO2", emptyLpDefaultLocation("depo2", "DEPO1", locations))
        assertEquals("DEPO1", emptyLpDefaultLocation("YOK", "DEPO1", locations))
        assertEquals("", emptyLpDefaultLocation("", "", locations))
        assertEquals("DEPO1", emptyLpDefaultLocation("", "", locations.take(1)))
    }

    @Test
    fun `default template is last used else pallet policy`() {
        val rows = listOf("CARTON-S" to "Koli", "PALLET-EUR" to "Euro palet")
        assertEquals("PALLET-EUR", emptyLpDefaultTemplate(rows, ""))
        assertEquals("CARTON-S", emptyLpDefaultTemplate(rows, "carton-s"))
        assertEquals("PALLET-EUR", emptyLpDefaultTemplate(rows, "SILINMIS"))
    }

    @Test
    fun `status reports created numbers and partial failure`() {
        assertEquals("TAMAM: 2 boş LP oluşturuldu: LP1, LP2", emptyLpCreateStatus(listOf("LP1", "LP2"), 2, ""))
        assertTrue(emptyLpCreateStatus(listOf("LP1"), 3, "raf yok").startsWith("UYARI: 3 LP'den 1"))
        assertEquals("HATA: LP oluşturulamadı: raf yok", emptyLpCreateStatus(emptyList(), 1, "raf yok"))
    }
}
