package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

/** BADE 1.14.200 (Merve): mal kabul "Etiket Yazdır" öncesi MTE ek bilgileri ve kopya adedi. */
class ReceiptMteOptionsTest {
    @Test
    fun `kopya adedi bos ise 1 gecersiz ise null`() {
        assertEquals(1, normalizeMteCopies(""))
        assertEquals(3, normalizeMteCopies(" 3 "))
        assertEquals(10, normalizeMteCopies("10"))
        assertNull(normalizeMteCopies("0"))
        assertNull(normalizeMteCopies("11"))
        assertNull(normalizeMteCopies("x"))
    }

    @Test
    fun `kalite kontrol tarihi varsayilani bugun`() {
        assertEquals("05.03.2026", defaultMteQcDate(java.time.LocalDate.of(2026, 3, 5)))
        assertEquals("2026-03-05", normalizeMteDate(defaultMteQcDate(java.time.LocalDate.of(2026, 3, 5))))
    }

    @Test
    fun `secilen alanlar ve kopya yazdirma govdesine gecer`() {
        val body = JSONObject(
            receiptMtePrintBody(
                "ZPL01",
                MteOptions(inspectorEmployeeNo = "P001", qcEmployeeNo = "P007", qcApprovalDate = "2026-10-23", copies = 2),
            ),
        )
        assertEquals("ZPL01", body.getString("printerId"))
        assertEquals(2, body.getInt("copies"))
        val options = JSONObject(body.getString("optionsJson"))
        assertEquals("P001", options.getString("inspectorEmployeeNo"))
        assertEquals("P007", options.getString("qcEmployeeNo"))
        assertEquals("2026-10-23", options.getString("qcApprovalDate"))
        assertFalse(options.has("supplierLotNo"))
    }

    @Test
    fun `hicbir sey secilmezse tek kopya bos alanlar`() {
        val body = JSONObject(receiptMtePrintBody("ZPL01", MteOptions()))
        assertEquals(1, body.getInt("copies"))
        assertEquals("{}", body.getString("optionsJson"))
    }

    @Test
    fun `BADE operator istegi secilen giris yapani korur kopyayi tasir`() {
        val body = receiptMtePrintBody("ZPL01", MteOptions(inspectorEmployeeNo = "P001", copies = 3))
        val request = mteOperatorRequest(mteOperatorAction("licensePlates", "printPalletLabels")!!, body, "Merve")
        val payload = JSONObject(request.body)
        assertEquals("printMteForOperator", request.action)
        assertEquals(3, payload.getInt("copies"))
        val options = JSONObject(payload.getString("optionsJson"))
        assertEquals("P001", options.getString("inspectorEmployeeNo"))
        assertFalse(options.has("operatorDisplayName"))
    }
}
