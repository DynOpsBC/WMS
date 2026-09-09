package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * LP okutmalı toplama ve toplu LP planı için saf mantık testleri.
 *
 * Bu senaryolar gerçek bir el terminali olmadan doğrulanabilen tek katmandır:
 * palet planı hesabı, aday palet eşleştirmesi ve cihazda saklanan bekleyen
 * isteğin geri yüklenmesi. Sunucu doğrulaması (madde/lot/raf) BC tarafındadır
 * ve buradan sınanamaz.
 */
class LpScanVerificationTest {

    // --- Toplu LP planı ------------------------------------------------------

    @Test
    fun `plan splits stock into full pallets plus one remainder`() {
        val plan = planLedgerLps(allocatableQuantity = 10350.0, quantityPerLp = 1000.0)
        assertNotNull(plan)
        assertEquals(10, plan!!.fullCount)
        assertEquals(350.0, plan.lastQuantity, 0.00001)
        assertEquals(11, plan.totalLpCount)
        assertEquals(10350.0, plan.totalQuantity, 0.00001)
    }

    @Test
    fun `plan without remainder produces only full pallets`() {
        val plan = planLedgerLps(allocatableQuantity = 5000.0, quantityPerLp = 1000.0)
        assertNotNull(plan)
        assertEquals(5, plan!!.fullCount)
        assertEquals(0.0, plan.lastQuantity, 0.00001)
        assertEquals(5, plan.totalLpCount)
    }

    @Test
    fun `stock smaller than pallet capacity becomes a single remainder pallet`() {
        val plan = planLedgerLps(allocatableQuantity = 350.0, quantityPerLp = 1000.0)
        assertNotNull(plan)
        assertEquals(0, plan!!.fullCount)
        assertEquals(350.0, plan.lastQuantity, 0.00001)
        assertEquals(1, plan.totalLpCount)
    }

    @Test
    fun `fractional capacity keeps the real remainder`() {
        // 3 x 33.33 = 99.99; kalan 0.01 gerçek bir artıktır ve korunmalıdır.
        val plan = planLedgerLps(allocatableQuantity = 100.0, quantityPerLp = 33.33)
        assertNotNull(plan)
        assertEquals(3, plan!!.fullCount)
        assertEquals(0.01, plan.lastQuantity, 0.00001)
    }

    @Test
    fun `invalid capacity or stock yields no plan`() {
        assertNull(planLedgerLps(1000.0, 0.0))
        assertNull(planLedgerLps(1000.0, -5.0))
        assertNull(planLedgerLps(1000.0, null))
        assertNull(planLedgerLps(1000.0, Double.NaN))
        assertNull(planLedgerLps(0.0, 100.0))
    }

    // --- Plan doğrulaması ----------------------------------------------------

    @Test
    fun `remainder plan that exactly consumes available stock is accepted`() {
        assertTrue(
            validLedgerBulkLpPlan(
                lpCount = 10,
                quantityPerLp = 1000.0,
                allocatableQuantity = 10350.0,
                serialNo = "",
                quantityLastLp = 350.0,
            ),
        )
    }

    @Test
    fun `plan exceeding available stock is rejected`() {
        assertFalse(
            validLedgerBulkLpPlan(
                lpCount = 10,
                quantityPerLp = 1000.0,
                allocatableQuantity = 10000.0,
                serialNo = "",
                quantityLastLp = 350.0,
            ),
        )
    }

    @Test
    fun `remainder pushing the batch past one hundred pallets is rejected`() {
        assertFalse(
            validLedgerBulkLpPlan(
                lpCount = 100,
                quantityPerLp = 10.0,
                allocatableQuantity = 100000.0,
                serialNo = "",
                quantityLastLp = 5.0,
            ),
        )
    }

    @Test
    fun `serial tracked stock allows only a single unit pallet`() {
        assertTrue(validLedgerBulkLpPlan(1, 1.0, 10.0, "SER-1", 0.0))
        assertFalse(validLedgerBulkLpPlan(1, 1.0, 10.0, "SER-1", 1.0))
        assertFalse(validLedgerBulkLpPlan(2, 1.0, 10.0, "SER-1", 0.0))
    }

    @Test
    fun `plan without remainder keeps behaving like the previous package`() {
        assertTrue(validLedgerBulkLpPlan(10, 100.0, 1000.0, ""))
        assertFalse(validLedgerBulkLpPlan(11, 100.0, 1000.0, ""))
    }

    // --- İstek gövdesi ve bekleyen istek -------------------------------------

    @Test
    fun `payload omits the remainder field when there is none`() {
        val body = JSONObject(
            ledgerBulkLpPayload("TPL", "", 10, 1000.0, "ZPL01", true, "req-1"),
        )
        assertFalse(body.has("quantityLastLp"))
        assertEquals(10, body.getInt("lpCount"))
    }

    @Test
    fun `payload carries the remainder when one is planned`() {
        val body = JSONObject(
            ledgerBulkLpPayload("TPL", "", 10, 1000.0, "ZPL01", true, "req-1", 350.0),
        )
        assertEquals(350.0, body.getDouble("quantityLastLp"), 0.00001)
        assertEquals(10, body.getInt("lpCount"))
    }

