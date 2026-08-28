package com.dynops.bcwms

import com.dynops.bcwms.feature.BulkReceiptLpRow
import com.dynops.bcwms.feature.buildBulkLpQuantities
import com.dynops.bcwms.feature.bulkLpRowsJson
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BulkReceiptLpTest {
    @Test
    fun `ten thousand is distributed to ten equal pallets`() {
        val quantities = buildBulkLpQuantities(10_000.0, 10, 1_000.0, true)
        assertEquals(List(10) { 1_000.0 }, quantities)
        assertEquals(10_000.0, quantities!!.sum(), 0.00001)
    }

    @Test
    fun `remainder is transferred to last pallet`() {
        assertEquals(
            listOf(3.0, 3.0, 4.0),
            buildBulkLpQuantities(10.0, 3, 3.0, true),
        )
    }

    @Test
    fun `unequal distribution is rejected when remainder option is off`() {
        assertNull(buildBulkLpQuantities(10.0, 3, 3.0, false))
    }

    @Test
    fun `different lots stay in different json rows`() {
        val json = JSONArray(
            bulkLpRowsJson(
                listOf(
                    BulkReceiptLpRow("1", 5.0, "LOT-A", "SUP-A", "2027-01-01"),
                    BulkReceiptLpRow("2", 5.0, "LOT-B", "SUP-B", "2027-02-01"),
                )
            )
        )
        assertEquals("LOT-A", json.getJSONObject(0).getString("lotNo"))
        assertEquals("LOT-B", json.getJSONObject(1).getString("lotNo"))
    }
}
