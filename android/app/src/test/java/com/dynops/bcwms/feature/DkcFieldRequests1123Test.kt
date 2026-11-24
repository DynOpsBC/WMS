package com.dynops.bcwms.feature

import com.dynops.bcwms.scanner.BarcodeIntentResolver
import com.dynops.bcwms.scanner.BarcodeKind
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** DKC saha istekleri (23 Kas 2026). */
class DkcFieldRequests1123Test {
    @Test
    fun lotLabelQrGivesItemWithSpacesAndLot() {
        val r = BarcodeIntentResolver.resolve("MADDE KODU=9MM KOVAN KASE(AKS); LOT NO=DKC26K107-001")
        assertEquals(BarcodeKind.Item, r.kind)
        assertEquals("9MM KOVAN KASE(AKS)", r.itemNo)
        assertEquals("DKC26K107-001", r.lotNo)
        val d = decideAdHocProductInput("MADDE KODU=KLC-10; LOT NO=DKC26L513-005")
        assertEquals("KLC-10", d.value)
        assertEquals("DKC26L513-005", d.lotNo)
    }

    @Test
    fun plainItemScanHasNoLot() {
        val d = decideAdHocProductInput("KLC-10")
        assertEquals("KLC-10", d.value)
        assertEquals("", d.lotNo)
    }

    @Test
    fun shipmentNeedsRegisteredPick() {
        fun line(toShip: Double, picked: Double, pickQty: Double = 0.0) =
            JSONObject().put("qtyToShip", toShip).put("qtyPicked", picked).put("pickQty", pickQty)
        assertNotNull(shipmentPickBlockReason(listOf(line(10.0, 0.0))))
        assertTrue(shipmentPickBlockReason(listOf(line(10.0, 0.0, 10.0)))!!.contains("kaydedilmemiş"))
        assertNull(shipmentPickBlockReason(listOf(line(10.0, 10.0))))
        // Eski BC (alan yok): engellenmez.
        assertNull(shipmentPickBlockReason(listOf(JSONObject().put("qtyToShip", 5.0))))
    }

    @Test
    fun productionPrepareUsesLotActionOnlyWithLot() {
        val withLot = ProductionOutputDraft("8f0d1f3e-0000-4000-8000-000000000001", "UR1", 10000, "X",
            JSONObject().put("quantity", 5.0).put("lotNo", "L1").toString())
        val noLot = withLot.copy(body = JSONObject().put("quantity", 5.0).toString())
        assertTrue(productionPreparePath(withLot).endsWith("prepareOutputWithLot"))
        assertTrue(productionPreparePath(noLot).endsWith("prepareOutput"))
        assertEquals("L1", productionRequestedLot(withLot))
    }
}

class DkcHareketBinContent1124Test {
    @Test
    fun binContentErrorKeepsDottedBinAndItem() {
        val raw = "The Bin Content does not exist. Identification fields and values: Location Code='DKC WMS',Bin Code='ÜR.0002',Item No.='9MM KOVAN KASE(AKS)',Variant Code='',Unit of Measure Code='ADET'"
        val msg = com.dynops.bcwms.ui.operatorKnownBcError(raw)!!
        assertTrue(msg, msg.contains("ÜR.0002"))
        assertTrue(msg, msg.contains("9MM KOVAN KASE(AKS)"))
        assertTrue(msg, msg.contains("ADET"))
    }

    @Test
    fun genericNotFoundDoesNotCutAtDotInValue() {
        val msg = com.dynops.bcwms.ui.operatorKnownBcError(
            "The Bin does not exist. Identification fields and values: Location Code='DKC WMS',Code='ÜR.0009'")!!
        assertTrue(msg, msg.contains("ÜR.0009"))
    }

    @Test
    fun typedLabelQrStillGivesLot() {
        val d = decideAdHocProductInput("MADDE KODU=9MM KOVAN KASE(AKS); LOT NO=DKC26L408-013")
        assertEquals("9MM KOVAN KASE(AKS)", d.value)
        assertEquals("DKC26L408-013", d.lotNo)
    }
}