    @Test
    fun `pending remainder request survives a round trip`() {
        val requestId = "8f14e45f-ceea-467a-9f6b-1c2d3e4f5a6b"
        val request = PendingLedgerBulkLpRequest(
            entryNo = 8338,
            expectedCount = 11,
            printLabels = true,
            requestId = requestId,
            body = ledgerBulkLpPayload("TPL", "", 10, 1000.0, "ZPL01", true, requestId, 350.0),
            action = LEDGER_BULK_LP_PLAN_ACTION,
        )
        val restored = pendingLedgerBulkLpRequestFromJson(pendingLedgerBulkLpRequestJson(request))
        assertNotNull(restored)
        assertEquals(11, restored!!.expectedCount)
        assertEquals(LEDGER_BULK_LP_PLAN_ACTION, restored.action)
    }

    @Test
    fun `pending request stored by an older build replays on the original action`() {
        val requestId = "8f14e45f-ceea-467a-9f6b-1c2d3e4f5a6b"
        val legacy = JSONObject().apply {
            put("entryNo", 8338)
            put("expectedCount", 10)
            put("printLabels", true)
            put("requestId", requestId)
            put("body", ledgerBulkLpPayload("TPL", "", 10, 1000.0, "ZPL01", true, requestId))
        }.toString()
        val restored = pendingLedgerBulkLpRequestFromJson(legacy)
        assertNotNull(restored)
        assertEquals(LEDGER_BULK_LP_CREATE_ACTION, restored!!.action)
    }

    @Test
    fun `remainder request whose total does not match the pallet count is rejected`() {
        val requestId = "8f14e45f-ceea-467a-9f6b-1c2d3e4f5a6b"
        val inconsistent = JSONObject().apply {
            put("entryNo", 8338)
            // 10 tam palet + artık = 11 olmalı; 10 saklanmış kayıt bozuktur.
            put("expectedCount", 10)
            put("printLabels", true)
            put("requestId", requestId)
            put("body", ledgerBulkLpPayload("TPL", "", 10, 1000.0, "ZPL01", true, requestId, 350.0))
            put("action", LEDGER_BULK_LP_PLAN_ACTION)
        }.toString()
        assertNull(pendingLedgerBulkLpRequestFromJson(inconsistent))
    }

    @Test
    fun `remainder request claiming the legacy action is rejected`() {
        val requestId = "8f14e45f-ceea-467a-9f6b-1c2d3e4f5a6b"
        val mismatched = JSONObject().apply {
            put("entryNo", 8338)
            put("expectedCount", 11)
            put("printLabels", true)
            put("requestId", requestId)
            put("body", ledgerBulkLpPayload("TPL", "", 10, 1000.0, "ZPL01", true, requestId, 350.0))
            put("action", LEDGER_BULK_LP_CREATE_ACTION)
        }.toString()
        assertNull(pendingLedgerBulkLpRequestFromJson(mismatched))
    }

    // --- Toplama: aday palet listesi -----------------------------------------

    private val sourcesJson = """
        {
          "activityNo": "PI000010",
          "lineNo": 10000,
          "itemNo": "AB.00118",
          "binCode": "A-01-01",
          "lotRequired": true,
          "sources": [
            {"lpNo":"LP000123","binCode":"A-01-01","lotNo":"A101809","availableBaseQty":1000.0},
            {"lpNo":"LP000124","binCode":"A-01-01","lotNo":"A101809","availableBaseQty":350.0}
          ]
        }
    """.trimIndent()

    @Test
    fun `source list is parsed in server order`() {
        val sources = parsePickLineSources(sourcesJson)
        assertEquals(2, sources.size)
        assertEquals("LP000123", sources[0].lpNo)
        assertEquals(1000.0, sources[0].availableBaseQty, 0.00001)
        assertEquals("A101809", sources[1].lotNo)
    }

    @Test
    fun `unreadable or empty source payloads never crash the screen`() {
        assertTrue(parsePickLineSources("").isEmpty())
        assertTrue(parsePickLineSources("not json").isEmpty())
        assertTrue(parsePickLineSources("""{"sources":[]}""").isEmpty())
        assertTrue(parsePickLineSources("""{"lineNo":1}""").isEmpty())
    }

    @Test
    fun `scanned pallet is matched case insensitively`() {
        val sources = parsePickLineSources(sourcesJson)
        assertEquals("LP000124", matchPickSource(sources, "lp000124")?.lpNo)
        assertEquals("LP000123", matchPickSource(sources, " LP000123 ")?.lpNo)
    }

    @Test
    fun `pallet outside the candidate list is not matched`() {
        val sources = parsePickLineSources(sourcesJson)
        assertNull(matchPickSource(sources, "LP999999"))
        assertNull(matchPickSource(sources, ""))
    }

    @Test
    fun `no candidate list means the device cannot pre-filter`() {
        assertNull(matchPickSource(emptyList(), "LP000123"))
    }
}
