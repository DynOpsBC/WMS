package com.dynops.bcwms.feature

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiptLabelSheetTest {
    private fun line(item: String, qty: Double, lot: String = "", unit: String = "KG") = JSONObject()
        .put("itemNo", item).put("description", "$item açıklama").put("qtyToReceive", qty)
        .put("lotNo", lot).put("unitOfMeasureCode", unit)

    @Test fun `quantity text uses Turkish separators and keeps the unit`() {
        assertEquals("25.060 KG", receiptLabelQtyText(25060.0, "KG"))
        assertEquals("12,5 KG", receiptLabelQtyText(12.5, "KG"))
        assertEquals("1.234.567,891 ADET", receiptLabelQtyText(1234567.891, "ADET"))
        assertEquals("7", receiptLabelQtyText(7.0, ""))
        assertEquals("0,333 KG", receiptLabelQtyText(1.0 / 3.0, "KG"))
    }

    @Test fun `one row per received line with one copy, lines without quantity are skipped`() {
        val rows = receiptLabelRows(listOf(line("KLC-8", 25060.0, "DKC26K250-006"), line("JMB-2", 0.0), line("PLASTİK TAPA DOMUZ", 500.0, unit = "ADET")))
        assertEquals(listOf("KLC-8", "PLASTİK TAPA DOMUZ"), rows.map { it.itemNo })
        assertEquals(listOf(1, 1), rows.map { it.copies })
        assertEquals("DKC26K250-006", rows[0].lotNo)
    }

    @Test fun `batches never exceed the per-job limit and keep every requested label in order`() {
        val rows = listOf(
            ReceiptLabelRow("A", "", "", "", 1.0, "KG", copies = 7),
            ReceiptLabelRow("B", "", "", "", 1.0, "KG", copies = 0),
            ReceiptLabelRow("C", "", "L1", "", 1.0, "KG", copies = 15),
        )
        val batches = receiptLabelBatches(rows, perJob = 10)
        assertTrue(batches.all { b -> b.sumOf { it.copies } <= 10 })
        assertEquals(22, batches.sumOf { b -> b.sumOf { it.copies } })
        assertEquals(listOf("A", "C", "C", "C"), batches.flatten().map { it.itemNo })
        assertEquals(listOf(7, 3, 10, 2), batches.flatten().map { it.copies })
    }

    @Test fun `rows json carries what Business Central prints`() {
        val json = JSONArray(receiptLabelRowsJson(listOf(ReceiptLabelRow("KLC-8", "x", "DKC26K250-006", "T-1", 25060.0, "KG", 2)), "RE000121", "18.11.2026"))
        val o = json.getJSONObject(0)
        assertEquals("KLC-8", o.getString("itemNo"))
        assertEquals("DKC26K250-006", o.getString("lotNo"))
        assertEquals("T-1", o.getString("supplierLotNo"))
        assertEquals("25.060 KG", o.getString("quantityText"))
        assertEquals("RE000121", o.getString("receiptNo"))
        assertEquals("18.11.2026", o.getString("dateText"))
        assertEquals(2, o.getInt("copies"))
    }
}
