package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONObject

class BulkLpBuildWorkflowTest {
    private fun completedBuild(
        printRequested: Boolean = true,
        failed: List<String> = emptyList(),
        replayed: Boolean = false,
        single: Boolean = false,
    ) = LedgerBulkLpBuildResult(
        createdLpNos = if (single) listOf("LP1") else listOf("LP1", "LP2"),
        failedPrintLpNos = failed,
        replayed = replayed,
        printSkippedOnReplay = replayed && printRequested,
        printLabelsRequested = printRequested,
        sourceEntryNo = 1234,
    )

    @Test
    fun `source entry must show the LP reference before success is reported`() {
        val entry = JSONObject().put("entryNo", 1234).put("lpNo", "LP1").put("lpNos", "")
        assertTrue(ledgerLpEntryReferenceMatches(1234, listOf("LP1"), listOf(entry), true))
        assertFalse(ledgerLpEntryReferenceMatches(1234, listOf("LP2"), listOf(entry), true))
        assertFalse(ledgerLpEntryReferenceMatches(1234, listOf("LP1"), listOf(entry), false))
        assertFalse(ledgerLpEntryReferenceMatches(5678, listOf("LP1"), listOf(entry), true))
        entry.put("lpNo", "")
        assertFalse(ledgerLpEntryReferenceMatches(1234, listOf("LP1"), listOf(entry), true))
        entry.put("lpNos", "LP1, LP2")
        assertTrue(ledgerLpEntryReferenceMatches(1234, listOf("LP1", "LP2"), listOf(entry), true))
        assertFalse(ledgerLpEntryReferenceMatches(1234, listOf("LP3"), listOf(entry), true))
    }

    @Test
    fun `truncated ILE display is allowed after exact LP line links are verified`() {
        val summary = (1..40).joinToString(", ") { "LP000$it" }.take(250)
        val entry = JSONObject().put("entryNo", 1234).put("lpNo", "").put("lpNos", summary)
        assertTrue(ledgerLpEntryReferenceMatches(1234, listOf("LP00040"), listOf(entry), true))
        assertFalse(ledgerLpEntryReferenceMatches(1234, listOf("LP00040"), emptyList(), true))
    }

    @Test
    fun `single LP requires a persisted link to the selected item ledger entry`() {
        val linked = JSONObject().put("lpNo", "LP1").put("sourceItemLedgerEntryNo", 1234).put("quantity", 100)
        assertTrue(ledgerLpSourceLinksMatch(1234, listOf("LP1"), listOf(linked), true))
        assertFalse(ledgerLpSourceLinksMatch(5678, listOf("LP1"), listOf(linked), true))
        assertFalse(ledgerLpSourceLinksMatch(1234, listOf("LP1"), listOf(linked), false))
        assertFalse(ledgerLpSourceLinksMatch(1234, listOf("LP1"), emptyList(), true))
        linked.remove("sourceItemLedgerEntryNo")
        assertFalse(ledgerLpSourceLinksMatch(1234, listOf("LP1"), listOf(linked), true))
    }

    @Test
    fun `all bulk LPs and all split bin lines must reference the selected source`() {
        fun line(no: String, source: Int = 1234) = JSONObject()
            .put("lpNo", no).put("sourceItemLedgerEntryNo", source).put("quantity", 50)
        val lpNos = listOf("LP1", "LP2")
        assertTrue(ledgerLpSourceLinksMatch(1234, lpNos, listOf(line("LP1"), line("LP1"), line("LP2")), true))
        assertFalse(ledgerLpSourceLinksMatch(1234, lpNos, listOf(line("LP1")), true))
        assertFalse(ledgerLpSourceLinksMatch(1234, lpNos, listOf(line("LP1"), line("LP2", 99)), true))
        assertFalse(ledgerLpSourceLinksMatch(1234, lpNos, listOf(line("LP1"), line("LP2"), line("LP3")), true))
    }

    @Test
    fun `source verification lookup escapes LP numbers and only filters one field`() {
        val path = ledgerLpSourceLookupPath(listOf("LP1", "LP'2"))
        assertTrue(path.contains("lpNo eq 'LP1' or lpNo eq 'LP''2'"))
        assertTrue(path.contains("sourceItemLedgerEntryNo"))
    }

    @Test
    fun `unprinted single and bulk LPs are selected for later label printing`() {
        assertEquals(setOf("LP1", "LP2"), ledgerLpPrintSelection(completedBuild(printRequested = false)))
        assertEquals(setOf("LP1"), ledgerLpPrintSelection(completedBuild(printRequested = false, single = true)))
        assertEquals(setOf("LP1", "LP2"), ledgerLpPrintSelection(completedBuild(printRequested = false, replayed = true)))
    }

