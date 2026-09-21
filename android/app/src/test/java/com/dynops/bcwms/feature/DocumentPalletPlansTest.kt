package com.dynops.bcwms.feature

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class DocumentPalletPlansTest {
    private fun line(no: Int, item: String = "AB.02029", bin: String = "A.C01.13", qty: Double = 10.0) =
        JSONObject().apply {
            put("no", "PI001945"); put("lineNo", no); put("actionType", "Take")
            put("itemNo", item); put("variantCode", ""); put("locationCode", "MERKEZDEPO")
            put("binCode", bin); put("lotNo", ""); put("serialNo", "")
            put("unitOfMeasureCode", "ADET"); put("qtyOutstanding", qty); put("qtyToHandle", qty)
        }

    private fun sources(row: JSONObject, available: Double = 10.0, empty: Boolean = false): String =
        JSONObject(row.toString()).apply {
            put("activityNo", row.getString("no"))
            put("outstandingBaseQty", row.getDouble("qtyOutstanding"))
            put("sources", JSONArray().apply {
                if (!empty) put(JSONObject().apply {
                    put("lpNo", "LP-AB"); put("binCode", row.getString("binCode"))
                    put("lotNo", row.optString("lotNo").ifBlank { "LOT-A" })
                    put("serialNo", row.optString("serialNo")); put("availableBaseQty", available)
                })
            })
        }.toString()

    @Test fun `AB02029 can open while earlier YM00273 has no LP`() = runBlocking {
        val earlier = line(10000, "YM.00273", "Y.A01.11", 240.0).put("unitOfMeasureCode", "KG")
        val selected = line(30000, qty = 7809.0)
        val calls = mutableListOf<Int>()
        val plans = buildDocumentPalletPlans(listOf(earlier, selected), listOf(selected to 7809.0)) { no ->
            calls += no
            if (no == 10000) sources(earlier, empty = true) else sources(selected, 7809.0)
        }
        assertEquals(listOf(30000), calls)
        assertEquals(30000, plans.single().lineNo)
        assertEquals(7809.0, plans.single().steps.single().baseQuantity, 0.0)
    }

    @Test fun `earlier rows with separate stock cannot block selected line`() = runBlocking {
        for ((field, value) in listOf("itemNo" to "OTHER", "variantCode" to "RED",
            "locationCode" to "OTHER", "binCode" to "OTHER", "lotNo" to "LOT-B", "serialNo" to "SERIAL-B")) {
            val selected = line(30000).put("lotNo", "LOT-A").put("serialNo", "SERIAL-A")
            val earlier = JSONObject(selected.toString()).put("lineNo", 10000).put(field, value)
            val calls = mutableListOf<Int>()
            val plans = buildDocumentPalletPlans(listOf(earlier, selected), listOf(selected to 10.0)) { no ->
                calls += no
                if (no == 10000) sources(earlier, empty = true) else sources(selected)
            }
            assertEquals(field, listOf(30000), calls)
            assertEquals(1, plans.size)
        }
    }

    @Test fun `earlier matching row still reserves shared pallet stock`() = runBlocking {
        val earlier = line(10000, qty = 6.0)
        val selected = line(30000)
        val calls = mutableListOf<Int>()
        val plans = buildDocumentPalletPlans(listOf(selected, earlier), listOf(selected to 4.0)) { no ->
            calls += no
            sources(if (no == 10000) earlier else selected)
        }
        assertEquals(listOf(10000, 30000), calls)
        assertEquals(4.0, plans.single().steps.single().baseQuantity, 0.0)
        val error = runCatching {
            buildDocumentPalletPlans(listOf(earlier, selected), listOf(selected to 5.0)) { no ->
                sources(if (no == 10000) earlier else selected)
            }
        }.exceptionOrNull()
        assertNotNull(error)
        assertTrue(error!!.message.orEmpty().contains("yeterli stok yok"))
    }

    @Test fun `blank earlier tracking still overlaps explicit selected tracking`() = runBlocking {
        val earlier = line(10000, qty = 6.0)
        val selected = line(30000).put("lotNo", "LOT-A")
        val error = runCatching {
            buildDocumentPalletPlans(listOf(earlier, selected), listOf(selected to 5.0)) { no ->
                sources(if (no == 10000) earlier else selected)
            }
        }.exceptionOrNull()
        assertNotNull(error)
        assertTrue(error!!.message.orEmpty().contains("yeterli stok yok"))
    }

    @Test fun `registration still checks every staged item and fails on missing LP`() = runBlocking {
        val earlier = line(10000, "YM.00273", "Y.A01.11")
        val selected = line(30000)
        val calls = mutableListOf<Int>()
        val error = runCatching {
            buildDocumentPalletPlans(listOf(earlier, selected)) { no ->
                calls += no
                sources(earlier, empty = true)
            }
        }.exceptionOrNull()
        assertEquals(listOf(10000), calls)
        assertNotNull(error)
        assertTrue(error!!.message.orEmpty().contains("YM.00273"))
    }

    @Test fun `selected line without LP reports its own item`() = runBlocking {
        val earlier = line(10000, "YM.00273", "Y.A01.11")
        val selected = line(30000)
        val error = runCatching {
            buildDocumentPalletPlans(listOf(earlier, selected), listOf(selected to 10.0)) { no ->
                sources(if (no == 10000) earlier else selected, empty = true)
            }
        }.exceptionOrNull()
        assertNotNull(error)
        assertTrue(error!!.message.orEmpty().contains("AB.02029"))
        assertFalse(error.message.orEmpty().contains("YM.00273"))
    }

    @Test fun `selected snapshot changed on server still fails before loading LPs`() = runBlocking {
        val selected = line(30000)
        val current = JSONObject(selected.toString()).put("binCode", "NEW-BIN")
        val error = runCatching {
            buildDocumentPalletPlans(listOf(current), listOf(selected to 10.0)) {
                fail("Changed snapshot must not load pallets")
                ""
            }
        }.exceptionOrNull()
        assertNotNull(error)
        assertTrue(error!!.message.orEmpty().contains("değişmiş"))
    }
}
