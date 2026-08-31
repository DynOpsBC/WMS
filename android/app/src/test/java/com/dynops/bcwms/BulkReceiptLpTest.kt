package com.dynops.bcwms

import com.dynops.bcwms.feature.BulkReceiptLpRow
import com.dynops.bcwms.feature.bulkLpRowsJson
import com.dynops.bcwms.feature.equalBulkLpQuantities
import com.dynops.bcwms.feature.manualBulkLpValidation
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

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
    fun `equal distribution fills every pallet and preserves exact total`() {
        val quantities = equalBulkLpQuantities(10.0, 3)

        assertEquals(listOf(3.33333, 3.33333, 3.33334), quantities)
        assertEquals(10.0, quantities.sum(), 0.000001)
    }

    @Test
    fun `equal distribution supports whole pallet quantities`() {
        assertEquals(listOf(25.0, 25.0, 25.0, 25.0), equalBulkLpQuantities(100.0, 4))
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

    @Test
    fun `pallet total must match entered receipt quantity`() {
        val rows = listOf(
            BulkReceiptLpRow("1", 4.0, "", "", ""),
            BulkReceiptLpRow("2", 4.0, "", "", ""),
        )

        assertEquals(
            "LP toplamı kabul miktarına eşit olmalıdır.",
            manualBulkLpValidation(10.0, rows, expiryRequired = false, expectedQty = 10.0),
        )
    }

    @Test
    fun `turkish display expiry is serialized as BC iso date`() {
        val json = JSONArray(
            bulkLpRowsJson(listOf(BulkReceiptLpRow("1", 5.0, "LOT-A", "", "31.12.2027")))
        )

        assertEquals("2027-12-31", json.getJSONObject(0).getString("expiryDate"))
    }

    @Test
    fun `past expiry is rejected for bulk receipt pallets`() {
        val rows = listOf(BulkReceiptLpRow("1", 5.0, "LOT-A", "", "27.08.2026"))

        assertEquals(
            "Geçmiş SKT'li ürün mal kabul edilemez.",
            manualBulkLpValidation(
                5.0,
                rows,
                expiryRequired = true,
                expectedQty = 5.0,
                today = LocalDate.of(2026, 8, 28),
            ),
        )
    }

    @Test
    fun `today expiry is accepted for bulk receipt pallets`() {
        val rows = listOf(BulkReceiptLpRow("1", 5.0, "LOT-A", "", "28.08.2026"))

        assertNull(
            manualBulkLpValidation(
                5.0,
                rows,
                expiryRequired = true,
                expectedQty = 5.0,
                today = LocalDate.of(2026, 8, 28),
            )
        )
    }
}
