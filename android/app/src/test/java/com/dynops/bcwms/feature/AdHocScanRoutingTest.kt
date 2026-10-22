package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdHocScanRoutingTest {
    @Test
    fun `screen routing and location move are Kitoko only`() {
        assertTrue(adHocScreenScanRouting("kitoko"))
        assertFalse(adHocScreenScanRouting("bade"))
        assertFalse(adHocScreenScanRouting("emu"))
        assertTrue(adHocLocationMoveOffered("kitoko"))
        assertFalse(adHocLocationMoveOffered("bade"))
    }

    @Test
    fun `LP step advances source bin then LP then target`() {
        assertEquals(AdHocLpStep.SourceBin, adHocLpStep("", lpLoaded = false))
        assertEquals(AdHocLpStep.Lp, adHocLpStep("A-01", lpLoaded = false))
        assertEquals(AdHocLpStep.Target, adHocLpStep("A-01", lpLoaded = true))
        // LP okutulup raf LP'den doldurulduysa da hedef adımı
        assertEquals(AdHocLpStep.Target, adHocLpStep("", lpLoaded = true))
    }

    @Test
    fun `first scan of a bin sets the source bin`() {
        assertEquals(AdHocLpScan.SourceBin("A-01-02"), routeAdHocLpScan("A-01-02", AdHocLpStep.SourceBin))
    }

    @Test
    fun `LP scanned first loads the LP directly`() {
        assertEquals(AdHocLpScan.Lp(LpScanRef.ByNo("LP000021")), routeAdHocLpScan("lp000021", AdHocLpStep.SourceBin))
    }

    @Test
    fun `LP and SSCC are recognised in the LP step`() {
        assertEquals(AdHocLpScan.Lp(LpScanRef.ByNo("LP000021")), routeAdHocLpScan("LP000021", AdHocLpStep.Lp))
        assertEquals(AdHocLpScan.Lp(LpScanRef.BySscc("123456789012345678")), routeAdHocLpScan("00123456789012345678", AdHocLpStep.Lp))
    }

    @Test
    fun `non LP scan in LP step is checked as bin or item`() {
        val route = routeAdHocLpScan("AB.00005", AdHocLpStep.Lp)
        assertEquals(AdHocLpScan.BinOrItem("AB.00005", "AB.00005", ""), route)
    }

    @Test
    fun `GS1 item in LP step keeps item and lot`() {
        val route = routeAdHocLpScan("(01)08690000000017(10)LOT42", AdHocLpStep.Lp) as AdHocLpScan.BinOrItem
        assertEquals("LOT42", route.lotNo)
        assertEquals("08690000000017", route.itemNo)
    }

    @Test
    fun `target step accepts LP bin or SSCC`() {
        assertEquals(AdHocLpScan.Target("LP000099", isSscc = false), routeAdHocLpScan("LP000099", AdHocLpStep.Target))
        assertEquals(AdHocLpScan.Target("B-02", isSscc = false), routeAdHocLpScan("B-02", AdHocLpStep.Target))
        assertEquals(AdHocLpScan.Target("123456789012345678", isSscc = true), routeAdHocLpScan("123456789012345678", AdHocLpStep.Target))
    }

    @Test
    fun `document barcode and blank are rejected`() {
        assertTrue(routeAdHocLpScan("%R%RE000035", AdHocLpStep.SourceBin) is AdHocLpScan.Rejected)
        assertTrue(routeAdHocLpScan("   ", AdHocLpStep.Target) is AdHocLpScan.Rejected)
    }

    @Test
    fun `product flow routes bin item target and lot in order`() {
        assertEquals(AdHocProductStep.SourceBin, adHocProductStep("", "", ""))
        assertEquals(AdHocProductStep.Item, adHocProductStep("A-01", "", ""))
        assertEquals(AdHocProductStep.TargetBin, adHocProductStep("A-01", "ITEM1", ""))
        assertEquals(AdHocProductStep.Lot, adHocProductStep("A-01", "ITEM1", "B-01"))

        assertEquals(AdHocProductScan.SourceBin("A-01"), routeAdHocProductScan("A-01", AdHocProductStep.SourceBin))
        assertEquals(AdHocProductScan.Item("ITEM1", ""), routeAdHocProductScan("ITEM1", AdHocProductStep.Item))
        assertEquals(AdHocProductScan.TargetBin("B-01"), routeAdHocProductScan("B-01", AdHocProductStep.TargetBin))
        assertEquals(AdHocProductScan.Lot("L-9"), routeAdHocProductScan("L-9", AdHocProductStep.Lot))
    }

    @Test
    fun `LP scan in product flow opens LP workflow and is never a target bin`() {
        assertEquals(AdHocProductScan.OpenLp("LP000021"), routeAdHocProductScan("LP000021", AdHocProductStep.SourceBin))
        assertEquals(AdHocProductScan.OpenLp("LP000021"), routeAdHocProductScan("LP000021", AdHocProductStep.Item))
        assertTrue(routeAdHocProductScan("LP000021", AdHocProductStep.TargetBin) is AdHocProductScan.Rejected)
    }

    @Test
    fun `confirm label names the new location when it changes`() {
        assertEquals("✅ LP'yi DEPO2/R-01'e taşı (lokasyon değişir)", adHocLpConfirmLabel(false, true, "DEPO2", "R-01", false))
        assertEquals("✅ LP'yi B-02 Rafına Taşı", adHocLpConfirmLabel(false, false, "DEPO1", "B-02", false))
        assertEquals("Gönderiliyor...", adHocLpConfirmLabel(true, true, "DEPO2", "R-01", false))
    }

    @Test
    fun `old BC without moveToLocation is detected`() {
        assertTrue(adHocLocationMoveMissing(404, ""))
        assertTrue(adHocLocationMoveMissing(400, "The action moveToLocation does not exist"))
        assertFalse(adHocLocationMoveMissing(400, "DEPO1 yönlendirilmiş depo; Transfer Emri kullanın."))
    }
}
