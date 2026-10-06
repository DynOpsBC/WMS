package com.dynops.bcwms.feature

import com.dynops.bcwms.BcApi
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class DocumentPalletPlansTest {

    @Test
    fun `selected bottle row is not blocked by unrelated row with no pallets or BC error`() = runBlocking {
        val unrelated = row(10000, staged = 1.0).put("itemNo", "YM.00273").put("binCode", "Y.A01.11")
        val selected = row(20000, outstanding = 7809.0)
        for (unrelatedResponse in listOf(
            sourceResult(unrelated, pallets = emptyList()),
            BcApi.ApiResult(false, 500, "{\"error\":{\"message\":\"Kaynak palet okunamadı\"}}"),
        )) {
            val loaded = mutableListOf<Int>()
            val plans = planDocumentPalletRows(listOf(unrelated, selected), listOf(selected to 7809.0)) { no ->
                loaded += no
                if (no == 10000) unrelatedResponse
                else sourceResult(selected, pallets = listOf("LP000159" to 7809.0))
            }
            assertEquals(listOf(20000), loaded)
            assertEquals(20000, plans.single().lineNo)
            assertEquals("LP000159", plans.single().steps.single().lpNo)
            assertEquals(7809.0, plans.single().steps.single().baseQuantity, 0.00001)
        }
    }

    @Test
    fun `same item on another bin location or variant does not block selected row`() = runBlocking {
        for (field in listOf("binCode", "locationCode", "variantCode")) {
            val unrelated = row(10000, staged = 1.0).put(field, "OTHER")
            val selected = row(20000)
            val loaded = mutableListOf<Int>()
            val plans = planDocumentPalletRows(listOf(unrelated, selected), listOf(selected to 5.0)) { no ->
                loaded += no
                if (no == 10000) BcApi.ApiResult(false, 500, "Unrelated row must not be queried")
                else sourceResult(selected)
            }
            assertEquals(field, listOf(20000), loaded)
            assertEquals(5.0, plans.single().quantity, 0.00001)
        }
    }

    @Test
    fun `earlier allocation on the same resource consumes capacity before requested row`() = runBlocking {
        val previous = row(10000, staged = 7.0)
        val selected = row(20000)
        val rows = listOf(previous, selected)
        val loaded = mutableListOf<Int>()
        val plans = planDocumentPalletRows(rows, listOf(selected to 5.0)) { no ->
            loaded += no
            sourceResult(rows.first { it.getInt("lineNo") == no })
        }
        assertEquals(listOf(10000, 20000), loaded)
        assertEquals(listOf(20000), plans.map { it.lineNo })
        assertEquals(listOf("LP000159", "LP000160"), plans.single().steps.map { it.lpNo })
        assertEquals(listOf(3.0, 2.0), plans.single().steps.map { it.baseQuantity })
    }

    @Test
    fun `prior allocation cannot be ignored to overallocate one shared pallet`() {
        val previous = row(10000, staged = 7.0)
        val selected = row(20000)
        val rows = listOf(previous, selected)
        val error = assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                planDocumentPalletRows(rows, listOf(selected to 5.0)) { no ->
                    sourceResult(rows.first { it.getInt("lineNo") == no }, pallets = listOf("LP000159" to 10.0))
                }
            }
        }
        assertTrue(error.message.orEmpty().contains("yeterli stok yok"))
    }

    @Test
    fun `resource matching is case insensitive and still deducts earlier stock`() = runBlocking {
        val previous = row(10000, staged = 7.0).apply {
            put("itemNo", "ab.02029")
            put("variantCode", "blue")
            put("locationCode", "merkezdepo")
            put("binCode", "a.c01.13")
        }
        val selected = row(20000).put("variantCode", "BLUE")
        val rows = listOf(previous, selected)
        val loaded = mutableListOf<Int>()
        val plans = planDocumentPalletRows(rows, listOf(selected to 5.0)) { no ->
            loaded += no
            sourceResult(rows.first { it.getInt("lineNo") == no })
        }
        assertEquals(listOf(10000, 20000), loaded)
        assertEquals(listOf(3.0, 2.0), plans.single().steps.map { it.baseQuantity })
    }

    @Test
    fun `previous row with different UOM draws from the same base stock`() = runBlocking {
        val previous = row(10000, staged = 0.8).put("unitOfMeasureCode", "KOLI")
        val selected = row(20000)
        val loaded = mutableListOf<Int>()
        val plans = planDocumentPalletRows(listOf(previous, selected), listOf(selected to 5.0)) { no ->
            loaded += no
            if (no == 10000) sourceResult(previous, baseFactor = 10.0) else sourceResult(selected)
        }
        assertEquals(listOf(10000, 20000), loaded)
        assertEquals(listOf(2.0, 3.0), plans.single().steps.map { it.baseQuantity })
        assertEquals(listOf(2.0, 3.0), plans.single().steps.map { it.quantity })
    }

    @Test
    fun `unspecified lot and serial on earlier row still consume matching selected stock`() = runBlocking {
        val previous = row(10000, staged = 7.0)
        val selected = row(20000).put("lotNo", "LOT-A").put("serialNo", "SERIAL-A")
        val rows = listOf(previous, selected)
        val loaded = mutableListOf<Int>()
        val plans = planDocumentPalletRows(rows, listOf(selected to 5.0)) { no ->
            loaded += no
            sourceResult(rows.first { it.getInt("lineNo") == no }, sourceSerial = "SERIAL-A")
        }
        assertEquals(listOf(10000, 20000), loaded)
        assertEquals(listOf(3.0, 2.0), plans.single().steps.map { it.baseQuantity })
    }

    @Test
    fun `full document registration still rejects an unrelated staged row without pallets`() {
        val unrelated = row(10000, staged = 1.0).put("itemNo", "YM.00273").put("binCode", "Y.A01.11")
        val selected = row(20000, staged = 5.0)
        val loaded = mutableListOf<Int>()
        val error = assertThrows(IllegalArgumentException::class.java) {
            runBlocking {
                planDocumentPalletRows(listOf(selected, unrelated)) { no ->
                    loaded += no
                    if (no == 10000) sourceResult(unrelated, pallets = emptyList()) else sourceResult(selected)
                }
            }
        }
        assertEquals(listOf(10000), loaded)
        assertTrue(error.message.orEmpty().contains("YM.00273"))
        assertTrue(error.message.orEmpty().contains("Y.A01.11"))
    }

    @Test
    fun `full document validates every positive Take row and excludes Place or zero rows`() = runBlocking {
        val first = row(10000, staged = 3.0)
        val place = row(15000, staged = 3.0).put("actionType", "Place")
        val zero = row(20000)
        val otherItem = row(30000, staged = 2.0).put("itemNo", "YM.00273")
        val rows = listOf(otherItem, zero, place, first)
        val loaded = mutableListOf<Int>()
        val plans = planDocumentPalletRows(rows) { no ->
            loaded += no
            sourceResult(rows.first { it.getInt("lineNo") == no })
        }
        assertEquals(listOf(10000, 30000), loaded)
        assertEquals(listOf(10000, 30000), plans.map { it.lineNo })
    }

    @Test
    fun `group selections keep line order and cumulative stock including intervening allocations`() = runBlocking {
        val first = row(10000, staged = 2.0)
        val selectedA = row(20000)
        val middle = row(30000, staged = 3.0)
        val selectedB = row(40000)
        val later = row(50000, staged = 20.0)
        val rows = listOf(later, selectedB, selectedA, middle, first)
        val loaded = mutableListOf<Int>()
        val plans = planDocumentPalletRows(rows, listOf(selectedB to 5.0, selectedA to 4.0)) { no ->
            loaded += no
            sourceResult(rows.first { it.getInt("lineNo") == no })
        }
        assertEquals(listOf(10000, 20000, 30000, 40000), loaded)
        assertEquals(listOf(20000, 40000), plans.map { it.lineNo })
        assertEquals(listOf(4.0), plans[0].steps.map { it.baseQuantity })
        assertEquals(listOf(1.0, 4.0), plans[1].steps.map { it.baseQuantity })
    }

    @Test
    fun `zero requested quantities and rows after the last request do not fetch sources`() = runBlocking {
        val earlier = row(10000, staged = 1.0)
        val selected = row(20000, staged = 5.0)
        val later = row(30000, staged = 20.0)
        for (requested in listOf(emptyList(), listOf(selected to 0.0))) {
            val loaded = mutableListOf<Int>()
            val plans = planDocumentPalletRows(listOf(earlier, selected, later), requested) { no ->
                loaded += no
                BcApi.ApiResult(false, 500, "No source request expected")
            }
            assertTrue(loaded.isEmpty())
            assertTrue(plans.isEmpty())
        }
    }

    @Test
    fun `zero override releases previously staged stock for another requested row`() = runBlocking {
        val released = row(10000, staged = 7.0)
        val selected = row(20000)
        val loaded = mutableListOf<Int>()
        val plans = planDocumentPalletRows(listOf(released, selected), listOf(released to 0.0, selected to 10.0)) { no ->
            loaded += no
            if (no == 10000) BcApi.ApiResult(false, 500, "Released row must not be queried")
            else sourceResult(selected, pallets = listOf("LP000159" to 10.0))
        }
        assertEquals(listOf(20000), loaded)
        assertEquals(listOf(20000), plans.map { it.lineNo })
        assertEquals(10.0, plans.single().steps.single().baseQuantity, 0.00001)
    }

    @Test
    fun `later staged row is skipped even when zero request extends the selected boundary`() = runBlocking {
        val selected = row(10000)
        val later = row(20000, staged = 20.0)
        val zero = row(30000, staged = 5.0)
        val loaded = mutableListOf<Int>()
        val plans = planDocumentPalletRows(listOf(selected, later, zero), listOf(selected to 5.0, zero to 0.0)) { no ->
            loaded += no
            if (no != 10000) BcApi.ApiResult(false, 500, "Later allocation must not block the selected row")
            else sourceResult(selected)
        }
        assertEquals(listOf(10000), loaded)
        assertEquals(listOf(10000), plans.map { it.lineNo })
        assertEquals(5.0, plans.single().quantity, 0.00001)
    }

    @Test
    fun `changed selected row identity is rejected before any source fetch`() {
        for (field in listOf("itemNo", "variantCode", "locationCode", "binCode", "lotNo", "serialNo", "unitOfMeasureCode")) {
            val expected = row(20000)
            val actual = JSONObject(expected.toString()).put(field, "CHANGED")
            val loaded = mutableListOf<Int>()
            val error = assertThrows(IllegalStateException::class.java) {
                runBlocking {
                    planDocumentPalletRows(listOf(row(10000, staged = 1.0), actual), listOf(expected to 5.0)) { no ->
                        loaded += no
                        sourceResult(actual)
                    }
                }
            }
            assertTrue(field, loaded.isEmpty())
            assertTrue(error.message.orEmpty().contains("değişmiş"))
        }
    }

    @Test
    fun `removed selected line is rejected before any source fetch`() {
        val loaded = mutableListOf<Int>()
        assertThrows(IllegalStateException::class.java) {
            runBlocking {
                planDocumentPalletRows(listOf(row(10000, staged = 1.0)), listOf(row(20000) to 5.0)) { no ->
                    loaded += no
                    BcApi.ApiResult(false, 404, "Removed line")
                }
            }
        }
        assertTrue(loaded.isEmpty())
    }

    private fun row(no: Int, staged: Double = 0.0, outstanding: Double = 20.0) = JSONObject().apply {
        put("no", "PI001943")
        put("lineNo", no)
        put("actionType", "Take")
        put("itemNo", "AB.02029")
        put("variantCode", "")
        put("locationCode", "MERKEZDEPO")
        put("binCode", "A.C01.13")
        put("lotNo", "")
        put("serialNo", "")
        put("unitOfMeasureCode", "ADET")
        put("qtyOutstanding", outstanding)
        put("qtyToHandle", staged)
    }

    private fun sourceResult(
        row: JSONObject,
        baseFactor: Double = 1.0,
        pallets: List<Pair<String, Double>> = listOf("LP000159" to 10.0, "LP000160" to 10.0),
        sourceSerial: String = "",
    ): BcApi.ApiResult {
        val body = JSONObject().apply {
            put("activityNo", row.getString("no"))
            put("lineNo", row.getInt("lineNo"))
            for (field in listOf("itemNo", "variantCode", "locationCode", "binCode", "lotNo", "unitOfMeasureCode")) {
                put(field, row.getString(field))
            }
            put("lotRequired", true)
            put("outstandingQty", row.getDouble("qtyOutstanding"))
            put("outstandingBaseQty", row.getDouble("qtyOutstanding") * baseFactor)
            put("sources", JSONArray().apply {
                for ((lp, available) in pallets) put(JSONObject().apply {
                    put("lpNo", lp)
                    put("binCode", row.getString("binCode"))
                    put("lotNo", row.getString("lotNo").ifBlank { "LOT-A" })
                    put("serialNo", sourceSerial)
                    put("availableBaseQty", available)
                })
            })
        }
        return BcApi.ApiResult(true, 200, JSONObject().put("value", body.toString()).toString())
    }
}
