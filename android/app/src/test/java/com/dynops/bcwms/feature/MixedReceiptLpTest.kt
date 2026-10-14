package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class MixedReceiptLpTest {
    private val today = LocalDate.of(2026, 10, 14)

    private fun entry(lineNo: Int, item: String, expected: Double, outstanding: Double = 20020.0, lot: String = "") =
        MixedReceiptLineEntry(lineNo, item, item, "ADET", outstanding, expected, lotRequired = true, lotNo = lot)

    @Test
    fun `BADE scenario splits both products over four pallets`() {
        val pallets = mixedEqualSplit(mapOf(10000 to 20020.0, 20000 to 20020.0), 4)
        assertEquals(4, pallets.size)
        pallets.forEach { pallet ->
            assertEquals(5005.0, pallet[10000]!!, 0.0)
            assertEquals(5005.0, pallet[20000]!!, 0.0)
        }
        val lines = listOf(entry(10000, "AB.02316", 20020.0), entry(20000, "AB.02317", 20020.0))
        assertNull(mixedDistributionValidation(lines, pallets, today))
    }

    @Test
    fun `uneven totals keep whole units per product`() {
        val pallets = mixedEqualSplit(mapOf(10000 to 10.0, 20000 to 7.0), 4)
        assertEquals(listOf(3.0, 3.0, 2.0, 2.0), pallets.map { it[10000] })
        assertEquals(listOf(2.0, 2.0, 2.0, 1.0), pallets.map { it[20000] })
        assertTrue(mixedEqualSplit(mapOf(10000 to 10.0), 0).isEmpty())
    }

    @Test
    fun `few units of one product leave some pallets without it but never a fraction`() {
        val pallets = mixedEqualSplit(mapOf(10000 to 100.0, 20000 to 3.0), 4)
        assertEquals(listOf(1.0, 1.0, 1.0, 0.0), pallets.map { it[20000] })
        assertEquals(listOf(25.0, 25.0, 25.0, 25.0), pallets.map { it[10000] })
        val lines = listOf(entry(10000, "BOTTLE", 100.0, outstanding = 100.0), entry(20000, "CAP", 3.0, outstanding = 3.0))
        assertNull(mixedDistributionValidation(lines, pallets, today))
        assertEquals(listOf(0.83333, 0.83333, 0.83334), mixedLineShares(2.5, 3))
    }

    @Test
    fun `validation catches wrong totals, empty pallets and missing expiry`() {
        val lines = listOf(entry(10000, "AB.02316", 100.0), entry(20000, "AB.02317", 100.0))
        val short = listOf(mapOf(10000 to 50.0, 20000 to 50.0), mapOf(10000 to 40.0, 20000 to 50.0))
        assertTrue(mixedDistributionValidation(lines, short, today)!!.startsWith("AB.02316: paletlere dağıtılan 90"))
        val empty = listOf(mapOf(10000 to 100.0, 20000 to 100.0), mapOf(10000 to 0.0, 20000 to 0.0))
        assertEquals("2. palet boş. Her palete en az bir ürün girin.", mixedDistributionValidation(lines, empty, today))
        assertEquals("Karma palet için en az iki ürün seçin.", mixedDistributionValidation(lines.take(1), short, today))
        val over = listOf(entry(10000, "AB.02316", 30000.0), entry(20000, "AB.02317", 100.0))
        assertTrue(mixedDistributionValidation(over, short, today)!!.contains("açık miktarı"))
        val expiry = listOf(lines[0].copy(expiryEnabled = true, expiryRequired = true), lines[1])
        assertEquals("AB.02316 için SKT girin.", mixedDistributionValidation(expiry, short, today))
        val past = listOf(lines[0].copy(expiryEnabled = true, expiryDate = "13.10.2026"), lines[1])
        assertTrue(mixedDistributionValidation(past, short, today)!!.contains("geçmiş SKT"))
    }

    @Test
    fun `payload carries each product once and skips zero pallet quantities`() {
        val lines = listOf(
            entry(10000, "AB.02316", 100.0, lot = " A102500 ").copy(supplierLotNo = "S-1", expiryEnabled = true, expiryDate = "31.12.2027"),
            entry(20000, "AB.02317", 60.0).copy(lotRequired = false, lotNo = "ignored"),
        )
        val json = JSONObject(mixedDistributionJson(lines, listOf(mapOf(10000 to 50.0, 20000 to 60.0), mapOf(10000 to 50.0, 20000 to 0.0))))
        val first = json.getJSONArray("lines").getJSONObject(0)
        assertEquals(10000, first.getInt("lineNo"))
        assertEquals(100.0, first.getDouble("expectedQty"), 0.0)
        assertEquals("A102500", first.getString("lotNo"))
        assertEquals("S-1", first.getString("supplierLotNo"))
        assertEquals("2027-12-31", first.getString("expiryDate"))
        assertEquals("", json.getJSONArray("lines").getJSONObject(1).getString("lotNo"))
        val pallets = json.getJSONArray("pallets")
        assertEquals(2, pallets.getJSONObject(0).getJSONArray("items").length())
        assertEquals(1, pallets.getJSONObject(1).getJSONArray("items").length())
        assertEquals(10000, pallets.getJSONObject(1).getJSONArray("items").getJSONObject(0).getInt("lineNo"))
    }

    @Test
    fun `candidates exclude received and already distributed lines`() {
        val open = JSONObject().put("lineNo", 10000).put("quantity", 100).put("qtyReceived", 0).put("bulkLpCount", 0)
        val distributed = JSONObject().put("lineNo", 20000).put("quantity", 100).put("qtyReceived", 0).put("bulkLpCount", 4)
        val received = JSONObject().put("lineNo", 30000).put("quantity", 100).put("qtyReceived", 100)
        val serial = JSONObject().put("lineNo", 40000).put("quantity", 5).put("serialRequired", true)
        val onLp = JSONObject().put("lineNo", 50000).put("quantity", 10).put("licensePlateNo", "LP7").put("qtyToReceive", 10)
        val freedFromLp = JSONObject().put("lineNo", 60000).put("quantity", 10).put("licensePlateNo", "LP7").put("qtyToReceive", 0)
        assertEquals(listOf(10000, 60000),
            mixedPalletCandidates(listOf(open, distributed, received, serial, onLp, freedFromLp)).map { it.optInt("lineNo") })
    }

    @Test
    fun `cancel response yields the reset receipt lines`() {
        assertEquals(setOf(10000, 20000), cancelledDistributionLineNos("""{"lpNos":["LP1","LP2"],"lineNos":[10000,20000]}"""))
        assertEquals(emptySet<Int>(), cancelledDistributionLineNos("not json"))
    }
}
