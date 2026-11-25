package com.dynops.bcwms.ui

import com.dynops.bcwms.feature.receiptVendorLine
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class ItemCellTextTest {
    @Test fun `product name first, code and details second`() {
        val row = JSONObject().put("itemNo", "P-00546").put("description", "Sac (1500x3000x2 mm)").put("description2", "Galvaniz").put("variantCode", "")
        assertEquals("Sac (1500x3000x2 mm)\nP-00546 · Galvaniz", itemCellText(row))
    }
    @Test fun `code alone when there is no name, variant shown`() {
        assertEquals("0.26072.0000", itemCellText(JSONObject().put("itemNo", "0.26072.0000")))
        assertEquals("Kablo\nK1 · Varyant SIYAH", itemCellText(JSONObject().put("itemNo", "K1").put("description", "Kablo").put("variantCode", "SIYAH")))
    }
    @Test fun `vendor line on receipt cards`() {
        assertEquals("Tedarikçi: ÖZ METAL · Sipariş: 106007", receiptVendorLine("ÖZ METAL", "106007"))
        assertEquals("Sipariş: AS000003", receiptVendorLine("", "AS000003"))
        assertEquals("Tedarikçi: -", receiptVendorLine(" ", ""))
    }
}
