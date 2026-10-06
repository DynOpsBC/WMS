package com.dynops.bcwms

import com.dynops.bcwms.feature.BulkReceiptLotGroup
import com.dynops.bcwms.feature.withGroupedBulkReceiptTracking
import com.dynops.bcwms.feature.receiptLpPlan
import org.json.JSONObject
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
    fun `400 and 600 units keep separate supplier and internal lots in one request`() {
        val groups = listOf(
            BulkReceiptLotGroup("G1", "A102370", "SUP-400", "2027-01-01"),
            BulkReceiptLotGroup("G2", "A102371", "SUP-600", "2027-02-01"),
        )
        val rows = withGroupedBulkReceiptTracking(listOf(
            BulkReceiptLpRow("G1", 400.0, "", "", ""),
            BulkReceiptLpRow("G2", 600.0, "", "", ""),
        ), groups)
        assertNull(manualBulkLpValidation(1000.0, rows, true, 1000.0, LocalDate.of(2026, 10, 6)))
        val json = JSONArray(bulkLpRowsJson(rows))
        assertEquals(2, json.length())
        assertEquals("A102370", json.getJSONObject(0).getString("lotNo"))
        assertEquals(400.0, json.getJSONObject(0).getDouble("quantity"), 0.0)
        assertEquals("A102371", json.getJSONObject(1).getString("lotNo"))
        assertEquals("SUP-600", json.getJSONObject(1).getString("supplierLotNo"))
        assertEquals(600.0, json.getJSONObject(1).getDouble("quantity"), 0.0)
    }

    @Test
    fun `several pallets share a generated lot group and first reserved group stays first`() {
        val groups = listOf(BulkReceiptLotGroup("G1", "RESERVED", "SUP-A"), BulkReceiptLotGroup("G2", "", "SUP-B"))
        val rows = withGroupedBulkReceiptTracking(listOf(
            BulkReceiptLpRow("G2", 300.0, "", "", ""),
            BulkReceiptLpRow("G1", 400.0, "", "", ""),
            BulkReceiptLpRow("G2", 300.0, "", "", ""),
        ), groups)
        assertEquals(listOf("G1", "G2", "G2"), rows.map { it.groupId })
        assertEquals(listOf("RESERVED", "", ""), rows.map { it.lotNo })
        assertEquals(listOf("SUP-A", "SUP-B", "SUP-B"), rows.map { it.supplierLotNo })
        assertNull(manualBulkLpValidation(1000.0, rows, false, 1000.0))
    }

    @Test
    fun `one internal lot cannot carry conflicting suppliers or expiration dates`() {
        val first = BulkReceiptLpRow("G1", 400.0, "LOT-A", "SUP-A", "2027-01-01")
        val second = BulkReceiptLpRow("G2", 600.0, "lot-a", "SUP-B", "2027-01-01")
        assertEquals("Aynı iç lot farklı tedarikçi lotlarıyla eşleştirilemez.", manualBulkLpValidation(1000.0, listOf(first, second), false))
        assertEquals("Aynı iç lot için farklı SKT girilemez.", manualBulkLpValidation(1000.0, listOf(first, second.copy(supplierLotNo = "SUP-A", expiryDate = "2027-02-01")), false))
    }

    @Test
    fun `nonfinite amounts and more than 200 pallets cannot be submitted`() {
        assertEquals("Her LP için sıfırdan büyük miktar girin.", manualBulkLpValidation(1000.0, listOf(BulkReceiptLpRow("G1", Double.NaN, "", "", "")), false))
        assertEquals("Tek işlemde en fazla 200 LP oluşturulabilir.", manualBulkLpValidation(1000.0, List(201) { BulkReceiptLpRow("G1", 1.0, "", "", "") }, false))
    }

    @Test
    fun `reloaded plan preserves both lots and old servers have no plan`() {
        val plan = JSONArray().put(JSONObject().put("lotNo", "A102370").put("quantity", 400))
            .put(JSONObject().put("lotNo", "A102371").put("quantity", 600))
        val rows = receiptLpPlan(JSONObject().put("receiptLpAllocations", plan.toString()))
        assertEquals(listOf("A102370", "A102371"), rows.map { it.getString("lotNo") })
        assertEquals(1000.0, rows.sumOf { it.getDouble("quantity") }, 0.0)
        assertEquals(emptyList<JSONObject>(), receiptLpPlan(JSONObject()))
    }

    @Test
    fun `all pallets use one common receipt lot and expiry`() {
        val commonRows = withGroupedBulkReceiptTracking(
            rows = listOf(
                BulkReceiptLpRow("RECEIPT", 5.0, "OLD-A", "", ""),
                BulkReceiptLpRow("RECEIPT", 5.0, "OLD-B", "", ""),
            ),
            groups = listOf(BulkReceiptLotGroup("RECEIPT", "LOT-A", "SUP-A", "2027-01-01")),
        )
        val json = JSONArray(
            bulkLpRowsJson(commonRows)
        )
        assertEquals("LOT-A", json.getJSONObject(0).getString("lotNo"))
        assertEquals("LOT-A", json.getJSONObject(1).getString("lotNo"))
        assertEquals("SUP-A", json.getJSONObject(1).getString("supplierLotNo"))
        assertEquals("2027-01-01", json.getJSONObject(1).getString("expiryDate"))
        assertEquals("RECEIPT", json.getJSONObject(0).getString("groupId"))
        assertEquals("RECEIPT", json.getJSONObject(1).getString("groupId"))
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
    fun `missing common expiry blocks the pallet set`() {
        val rows = listOf(
            BulkReceiptLpRow("1", 5.0, "", "", "2027-01-01"),
            BulkReceiptLpRow("2", 5.0, "", "", ""),
        )

        assertEquals("Bu mal kabul için SKT girin.", manualBulkLpValidation(10.0, rows, expiryRequired = true))
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
