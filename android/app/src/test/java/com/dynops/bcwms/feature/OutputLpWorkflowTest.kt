package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class OutputLpWorkflowTest {
    @Test
    fun splitWholeQuantityGivesRemainderToLastLp() {
        assertEquals(listOf(1000.0, 1000.0, 1000.0), splitOutputQuantity(3000.0, 3))
        assertEquals(listOf(333.0, 333.0, 334.0), splitOutputQuantity(1000.0, 3))
        assertEquals(listOf(10000.0), splitOutputQuantity(10000.0, 1))
    }

    @Test
    fun splitRejectsInvalidInput() {
        assertEquals(emptyList<Double>(), splitOutputQuantity(0.0, 2))
        assertEquals(emptyList<Double>(), splitOutputQuantity(5.0, 0))
        assertEquals(emptyList<Double>(), splitOutputQuantity(2.0, 3))
    }

    @Test
    fun splitFractionalQuantitySumsToTotal() {
        val parts = splitOutputQuantity(10.5, 4)
        assertEquals(4, parts.size)
        assertEquals(10.5, parts.sum(), 0.00001)
    }

    @Test
    fun targetLpChecks() {
        val ok = JSONObject().put("no", "LP1").put("status", "Built").put("locationCode", "DKC WMS")
        assertNull(outputTargetLpProblem(ok, "LP1", "DKC WMS"))
        assertNotNull(outputTargetLpProblem(null, "LP1", "DKC WMS"))
        assertNotNull(outputTargetLpProblem(JSONObject(ok.toString()).put("status", "Used"), "LP1", "DKC WMS"))
        assertNotNull(outputTargetLpProblem(JSONObject(ok.toString()).put("locationCode", "BASKA"), "LP1", "DKC WMS"))
    }

    @Test
    fun lineBodyCarriesLotAndSourceBin() {
        val body = JSONObject(outputLpLineBody("I1", "ADET", 50.0, "L1", "URT-01", "U1"))
        assertEquals("URT-01", body.getString("sourceBinCode"))
        assertEquals("L1", body.getString("lotNo"))
        assertEquals(50.0, body.getDouble("quantity"), 0.0)
    }
}
