package com.dynops.bcwms.feature

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PalletPickPlanTest {

    @Test
    fun `source bin must match before pallet scan`() {
        assertTrue(acceptsSourceBin("A.TOPLAM", " a.toplam "))
        assertTrue(acceptsSourceBin("A.TOPLAM", "B-A.TOPLAM"))
        assertTrue(acceptsSourceBin("B-01", "B-01"))
        assertFalse(acceptsSourceBin("A.TOPLAM", "A1"))
        assertFalse(acceptsSourceBin("A.TOPLAM", "LP000013"))
        assertFalse(acceptsSourceBin("", "A.TOPLAM"))
        assertFalse(acceptsSourceBin("A.TOPLAM", ""))
    }

    @Test
    fun `pallet scanned before the bin is explained as an order problem`() {
        val lp = sourceBinScanError("A.TOPLAM", com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve("LP000013"))
        assertTrue(lp, lp.startsWith("LP000013 bir palet etiketi.") && lp.contains("A.TOPLAM"))
        val other = sourceBinScanError("A.TOPLAM", com.dynops.bcwms.scanner.BarcodeIntentResolver.resolve("A.E08.11"))
        assertEquals("Yanlış raf: A.E08.11. Bu toplama için önce A.TOPLAM rafını okutun.", other)
    }
    @Test fun `source lookup from a changed UOM or quantity snapshot is rejected`() {
        reject(data = response().put("unitOfMeasureCode", "ADET"))
        reject(data = response().put("outstandingQty", 10))
    }

    @Test fun `registration transmits every scanned pallet and rounds binary artifacts`() {
        val plan = buildPalletPickPlan(line(), 15.0, response().toString())
        val json = JSONArray(scannedPalletRegistrationJson(listOf(plan)))
        assertEquals(1, json.length())
        val entry = json.getJSONObject(0)
        assertEquals(plan.identity, entry.getString("identity"))
        val steps = entry.getJSONArray("steps")
        assertEquals(2, steps.length())
        assertEquals("LP0001", steps.getJSONObject(0).getString("lpNo"))
        assertEquals("LP0002", steps.getJSONObject(1).getString("lpNo"))
        assertEquals(150.0, (0 until steps.length()).sumOf { steps.getJSONObject(it).getDouble("baseQuantity") }, 0.00001)
        val rounded = plan.copy(steps = listOf(plan.steps.first().copy(baseQuantity = 0.1 + 0.2)))
        assertEquals(0.3, JSONArray(scannedPalletRegistrationJson(listOf(rounded)))
            .getJSONObject(0).getJSONArray("steps").getJSONObject(0).getDouble("baseQuantity"), 0.0)
    }

    @Test fun `empty duplicate or invalid registration plans cannot be sent`() {
        val plan = buildPalletPickPlan(line(), 15.0, response().toString())
        for (plans in listOf(emptyList(), listOf(plan, plan), listOf(plan.copy(steps = emptyList())),
            listOf(plan.copy(steps = listOf(plan.steps.first().copy(baseQuantity = Double.NaN)))))) {
            assertThrows(IllegalArgumentException::class.java) { scannedPalletRegistrationJson(plans) }
        }
    }

    private fun line(no: Int = 10000) = JSONObject("""{
        "no":"PI001", "lineNo":$no, "itemNo":"ITEM", "variantCode":"", "locationCode":"BADE",
        "binCode":"A-01", "lotNo":"LOT-A", "serialNo":"", "unitOfMeasureCode":"KOLI", "qtyOutstanding":15
    }""")

    private fun response(no: Int = 10000) = JSONObject("""{
        "activityNo":"PI001", "lineNo":$no, "itemNo":"ITEM", "variantCode":"", "locationCode":"BADE",
        "binCode":"A-01", "lotNo":"LOT-A", "lotRequired":true, "outstandingBaseQty":150,
        "sources":[
            {"lpNo":"LP0001", "binCode":"A-01", "lotNo":"LOT-A", "serialNo":"", "availableBaseQty":100},
            {"lpNo":"LP0002", "binCode":"A-01", "lotNo":"LOT-A", "serialNo":"", "availableBaseQty":100}
        ]
    }""")

    private fun reject(line: JSONObject = line(), data: JSONObject = response(), qty: Double = 15.0) {
        assertThrows(Exception::class.java) { buildPalletPickPlan(line, qty, data.toString()) }
    }

    @Test fun `multi pallet plan converts base stock into pick UOM and uses only required remainder`() {
        val p = buildPalletPickPlan(line(), 15.0, response().toString())
        assertEquals(listOf("LP0001", "LP0002"), p.steps.map { it.lpNo })
        assertEquals(listOf(10.0, 5.0), p.steps.map { it.quantity })
        assertEquals(listOf(100.0, 50.0), p.steps.map { it.baseQuantity })
    }

    @Test fun `partial quantity needs only one pallet`() {
        val p = buildPalletPickPlan(line(), 4.5, response().toString())
        assertEquals(1, p.steps.size)
        assertEquals(45.0, p.steps.single().baseQuantity, 0.00001)
    }

    @Test fun `blank or wrong scans cannot advance and all pallets are mandatory`() {
        val steps = buildPalletPickPlan(line(), 15.0, response().toString()).steps
        assertFalse(acceptsPalletStep(steps, 0, ""))
        assertFalse(acceptsPalletStep(steps, 0, "ITEM"))
        assertFalse(acceptsPalletStep(steps, 0, "LP0002"))
        assertTrue(acceptsPalletStep(steps, 0, " lp0001 "))
        assertFalse(acceptsPalletStep(steps, 1, "LP0001"))
        assertTrue(acceptsPalletStep(steps, 1, "LP0002"))
        assertFalse(palletScansComplete(steps, 0))
        assertFalse(palletScansComplete(steps, 1))
        assertTrue(palletScansComplete(steps, 2))
        assertFalse(acceptsPalletStep(steps, 2, "LP0002"))
        assertFalse(palletScansComplete(emptyList(), 0))
    }

    @Test fun `wrong product variant location bin document or line is rejected`() {
        for (field in listOf("itemNo", "variantCode", "locationCode", "binCode", "activityNo")) {
            reject(data = response().put(field, "OTHER"))
        }
        reject(data = response(20000))
    }

    @Test fun `wrong lot or serial candidates cannot satisfy a pick`() {
        for (field in listOf("lotNo", "serialNo", "binCode")) {
            val data = response()
            val sources = data.getJSONArray("sources")
            for (i in 0 until sources.length()) sources.getJSONObject(i).put(field, "OTHER")
            reject(line = if (field == "serialNo") line().put("serialNo", "EXPECTED") else line(), data = data)
        }
    }

    @Test fun `missing malformed empty and insufficient candidates fail closed`() {
        reject(data = response().put("sources", JSONArray()))
        reject(data = JSONObject())
        val data = response()
        data.getJSONArray("sources").getJSONObject(1).put("availableBaseQty", 1)
        reject(data = data)
        assertThrows(Exception::class.java) { buildPalletPickPlan(line(), 10.0, "not json") }
    }

    @Test fun `different lot pallet reports expected source without allowing confirmation`() {
        val row = line().put("itemNo", "AB.01091").put("lotNo", "A103309")
        val data = response().put("itemNo", "AB.01091").put("lotNo", "A103309")
        val sources = data.getJSONArray("sources")
        for (i in 0 until sources.length()) sources.getJSONObject(i).put("lotNo", "A102116")
        val error = assertThrows(IllegalArgumentException::class.java) {
            buildPalletPickPlan(row, 15.0, data.toString())
        }
        assertTrue(error.message.orEmpty().contains("AB.01091"))
        assertTrue(error.message.orEmpty().contains("Lot: A103309"))
        assertTrue(error.message.orEmpty().contains("Raf: A-01"))
        assertTrue(error.message.orEmpty().contains("Farklı lotlu palet bu satırda toplanamaz"))
    }

    @Test fun `zero negative nonfinite and excess quantities are rejected`() {
        listOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY, 16.0).forEach { reject(qty = it) }
        reject(data = response().put("outstandingBaseQty", 0))
        reject(line = line().put("qtyOutstanding", 0))
    }

    @Test fun `lot can come from an unambiguous pallet but different lots never mix`() {
        val row = line().put("lotNo", "")
        val data = response().put("lotNo", "")
        assertEquals("LOT-A", buildPalletPickPlan(row, 15.0, data.toString()).lotNo)
        data.getJSONArray("sources").getJSONObject(1).put("lotNo", "LOT-B")
        reject(line = row, data = data)
    }

    @Test fun `merged or previously staged lines do not reuse pallet capacity`() {
        val used = mutableMapOf<String, Double>()
        buildPalletPickPlan(line(), 8.0, response().toString(), used)
        val next = buildPalletPickPlan(line(20000), 7.0, response(20000).toString(), used)
        assertEquals(listOf(20.0, 50.0), next.steps.map { it.baseQuantity })
    }

    @Test fun `exhausted first pallet is skipped for the next line`() {
        val used = mutableMapOf<String, Double>()
        buildPalletPickPlan(line(), 10.0, response().toString(), used)
        val next = buildPalletPickPlan(line(20000), 5.0, response(20000).toString(), used)
        assertEquals("LP0002", next.steps.single().lpNo)
    }

    @Test fun `merged lines sharing a pallet ask for one scan and the combined physical quantity`() {
        val used = mutableMapOf<String, Double>()
        val first = buildPalletPickPlan(line(), 8.0, response().toString(), used)
        val second = buildPalletPickPlan(line(20000), 7.0, response(20000).toString(), used)
        val steps = palletScanSteps(listOf(first, second))
        assertEquals(listOf("LP0001", "LP0002"), steps.map { it.lpNo })
        assertEquals(listOf(10.0, 5.0), steps.map { it.quantity })
        assertFalse(palletScansComplete(steps, 1))
    }

    @Test fun `failed plan does not consume stock for subsequent attempts`() {
        val used = mutableMapOf<String, Double>()
        buildPalletPickPlan(line(), 15.0, response().toString(), used)
        val before = used.toMap()
        assertThrows(Exception::class.java) { buildPalletPickPlan(line(20000), 10.0, response(20000).toString(), used) }
        assertEquals(before, used)
    }

    @Test fun `confirmed source preference is replayed in BC allocation order`() {
        val p = buildPalletPickPlan(line().put("licensePlateNo", "LP0002"), 15.0, response().toString())
        assertEquals(listOf("LP0002", "LP0001"), p.steps.map { it.lpNo })
    }

    @Test fun `stock change invalidates scan proof`() {
        val old = buildPalletPickPlan(line(), 15.0, response().toString())
        val changed = response()
        changed.getJSONArray("sources").getJSONObject(0).put("availableBaseQty", 80)
        assertFalse(samePalletPickPlan(old, buildPalletPickPlan(line(), 15.0, changed.toString())))
        assertFalse(samePalletPickPlan(old, old.copy(identity = "another item")))
        assertTrue(samePalletPickPlan(old, old.copy()))
    }

    @Test fun `scan proof survives reopening and corrupted proof is rejected`() {
        val plan = buildPalletPickPlan(line(), 15.0, response().toString())
        assertEquals(plan, palletPlanFromJson(palletPlanJson(plan)))
        assertNull(palletPlanFromJson(""))
        assertNull(palletPlanFromJson("{}"))
    }

    @Test fun `BADE always requires pallet workflow without changing EMU policy`() {
        assertTrue(requiresPalletWorkflow("bade"))
        assertFalse(requiresPalletWorkflow("emu"))
        assertFalse(requiresPalletWorkflow("dynops"))
    }

    @Test fun `mandatory putaway verifies pallet without product barcode with or without stamped LP`() {
        for (lp in listOf("", "LP0001")) {
            val steps = putAwayScanSteps(true, lp, "A-01")
            assertEquals(listOf(PutAwayStep.LP, PutAwayStep.SOURCE_BIN, PutAwayStep.TARGET_BIN, PutAwayStep.QTY), steps)
            assertFalse(steps.contains(PutAwayStep.ITEM))
        }
        assertEquals(listOf(PutAwayStep.LP, PutAwayStep.TARGET_BIN, PutAwayStep.QTY), putAwayScanSteps(true, "", ""))
    }

    @Test fun `optional putaway keeps the existing product verification for other customers`() {
        assertEquals(listOf(PutAwayStep.SOURCE_BIN, PutAwayStep.ITEM, PutAwayStep.TARGET_BIN, PutAwayStep.QTY),
            putAwayScanSteps(false, "", "A-01"))
    }
}
