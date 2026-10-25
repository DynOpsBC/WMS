package com.dynops.bcwms.feature

import com.dynops.bcwms.BcApi
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Kitoko (21 Eki 2026): terminalde etiket tasarımı seçimi (labelLayouts). */
class LabelLayoutSelectorTest {
    private fun row(code: String, kind: String, description: String = "", width: Double = 80.0, height: Double = 40.0, active: Boolean = false) =
        JSONObject().put("code", code).put("description", description).put("labelKind", kind)
            .put("widthMm", width).put("heightMm", height).put("dpi", 203).put("active", active)

    private val rows = listOf(
        row("ETIKETV2", "Item", "Ürün V2", active = false),
        row("ITEM", "Item", "Ürün etiketi (varsayılan)", active = true),
        row("BIN", "Bin", "Raf etiketi (varsayılan)"),
        row("LP", "LP", "LP / palet etiketi (varsayılan)", width = 101.6, height = 50.8),
    )

    private fun page(rows: List<JSONObject>) = BcApi.PagedItemsResult(rows, complete = true)

    @Test fun `old BC without labelLayouts (404) hides the selector and keeps the old action`() {
        val load = labelLayoutsLoad(LabelLayoutKind.Item,
            BcApi.PagedItemsResult(emptyList(), complete = false, error = BcApi.ApiResult(false, 404, "Not found")))
        assertEquals(LabelLayoutLoad.Hidden, load)
        assertEquals("", rememberedLabelLayout("ETIKETV2", load))
        assertEquals("", effectiveLabelLayoutCode(load, "ETIKETV2"))
        assertEquals("printLabel", labelPrintAction(effectiveLabelLayoutCode(load, "ETIKETV2")))
    }

    @Test fun `only designs of the requested kind are offered`() {
        val item = labelLayoutsLoad(LabelLayoutKind.Item, page(rows)) as LabelLayoutLoad.Ready
        assertEquals(listOf("ETIKETV2", "ITEM"), item.options.map { it.code })
        val lp = labelLayoutsLoad(LabelLayoutKind.LP, page(rows)) as LabelLayoutLoad.Ready
        assertEquals(listOf("LP"), lp.options.map { it.code })
        assertEquals(LabelLayoutLoad.Hidden, labelLayoutsLoad(LabelLayoutKind.Zone, page(rows)))
    }

    @Test fun `default is blank and uses the old actions and payload`() {
        val load = labelLayoutsLoad(LabelLayoutKind.Item, page(rows))
        assertEquals("", rememberedLabelLayout("", load))
        assertEquals("", effectiveLabelLayoutCode(load, ""))
        assertEquals("printLabel", labelPrintAction(""))
        assertEquals("printLabels", labelPrintAction("", "printLabels"))
        val body = JSONObject(labelPrintPayload("ZPL01", 3, ""))
        assertEquals("ZPL01", body.getString("printerId"))
        assertEquals(3, body.getInt("copies"))
        assertFalse(body.has("layoutCode"))
        assertEquals("", labelLayoutNote(""))
    }

    @Test fun `remembered choice is restored and sent with the WithLayout action`() {
        val load = labelLayoutsLoad(LabelLayoutKind.Item, page(rows))
        val code = rememberedLabelLayout("etiketv2", load)
        assertEquals("ETIKETV2", code)
        assertEquals("ETIKETV2", effectiveLabelLayoutCode(load, code))
        assertEquals("printLabelWithLayout", labelPrintAction(code))
        assertEquals("printLabelsWithLayout", labelPrintAction(code, "printLabels"))
        assertEquals("ETIKETV2", JSONObject(labelPrintPayload("ZPL01", 1, code)).getString("layoutCode"))
    }

    @Test fun `a remembered design that is gone or of another kind falls back to default`() {
        val load = labelLayoutsLoad(LabelLayoutKind.Item, page(rows))
        assertEquals("", rememberedLabelLayout("SILINDI", load))
        assertEquals("", rememberedLabelLayout("BIN", load))
        assertEquals("", effectiveLabelLayoutCode(load, "BIN"))
    }

    @Test fun `a list read error keeps the remembered design without showing the selector`() {
        val load = labelLayoutsLoad(LabelLayoutKind.Bin,
            BcApi.PagedItemsResult(emptyList(), complete = false, error = BcApi.ApiResult(false, 503, "")))
        assertEquals(LabelLayoutLoad.Failed, load)
        assertEquals("RAF2", effectiveLabelLayoutCode(load, rememberedLabelLayout("RAF2", load)))
        assertEquals("", effectiveLabelLayoutCode(load, rememberedLabelLayout("", load)))
    }

    @Test fun `option title shows description and size`() {
        val options = (labelLayoutsLoad(LabelLayoutKind.Item, page(rows)) as LabelLayoutLoad.Ready).options
        assertEquals("Ürün V2 · 80×40", labelLayoutOptionTitle(options.first()))
        val lp = (labelLayoutsLoad(LabelLayoutKind.LP, page(rows)) as LabelLayoutLoad.Ready).options.single()
        assertEquals("LP / palet etiketi (varsayılan) · 101,6×50,8", labelLayoutOptionTitle(lp))
        assertEquals("X1", labelLayoutOptionTitle(LabelLayoutOption("X1", "", "Bin", 0.0, 0.0, 203, false)))
        assertTrue(options.single { it.code == "ITEM" }.active)
    }

    @Test fun `remembered choice is kept per company and kind`() {
        val a = labelLayoutPrefKey(terminalPreferenceScope("t", "Prod", "c1"), LabelLayoutKind.Item)
        val b = labelLayoutPrefKey(terminalPreferenceScope("t", "Prod", "c2"), LabelLayoutKind.Item)
        val c = labelLayoutPrefKey(terminalPreferenceScope("t", "Prod", "c1"), LabelLayoutKind.Bin)
        assertEquals(3, setOf(a, b, c).size)
    }

    @Test fun `LP design only changes the empty-LP label route, never MTE or document`() {
        assertEquals(LpPrintRoute("printLabelWithLayout", "ZPL01"),
            lpLabelRouteWithLayout(bulkLpPrintRoute(0, "ZPL01", "PDF01"), "LP2"))
        assertEquals(LpPrintRoute("printLabel", "ZPL01"),
            lpLabelRouteWithLayout(bulkLpPrintRoute(0, "ZPL01", "PDF01"), ""))
        assertEquals(LpPrintRoute("printPalletLabels", "ZPL01"),
            lpLabelRouteWithLayout(bulkLpPrintRoute(3, "ZPL01", "PDF01"), "LP2"))
        assertEquals(LpPrintRoute("printDocument", "PDF01"),
            lpLabelRouteWithLayout(bulkLpPrintRoute(0, "", "PDF01"), "LP2"))
    }
}