    @Test
    fun `successful labels and uncertain replay labels are not automatically reprinted`() {
        assertTrue(ledgerLpPrintSelection(completedBuild()).isEmpty())
        assertEquals(setOf("LP2"), ledgerLpPrintSelection(completedBuild(failed = listOf("LP2"))))
        assertTrue(ledgerLpPrintSelection(completedBuild(replayed = true)).isEmpty())
    }

    @Test
    fun `single LP print failure remains visible with its source entry`() {
        val status = ledgerLpCompletionStatus(completedBuild(failed = listOf("LP1"), single = true))
        assertTrue(status.startsWith("UYARI:"))
        assertTrue(status.contains("#1234"))
        assertTrue(status.contains("1 etiket gönderilemedi"))
        assertTrue(status.contains("Seçilenleri Yazdır"))
    }

    @Test
    fun `completion distinguishes unprinted labels queued labels and replay`() {
        assertTrue(ledgerLpCompletionStatus(completedBuild(printRequested = false)).contains("henüz yazdırılmadı"))
        assertTrue(ledgerLpCompletionStatus(completedBuild()).contains("kuyruğa alındı"))
        assertTrue(ledgerLpCompletionStatus(completedBuild(replayed = true)).contains("yalnız eksikleri seçin"))
    }

    @Test
    fun `one ledger row can be allocated to ten LP records`() {
        assertTrue(validLedgerBulkLpPlan(10, 100.0, 1000.0, ""))
        assertFalse(validLedgerBulkLpPlan(11, 100.0, 1000.0, ""))
        assertFalse(validLedgerBulkLpPlan(0, 100.0, 1000.0, ""))
    }

    @Test
    fun `serial tracked ledger row cannot be split`() {
        assertTrue(validLedgerBulkLpPlan(1, 1.0, 1.0, "SER-1"))
        assertFalse(validLedgerBulkLpPlan(2, 1.0, 2.0, "SER-1"))
    }

    @Test
    fun `ledger bulk payload requests one separate label per LP`() {
        val requestId = "d2881548-a77f-43ef-ae09-b277671f7e22"
        val payload = JSONObject(
            ledgerBulkLpPayload("PALET", "A-01", 10, 100.0, "ZPL01", true, requestId),
        )

        assertEquals("PALET", payload.getString("templateCode"))
        assertEquals(10, payload.getInt("lpCount"))
        assertEquals(100.0, payload.getDouble("quantityPerLp"), 0.0)
        assertTrue(payload.getBoolean("printLabels"))
        assertEquals(requestId, payload.getString("requestId"))
    }

    @Test
    fun `blank bin requests automatic distribution across stock bins`() {
        val requestId = "d2881548-a77f-43ef-ae09-b277671f7e22"
        val payload = JSONObject(
            ledgerBulkLpPayload("PALET", "", 10, 100.0, "ZPL01", false, requestId),
        )
        val pending = PendingLedgerBulkLpRequest(
            entryNo = 4066,
            expectedCount = 10,
            printLabels = false,
            requestId = requestId,
            body = payload.toString(),
        )

        assertEquals("", payload.getString("binCode"))
        assertEquals(pending, pendingLedgerBulkLpRequestFromJson(pendingLedgerBulkLpRequestJson(pending)))
    }

    @Test
    fun `ledger bulk creation only uses the idempotent action`() {
        assertEquals("createLicensePlatesIdempotent", LEDGER_BULK_LP_CREATE_ACTION)
    }

    @Test
    fun `pending idempotent request survives serialization with the same UUID and body`() {
        val requestId = "d2881548-a77f-43ef-ae09-b277671f7e22"
        val body = ledgerBulkLpPayload("PALET", "A-01", 10, 100.0, "ZPL01", true, requestId)
        val pending = PendingLedgerBulkLpRequest(
            entryNo = 8742,
            expectedCount = 10,
            printLabels = true,
            requestId = requestId,
            body = body,
        )

        assertEquals(pending, pendingLedgerBulkLpRequestFromJson(pendingLedgerBulkLpRequestJson(pending)))

        val mismatched = JSONObject(pendingLedgerBulkLpRequestJson(pending))
            .put("requestId", "68f03988-2508-411c-ae32-26fbb880aa88")
            .toString()
        assertEquals(null, pendingLedgerBulkLpRequestFromJson(mismatched))
    }

