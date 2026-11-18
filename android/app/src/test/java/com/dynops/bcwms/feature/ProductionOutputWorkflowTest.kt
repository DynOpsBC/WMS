package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProductionOutputWorkflowTest {
    private fun entry(lot: String, qty: Double, date: String, unit: String = "KG") = JSONObject()
        .put("lotNo", lot).put("quantity", qty).put("postingDate", date).put("baseUnitOfMeasure", unit)

    @Test
    fun ledgerQueryScopesTheExactOrderLineAndProductWithoutTruncatingReversals() {
        val path = productionOutputEntriesPath("UR'1", 20000, "TEL'5")
        assertTrue(path.contains("orderNo eq 'UR''1' and orderLineNo eq 20000"))
        assertTrue(path.contains("itemNo eq 'TEL''5' and entryType eq 'Output'"))
        assertFalse(path.contains("\$top="))
    }

    @Test
    fun largeHistoryIncludesReversalsAfterTheFirstPage() {
        val entries = (1..600).map { entry("LOT", 1.0, "2026-11-18") } + entry("LOT", -600.0, "2026-11-18")
        assertTrue(productionOutputLots(entries).isEmpty())
    }

    @Test
    fun invalidLabelQuantitiesAndUnknownBaseUnitAreRejected() {
        listOf(Double.NaN, Double.POSITIVE_INFINITY, -5.0, 0.0).forEach { qty ->
            assertTrue(productionLabelRows("X", "", "L", qty, "KG", 1).isEmpty())
        }
        assertTrue(productionLabelRows("X", "", "L", 5.0, "", 1).isEmpty())
    }

    @Test
    fun labelBatchesKeepTheProductionOrderLotBaseQuantityAndCopies() {
        val rows = productionLabelRows("TEL", "Tel", "L1", 12.5, "KG", 23)
        val batches = receiptLabelBatches(rows)
        assertEquals(listOf(10, 10, 3), batches.map { batch -> batch.sumOf { it.copies } })
        val json = org.json.JSONArray(receiptLabelRowsJson(batches.first(), "UR001", "18.11.2026")).getJSONObject(0)
        assertEquals("UR001", json.getString("receiptNo"))
        assertEquals("L1", json.getString("lotNo"))
        assertEquals("12,5 KG", json.getString("quantityText"))
    }

    @Test
    fun outputIsSummedPerLotAndReversalsAreDeducted() {
        // 5.50 MM TEL: 500 çıktı, 500 geri alındı, 480 yeniden çıktı — hepsi aynı lotta.
        val lots = productionOutputLots(
            listOf(
                entry("DKC26L715-004", 500.0, "2026-11-17"),
                entry("DKC26L715-004", -500.0, "2026-11-17"),
                entry("DKC26L715-004", 480.0, "2026-11-17"),
            ),
        )
        assertEquals(listOf(OutputLot("DKC26L715-004", 480.0, "KG", "2026-11-17")), lots)
    }

    @Test
    fun fullyReversedLotIsNotListedAndNewestLotComesFirst() {
        val lots = productionOutputLots(
            listOf(
                entry("LOT-A", 1478.0, "2026-11-15"),
                entry("LOT-A", -1478.0, "2026-11-16"),
                entry("LOT-B", 190.0, "2026-11-16"),
                entry("LOT-C", 100.0, "2026-11-18"),
            ),
        )
        assertEquals(listOf("LOT-C", "LOT-B"), lots.map { it.lotNo })
        assertTrue(productionOutputLots(emptyList()).isEmpty())
    }

    @Test
    fun percentComparesOutputWithThePlannedQuantity() {
        assertEquals(10, productionOutputPercent(1000.0, 100.0))
        assertEquals(0, productionOutputPercent(1000.0, 0.0))
        assertEquals(0, productionOutputPercent(0.0, 50.0))
        assertEquals(120, productionOutputPercent(500.0, 600.0))
    }

    @Test
    fun datesAreShownDayFirst() {
        assertEquals("18.11.2026", productionDateText("2026-11-18"))
        assertEquals("", productionDateText("0001-01-01"))
        assertEquals("", productionDateText(""))
    }

    @Test
    fun searchLooksAtOrderItemAndDescription() {
        val line = JSONObject().put("prodOrderNo", "UR000381").put("itemNo", "BILLET BPS").put("description", "BİLLET KURŞUN BPS")
        assertTrue(productionOutputMatches(line, ""))
        assertTrue(productionOutputMatches(line, "ur000381"))
        assertTrue(productionOutputMatches(line, "billet"))
        assertTrue(productionOutputMatches(line, "KURŞUN"))
        assertFalse(productionOutputMatches(line, "TEL"))
    }

    @Test
    fun labelRowCarriesLotQuantityAndCopies() {
        val rows = productionLabelRows("BILLET BPS", "BİLLET KURŞUN BPS", "DKC26L601-003", 100.0, "KG", 3)
        assertEquals(1, rows.size)
        assertEquals("DKC26L601-003", rows[0].lotNo)
        assertEquals(3, rows[0].copies)
        assertEquals("100 KG", receiptLabelQtyText(rows[0].quantity, rows[0].unit))
        assertTrue(productionLabelRows("BILLET BPS", "", "", 0.0, "KG", 1).isEmpty())
        assertTrue(productionLabelRows("", "", "", 5.0, "KG", 1).isEmpty())
        assertEquals(RECEIPT_LABEL_COPIES_MAX, productionLabelRows("X", "", "", 5.0, "KG", 999)[0].copies)
    }

    @Test
    fun consumableFollowsTheOutputAlreadyPosted() {
        // 200 KG'lik emirden 110 KG çıktı, birim başına 1,05 KG bileşen, henüz tüketim yok.
        val c = componentConsumption(finished = 110.0, qtyPer = 1.05, consumed = 0.0, remainingOnOrder = 210.0)
        assertEquals(115.5, c.neededForOutput, 0.0)
        assertEquals(115.5, c.consumableNow, 0.0)
        // 100 KG zaten tüketildiyse yalnız fark kalır.
        assertEquals(15.5, componentConsumption(110.0, 1.05, 100.0, 110.0).consumableNow, 0.0)
    }

    @Test
    fun nothingIsConsumableWhenMoreThanNeededWasAlreadyConsumed() {
        // UR000381: 100 KG çıktıda emrin bütün bileşeni (210 KG) tüketilmişti.
        val c = componentConsumption(finished = 110.0, qtyPer = 1.05, consumed = 210.0, remainingOnOrder = 0.0)
        assertEquals(0.0, c.consumableNow, 0.0)
        assertEquals(210.0, c.consumed, 0.0)
        // Çıktı yokken tüketilecek bir şey yoktur.
        assertEquals(0.0, componentConsumption(0.0, 1.05, 0.0, 210.0).consumableNow, 0.0)
    }

    @Test
    fun consumableNeverExceedsWhatIsLeftOnTheOrder() {
        assertEquals(40.0, componentConsumption(finished = 500.0, qtyPer = 1.0, consumed = 0.0, remainingOnOrder = 40.0).consumableNow, 0.0)
    }

    @Test
    fun consumedQuantityNetsReversalsPerItem() {
        fun e(item: String, qty: Double) = JSONObject().put("itemNo", item).put("quantity", qty)
        val used = consumedByItem(listOf(e("KLC-4", -210.0), e("KLC-4", 10.0), e("JMB-3", -50.0), e("X", 5.0)))
        assertEquals(200.0, used.getValue("KLC-4"), 0.0)
        assertEquals(50.0, used.getValue("JMB-3"), 0.0)
        assertEquals(0.0, used.getValue("X"), 0.0)
    }

    @Test
    fun onlyWhatWasPickedIntoTheProductionBinCanBeConsumed() {
        // Çıktıya göre 115,5 KG gerekir ama üretim gözüne 80 KG çekilmiş.
        assertEquals(80.0, componentConsumption(110.0, 1.05, 0.0, 210.0, pickedInBin = 80.0).consumableNow, 0.0)
        assertEquals(0.0, componentConsumption(110.0, 1.05, 0.0, 210.0, pickedInBin = 0.0).consumableNow, 0.0)
        // Göz okunamadıysa sınır uygulanmaz (ekran ayrıca uyarı gösterir).
        assertEquals(115.5, componentConsumption(110.0, 1.05, 0.0, 210.0, pickedInBin = null).consumableNow, 0.0)
    }
}
