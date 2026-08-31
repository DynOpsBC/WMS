package com.dynops.bcwms

import com.dynops.bcwms.feature.BulkReceiptLpRow
import com.dynops.bcwms.feature.bulkLpRowsJson
import com.dynops.bcwms.feature.manualBulkLpValidation
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BulkReceiptLpTest {
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

    @Test
    fun `at least one manual pallet is required`() {
        assertEquals("En az bir LP ekleyin.", manualBulkLpValidation(10.0, emptyList(), expiryRequired = false))
    }

    @Test
    fun `manual pallet quantities are accepted without redistribution`() {
        val rows = listOf(
            BulkReceiptLpRow("1", 3.0, "LOT-A", "", "2027-01-01"),
            BulkReceiptLpRow("2", 7.0, "LOT-B", "", "2027-02-01"),
        )

        assertNull(manualBulkLpValidation(10.0, rows, expiryRequired = true))
        val json = JSONArray(bulkLpRowsJson(rows))
        assertEquals(3.0, json.getJSONObject(0).getDouble("quantity"), 0.00001)
        assertEquals(7.0, json.getJSONObject(1).getDouble("quantity"), 0.00001)
    }

    @Test
    fun `partial manual pallet total is allowed`() {
        val rows = listOf(BulkReceiptLpRow("1", 4.0, "", "", ""))

        assertNull(manualBulkLpValidation(10.0, rows, expiryRequired = false))
    }

    @Test
    fun `manual pallet total cannot exceed outstanding quantity`() {
        val rows = listOf(
            BulkReceiptLpRow("1", 6.0, "", "", ""),
            BulkReceiptLpRow("2", 5.0, "", "", ""),
        )

        assertEquals("LP toplamı açık miktarı aşamaz.", manualBulkLpValidation(10.0, rows, expiryRequired = false))
    }

    @Test
    fun `every manual pallet requires a positive quantity`() {
        val rows = listOf(
            BulkReceiptLpRow("1", 5.0, "", "", ""),
            BulkReceiptLpRow("2", 0.0, "", "", ""),
        )

        assertEquals("Her LP için sıfırdan büyük miktar girin.", manualBulkLpValidation(10.0, rows, expiryRequired = false))
    }

    @Test
    fun `expiry is checked separately for every manual pallet`() {
        val rows = listOf(
            BulkReceiptLpRow("1", 5.0, "", "", "2027-01-01"),
            BulkReceiptLpRow("2", 5.0, "", "", ""),
        )

        assertEquals("Her LP için SKT girin.", manualBulkLpValidation(10.0, rows, expiryRequired = true))
    }
}