    @Test
    fun `ledger bulk replay state distinguishes deliberately skipped printing`() {
        assertEquals(
            LedgerBulkLpReplayState.FirstExecution,
            ledgerBulkLpReplayState(replayed = false, printLabels = true, printSkippedOnReplay = false),
        )
        assertEquals(
            LedgerBulkLpReplayState.ReplayedWithPrintSkipped,
            ledgerBulkLpReplayState(replayed = true, printLabels = true, printSkippedOnReplay = true),
        )
        assertEquals(
            LedgerBulkLpReplayState.Replayed,
            ledgerBulkLpReplayState(replayed = true, printLabels = false, printSkippedOnReplay = false),
        )
    }

    @Test
    fun `contradictory replay and print flags are rejected`() {
        assertEquals(
            LedgerBulkLpReplayState.Invalid,
            ledgerBulkLpReplayState(replayed = false, printLabels = true, printSkippedOnReplay = true),
        )
        assertEquals(
            LedgerBulkLpReplayState.Invalid,
            ledgerBulkLpReplayState(replayed = true, printLabels = true, printSkippedOnReplay = false),
        )
        assertEquals(
            LedgerBulkLpReplayState.Invalid,
            ledgerBulkLpReplayState(replayed = true, printLabels = false, printSkippedOnReplay = true),
        )
    }

    @Test
    fun `numeric lookup searches entry and numeric item separately for BC OData`() {
        assertEquals(
            listOf("entryNo eq 1000", "itemNo eq '1000'", "lotNo eq '1000'"),
            itemLedgerLookupFilters(" 1000 "),
        )
        assertTrue(itemLedgerLookupFilters("8338").none { it.contains(" or ") })
        assertEquals(listOf("itemNo eq 'AB.00005'", "lotNo eq 'AB.00005'"), itemLedgerLookupFilters("AB.00005"))
        assertEquals("itemNo eq 'AB.00005'", itemLedgerLookupFilter("AB.00005"))
        assertEquals("itemNo eq 'O''RING'", itemLedgerLookupFilter("O'RING"))
    }

    @Test
    fun `lot lookup trims and escapes input without mixing OData fields`() {
        assertEquals(
            listOf("itemNo eq 'LOT''79'", "lotNo eq 'LOT''79'"),
            itemLedgerLookupFilters(" LOT'79 "),
        )
        assertEquals(
            listOf("entryNo eq 79", "itemNo eq '00079'", "lotNo eq '00079'"),
            itemLedgerLookupFilters("00079"),
        )
        assertTrue(itemLedgerLookupFilters("LOT79").none { it.contains(" or ") })
    }

    @Test
    fun `ledger lookup requests LP allocation fields with a legacy fallback path`() {
        val filter = itemLedgerLookupFilter("1000")

        val current = itemLedgerLookupPath(filter, includeLpAllocationFields = true)
        val legacy = itemLedgerLookupPath(filter, includeLpAllocationFields = false)
        assertTrue(current.contains("allocatedLpQuantity,lpAllocatableQuantity"))
        assertFalse(legacy.contains("allocatedLpQuantity"))
        assertTrue(legacy.contains("remainingQuantity"))
    }

    @Test
    fun `allocatable quantity uses server allocation and falls back for an older BC package`() {
        val current = JSONObject()
            .put("remainingQuantity", 1000.0)
            .put("allocatedLpQuantity", 400.0)
            .put("lpAllocatableQuantity", 600.0)
        val legacy = JSONObject().put("remainingQuantity", 1000.0)
        val legacyNull = JSONObject()
            .put("remainingQuantity", 1000.0)
            .put("lpAllocatableQuantity", JSONObject.NULL)

        assertEquals(600.0, ledgerLpAllocatableQuantity(current), 0.0)
        assertEquals(1000.0, ledgerLpAllocatableQuantity(legacy), 0.0)
        assertEquals(1000.0, ledgerLpAllocatableQuantity(legacyNull), 0.0)
    }

    @Test
    fun `ledger bulk response must contain every unique created LP number`() {
        val tenLpNos = (1..10).map { "LP${it.toString().padStart(6, '0')}" }

        assertTrue(validLedgerBulkLpResponse(10, 10, tenLpNos))
        assertFalse(validLedgerBulkLpResponse(10, 9, tenLpNos))
        assertFalse(validLedgerBulkLpResponse(10, 10, tenLpNos.dropLast(1)))
        assertFalse(validLedgerBulkLpResponse(10, 10, tenLpNos.dropLast(1) + tenLpNos.first()))
    }

