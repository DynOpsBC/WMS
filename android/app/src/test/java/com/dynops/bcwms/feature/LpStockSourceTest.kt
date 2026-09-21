package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class LpStockSourceTest {
    private val key = LpStockSourceKey("AB.01743", "MERKEZ", "A101119", "")
    private fun entry(no: Int, available: Double) = JSONObject()
        .put("entryNo", no).put("itemNo", key.itemNo).put("locationCode", key.locationCode)
        .put("lotNo", key.lotNo).put("serialNo", key.serialNo).put("variantCode", key.variantCode)
        .put("documentNo", "MG-$no").put("quantity", 1782.0).put("remainingQuantity", 850.0)
        .put("lpAllocatableQuantity", available).put("baseUnitOfMeasure", "ADET")
        .put("postingDate", "2026-03-17")

    @Test fun `150 already allocated is excluded while 850 source remains selectable`() {
        val result = lpStockSourceEntries(listOf(entry(454, 0.0), entry(53, 850.0)), key)
        assertEquals(listOf(53), result.map { it.entryNo })
        assertEquals("MG-53", result.single().documentNo)
        assertEquals(850.0, result.single().available, 0.0)
    }
    @Test fun `different lot location variant and outbound entries are rejected`() {
        val invalid = listOf(
            entry(1, 850.0).put("lotNo", "OTHER"),
            entry(2, 850.0).put("locationCode", "OTHER"),
            entry(3, 850.0).put("variantCode", "OTHER"),
            entry(4, 850.0).put("quantity", -850.0),
        )
        assertTrue(lpStockSourceEntries(invalid, key).isEmpty())
    }
    @Test fun `missing allocation metadata is never treated as free stock`() {
        val row = entry(53, 850.0).apply { remove("lpAllocatableQuantity") }
        assertTrue(lpStockSourceEntries(listOf(row), key).isEmpty())
    }
    @Test fun `ambiguous origins stay separate for operator selection`() {
        val rows = listOf(entry(53, 850.0), entry(454, 150.0))
        assertEquals(listOf(53, 454), lpStockSourceEntries(rows, key).map { it.entryNo })
    }
    @Test fun `source lookup does not impose a total row limit`() {
        assertFalse(lpStockSourcePath(key).contains("\$top="))
        assertTrue(lpStockSourcePath(key).contains("\$orderby=postingDate,entryNo"))
    }
    @Test fun `query carries exact location lot serial variant and escapes quotes`() {
        val path = lpStockSourcePath(key.copy(itemNo = "O'RING", serialNo = "S'1", variantCode = "V1"))
        assertTrue(path.contains("itemNo eq 'O''RING'"))
        assertTrue(path.contains("serialNo eq 'S''1'"))
        assertTrue(path.contains("variantCode eq 'V1'"))
        assertTrue(path.contains("locationCode eq 'MERKEZ'"))
        assertTrue(path.contains("lotNo eq 'A101119'"))
        assertTrue(path.contains("quantity gt 0"))
    }
}
