package com.dynops.bcwms.feature

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TransferShipWorkflowTest {
    private fun line(
        lineNo: Int,
        itemNo: String,
        outstanding: Double,
        lot: Boolean = false,
        serial: Boolean = false,
        gtin: String = "",
    ) = TransferLineSummary(lineNo, itemNo, "", "ADET", outstanding, "", gtin, lot, serial)

    @Test
    fun `status and receiver ordinals match the AL enums`() {
        assertEquals(EDespatchStatus.Draft, EDespatchStatus.fromValue(1))
        assertEquals(EDespatchStatus.NotRequired, EDespatchStatus.fromValue("9"))
        assertEquals(EDespatchStatus.WaitingAdapter, EDespatchStatus.fromValue("WaitingAdapter"))
        assertEquals(EDespatchStatus.Pending, EDespatchStatus.fromValue(null))
        assertEquals(EDespatchReceiverType.Vendor, EDespatchReceiverType.fromValue(2))
        assertEquals(EDespatchReceiverType.Customer, EDespatchReceiverType.fromValue("Customer"))
        assertEquals(EDespatchPurpose.Consignment, EDespatchPurpose.fromValue(3))
    }

    @Test
    fun `transfer orders without number are dropped and bad quantities become zero`() {
        val rows = listOf(
            JSONObject().put("no", "TO-1").put("transferFromCode", "ANA").put("transferToCode", "FASON")
                .put("outstandingQuantity", 12.5).put("lineCount", 2).put("requiresWhseShipment", false),
            JSONObject().put("no", "TO-2").put("outstandingQuantity", "abc"),
            JSONObject().put("no", "").put("outstandingQuantity", 1),
        )
        val orders = parseTransferOrders(rows)
        assertEquals(listOf("TO-1", "TO-2"), orders.map { it.no })
        assertEquals("FASON", orders.first().toCode)
        assertEquals(12.5, orders.first().outstandingQuantity, 0.0001)
        assertEquals(0.0, orders[1].outstandingQuantity, 0.0)
    }

    @Test
    fun `fully shipped and itemless transfer lines are hidden`() {
        val rows = listOf(
            JSONObject().put("lineNo", 10000).put("itemNo", "HG-120").put("outstandingQuantity", 4).put("lotRequired", true),
            JSONObject().put("lineNo", 20000).put("itemNo", "BH-01").put("outstandingQuantity", 0),
            JSONObject().put("lineNo", 30000).put("itemNo", "").put("outstandingQuantity", 3),
        )
        val lines = parseTransferLines(rows)
        assertEquals(listOf(10000), lines.map { it.lineNo })
        assertTrue(lines.first().lotRequired)
    }

    @Test
    fun `scanned item or GTIN finds its transfer line`() {
        val lines = listOf(line(10000, "HG-120", 40.0, gtin = "08690000000017"), line(20000, "BH-01", 5.0))
        assertEquals(10000, matchTransferLine(lines, "hg-120")?.lineNo)
        assertEquals(10000, matchTransferLine(lines, "8690000000017")?.lineNo)
        assertNull(matchTransferLine(lines, "XX"))
    }

    @Test
    fun `ship entries cannot exceed outstanding and must carry tracking`() {
        val lines = listOf(line(10000, "HG-120", 40.0), line(20000, "BH-01", 5.0, lot = true), line(30000, "SN-1", 2.0, serial = true))
        assertEquals("En az bir satıra sevk miktarı girin.", validateShipEntries(lines, emptyList()))
        assertTrue(validateShipEntries(lines, listOf(TransferShipEntry(10000, 41.0)))!!.contains("kalan 40"))
        assertTrue(validateShipEntries(lines, listOf(TransferShipEntry(20000, 1.0)))!!.contains("lot"))
        assertTrue(validateShipEntries(lines, listOf(TransferShipEntry(30000, 2.0, serialNo = "S1")))!!.contains("miktar 1"))
        assertNull(validateShipEntries(lines, listOf(TransferShipEntry(10000, 40.0), TransferShipEntry(20000, 5.0, lotNo = "L1"))))
    }

    @Test
    fun `ship lines json only carries positive quantities and tracking when present`() {
        val json = JSONArray(buildShipLinesJson(listOf(TransferShipEntry(10000, 3.0), TransferShipEntry(20000, 0.0), TransferShipEntry(30000, 1.0, lotNo = " L7 "))))
        assertEquals(2, json.length())
        assertFalse(json.getJSONObject(0).has("lotNo"))
        assertEquals("L7", json.getJSONObject(1).getString("lotNo"))
    }

    @Test
    fun `changes json sends only edited fields with normalized plate and TCKN`() {
        val json = buildChangesJson(
            EDespatchChanges(
                receiverType = EDespatchReceiverType.Vendor,
                receiverNo = " V001 ",
                vehiclePlateNo = "16 abc 123",
                driverIdentificationNo = "123 456 789 01",
            ),
        )
        assertEquals(2, json.getInt("receiverType"))
        assertEquals("V001", json.getString("receiverNo"))
        assertEquals("16ABC123", json.getString("vehiclePlateNo"))
        assertEquals("12345678901", json.getString("driverIdentificationNo"))
        assertFalse(json.has("note"))
        assertFalse(json.has("purpose"))
    }

    @Test
    fun `plate normalization keeps Latin letters stable`() {
        assertEquals("34ABC12", normalizePlate(" 34 abc 12 "))
        // Turkish dotless/dotted i must not become a different letter.
        assertEquals("34İ12", normalizePlate("34İ12"))
    }

    @Test
    fun `vehicle validation follows the GIB rules`() {
        assertEquals("Araç plakasını girin.", validateVehicleInfo("", "Ali", "Kaya", "", ""))
        assertEquals("Nakliyeci yoksa şoför adı ve soyadı gerekli.", validateVehicleInfo("16ABC123", "Ali", "", "", ""))
        assertNull(validateVehicleInfo("16ABC123", "", "", "", "ARAS"))
        assertEquals("Şoför TCKN 11 haneli olmalı.", validateVehicleInfo("16ABC123", "Ali", "Kaya", "123", ""))
        assertNull(validateVehicleInfo("", "", "", "", "", requireVehicle = false))
    }

    @Test
    fun `new transfer needs two different locations and lines`() {
        assertEquals("Kaynak lokasyonu seçin.", validateNewTransfer("", "FASON", listOf(NewTransferLine("A", 1.0))))
        assertTrue(validateNewTransfer("ANA", "ana", listOf(NewTransferLine("A", 1.0)))!!.contains("aynı lokasyon"))
        assertEquals("En az bir ürün okutun.", validateNewTransfer("ANA", "FASON", emptyList()))
        assertNull(validateNewTransfer("ANA", "FASON", listOf(NewTransferLine("A", 2.0))))
    }

    @Test
    fun `create and ship json carries locations bins lines and receiver`() {
        val body = JSONObject(
            buildCreateAndShipJson(
                "ana", "fason", "v001",
                listOf(NewTransferLine("HG-120", 4.0, lotNo = "L1"), NewTransferLine("X", 0.0)),
                EDespatchChanges(receiverType = EDespatchReceiverType.Vendor, receiverNo = "V001", purpose = EDespatchPurpose.Subcontracting),
            ),
        )
        assertEquals("ANA", body.getString("fromLocationCode"))
        assertEquals("FASON", body.getString("toLocationCode"))
        assertEquals("V001", body.getString("toBinCode"))
        assertEquals(1, body.getJSONArray("lines").length())
        assertEquals(2, body.getInt("purpose"))
        assertEquals(2, body.getInt("receiverType"))
    }

    @Test
    fun `sheet actions follow the request status`() {
        val draft = eDespatchActionsFor(EDespatchStatus.Draft, editable = true)
        assertTrue(draft.containsAll(listOf(EDespatchAction.Save, EDespatchAction.Send, EDespatchAction.PrintA4, EDespatchAction.PrintThermal)))
        val sent = eDespatchActionsFor(EDespatchStatus.Sent, editable = false)
        assertFalse(sent.contains(EDespatchAction.Save))
        assertFalse(sent.contains(EDespatchAction.Send))
        assertTrue(sent.contains(EDespatchAction.PrintThermal))
        val waiting = eDespatchActionsFor(EDespatchStatus.WaitingAdapter, editable = true, providerConnected = false)
        assertTrue(waiting.contains(EDespatchAction.PrintSlip))
        assertFalse(waiting.contains(EDespatchAction.Send))
        assertTrue(eDespatchActionsFor(EDespatchStatus.NotRequired, editable = false).isEmpty())
        val error = eDespatchActionsFor(EDespatchStatus.Error, editable = true)
        assertTrue(error.containsAll(listOf(EDespatchAction.Save, EDespatchAction.Retry, EDespatchAction.Send)))
        val draftOffline = eDespatchActionsFor(EDespatchStatus.Draft, editable = true, providerConnected = false)
        assertTrue(draftOffline.contains(EDespatchAction.Save))
        assertTrue(draftOffline.contains(EDespatchAction.PrintSlip))
        assertFalse(draftOffline.contains(EDespatchAction.PrintThermal))
    }

    @Test
    fun `thermal format prints on the thermal printer usage`() {
        assertEquals(PRINTER_USAGE_THERMAL, printerUsageFor(EDespatchPrintFormat.Thermal80))
        assertEquals(PRINTER_USAGE_DOCUMENT, printerUsageFor(EDespatchPrintFormat.A4Official))
        assertNull(thermalPrinterSelectionIssue(true, "pdf"))
        assertNotNull(thermalPrinterSelectionIssue(true, "ZPL"))
    }

    @Test
    fun `bound action results are unwrapped from the OData value`() {
        val inner = JSONObject()
            .put("transferOrderNo", "TO-9")
            .put("postedShipmentNo", "TS-9")
            .put("eDespatchRequired", true)
            .put("eDespatch", JSONObject().put("entryNo", 12).put("status", 1))
        val result = parseTransferShipResult(JSONObject().put("value", inner.toString()).toString())
        assertNotNull(result)
        assertEquals("TS-9", result!!.postedShipmentNo)
        assertEquals(12, result.requestEntryNo)
        assertEquals(EDespatchStatus.Draft, result.status)

        val movement = parseMovementRegisterResult(
            JSONObject().put("value", JSONObject().put("registeredNo", "RM-1").put("eDespatchRequired", false).toString()).toString(),
        )
        assertEquals("RM-1", movement!!.registeredNo)
        assertEquals(0, movement.requestEntryNo)
    }

    @Test
    fun `summary line explains skipped and failed requests`() {
        assertTrue(eDespatchSummaryLine(JSONObject().put("status", 9).put("skipReason", "aynı lokasyon")).contains("gerekmiyor"))
        assertTrue(eDespatchSummaryLine(JSONObject().put("status", 7).put("lastError", "Alias yok")).contains("HATA"))
        assertTrue(eDespatchSummaryLine(JSONObject().put("status", 3).put("eDespatchNo", "IRS1").put("receiverName", "Fason A")).contains("IRS1"))
    }

    @Test
    fun `quantities print without trailing zeros`() {
        assertEquals("40", fmtQty(40.0))
        assertEquals("2.5", fmtQty(2.5))
        assertEquals("0.125", fmtQty(0.125))
    }
}