    @Test
    fun `only failed print LP numbers from the created set are accepted for retry`() {
        val created = listOf("LP000001", "LP000002", "LP000003")

        assertTrue(validFailedPrintLpResponse(1, created, listOf("LP000002")))
        assertTrue(validFailedPrintLpResponse(0, created, emptyList()))
        assertFalse(validFailedPrintLpResponse(1, created, emptyList()))
        assertFalse(validFailedPrintLpResponse(1, created, listOf("LP999999")))
        assertFalse(validFailedPrintLpResponse(2, created, listOf("LP000002", "lp000002")))
    }

    @Test
    fun `location choices are normalized deduplicated and sorted`() {
        val options = bulkLpLocationOptions(
            listOf(
                JSONObject().put("code", " ZONE-B ").put("displayName", "İkinci Depo"),
                JSONObject().put("code", "").put("displayName", "Geçersiz"),
                JSONObject().put("code", "merkezdepo").put("displayName", "Merkez Depo"),
                JSONObject().put("code", "MERKEZDEPO").put("displayName", "Tekrar"),
            ),
        )

        assertEquals(listOf("merkezdepo", "ZONE-B"), options.map { it.code })
        assertEquals("merkezdepo · Merkez Depo", options.first().label)
        assertTrue(validBulkLpLocationSelection("MERKEZDEPO", true, options))
        assertFalse(validBulkLpLocationSelection("BILINMEYEN", true, options))
        assertFalse(validBulkLpLocationSelection("MERKEZDEPO", false, options))
    }

    @Test
    fun `common quantity is assigned to every LP and rows stay independent`() {
        val rows = commonLpQuantityDrafts(10, "100")

        assertEquals(10, rows.size)
        assertTrue(rows.all { it.quantity == "100" })
        val edited = rows.map { if (it.id == 10) it.copy(quantity = "80") else it }
        assertEquals("100", edited.first().quantity)
        assertEquals("80", edited.last().quantity)
    }

    @Test
    fun `bulk LP count is capped at the same one hundred limit as BC`() {
        assertTrue(commonLpQuantityDrafts(0, "1").isEmpty())
        assertTrue(commonLpQuantityDrafts(101, "1").isEmpty())
        assertEquals(100, commonLpQuantityDrafts(100, "1").size)
    }

    @Test
    fun `tracked stock error tells operator to scan the actual bin`() {
        val raw = "AB.00118 ürününün A.B01.17 rafındaki izlemeli serbest stoku yetersizdir " +
            "(lot A101298, seri ). İzlemeli stok: 0, aktif LP miktarı: 0, istenen: 98.392."

        val visible = ledgerBulkLpFriendlyError(raw, 400)

        assertEquals(
            "HATA: Seçtiğiniz ürün veya lot bu rafta yeterli miktarda yok. " +
                "Ürünün gerçekten bulunduğu rafı okutun. Ürün zaten bir LP içindeyse yeni LP oluşturmayın.",
            visible,
        )
        assertFalse(visible.contains("izlemeli"))
        assertFalse(visible.contains("aktif LP miktarı"))
        assertFalse(visible.contains("HTTP"))
    }

    @Test
    fun `allocation errors give a simple corrective action`() {
        assertEquals(
            "HATA: Bu stok kaydında seçtiğiniz toplam kadar kullanılabilir ürün yok. " +
                "LP adedini veya LP başı miktarı azaltın.",
            ledgerBulkLpFriendlyError(
                "3843 numaralı Madde Defter Girişinde LP'ye ayrılabilir miktar 80, istenen miktar 100'tür.",
                400,
            ),
        )
        assertEquals(
            "HATA: Seri numaralı ürünlerde her LP yalnızca 1 adet olabilir.",
            ledgerBulkLpFriendlyError("Seri takipli X maddesi yalnız 1 adetlik tek LP olarak oluşturulabilir.", 400),
        )
        assertEquals(
            "HATA: Raflardaki stok toplamı yeterli görünse de seçtiğiniz LP miktarıyla tam paletlere ayrılamıyor. " +
                "LP başı miktarı azaltın veya belirli bir raf okutarak o raftaki stoğu ayrı işlemde LP'leyin.",
            ledgerBulkLpFriendlyError(
                "AB.00118 ürününün raflara dağılmış LP'ye atanmamış stoku 1000 adettir ancak 100 adetlik 10 tam LP oluşturulamadı.",
                400,
            ),
        )
    }

    @Test
    fun `bulk LP creation does not require a bin`() {
        val rows = commonLpQuantityDrafts(3, "0")
        val payload = JSONObject(bulkLpBuildPayload("MERKEZDEPO", "", rows))

        assertTrue(rows.isNotEmpty())
        assertFalse(rows.any { it.quantity.toDouble() < 0.0 })
        assertEquals("MERKEZDEPO", payload.getString("locationCode"))
        assertEquals("", payload.getString("binCode"))
    }
}
