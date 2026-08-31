package com.dynops.bcwms

import com.dynops.bcwms.feature.allowAdminBypass
import com.dynops.bcwms.ui.assignedToMeClause
import com.dynops.bcwms.ui.canLoadAssignedOnlyList
import com.dynops.bcwms.ui.operatorFacingApiError
import com.dynops.bcwms.ui.normalizeQtyInput
import com.dynops.bcwms.ui.operatorFacingStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProductionUxRulesTest {
    @Test
    fun `BADE always uses the production operation flow`() {
        assertTrue(shouldForceProductionFlow("bade"))
        assertFalse(shouldForceProductionFlow("dynops"))
        assertTrue(shouldForceProductionFlow("emu"))
    }

    @Test
    fun `emu customer home hides technical test screens`() {
        val screens = operatorHomeScreens("emu")
        assertFalse(Screen.TestCenter in screens)
        assertFalse(Screen.PostingTest in screens)
        assertFalse(Screen.SelfTest in screens)
        assertTrue(Screen.Printers in screens)
        assertTrue(Screen.HierarchicalLP in screens)
    }

    @Test
    fun `offline home only allows connection setup`() {
        assertTrue(isHomeTileEnabled(Screen.Connection, connected = false))
        assertTrue(isHomeTileEnabled(Screen.Help, connected = false))
        assertFalse(isHomeTileEnabled(Screen.Picking, connected = false))
        assertFalse(isHomeTileEnabled(Screen.Count, connected = false))
        assertTrue(isHomeTileEnabled(Screen.Packing, connected = true))
    }

    @Test
    fun `BADE operator menu hides support and destructive test tools`() {
        val screens = operatorHomeScreens("bade")

        assertTrue(Screen.Picking in screens)
        assertTrue(Screen.Packing in screens)
        assertTrue(Screen.LicensePlates in screens)
        assertTrue(Screen.Count in screens)
        assertTrue(Screen.CountV2 in screens)
        assertTrue(Screen.Subcontracting in screens)
        assertTrue(Screen.Printers in screens)
        assertTrue(Screen.Connection in screens)
        assertTrue(Screen.Help in screens)
        assertFalse(Screen.HierarchicalLP in screens)
        assertFalse(Screen.TestCenter in screens)
        assertFalse(Screen.PostingTest in screens)
        assertFalse(Screen.SelfTest in screens)
        assertFalse(Screen.FieldSettings in screens)
    }

    @Test
    fun `BADE admin test session can expose posting harness in debug flow`() {
        val screens = operatorHomeScreens("bade", includeAdminTestTools = true)

        assertTrue(Screen.TestCenter in screens)
        assertTrue(Screen.PostingTest in screens)
        assertFalse(Screen.SelfTest in screens)
        assertFalse(Screen.FieldSettings in screens)
    }

    @Test
    fun `BADE cannot bypass local operator authentication with service token`() {
        assertTrue(allowAdminBypass("bade"))
        assertTrue(allowAdminBypass("dynops"))
        assertTrue(allowAdminBypass("customer"))
    }

    @Test
    fun `assigned-only filtering fails closed when identity is unresolved`() {
        assertTrue(assignedToMeClause("", enabled = true)!!.contains("UNRESOLVED"))
        assertTrue(assignedToMeClause("operator", enabled = true)!!.contains("OPERATOR"))
        assertTrue(assignedToMeClause("operator", enabled = false) == null)
        assertFalse(canLoadAssignedOnlyList(showAll = false, localUserId = ""))
        assertTrue(canLoadAssignedOnlyList(showAll = true, localUserId = ""))
    }

    @Test
    fun `operator status hides transport and deployment details`() {
        val masked = operatorFacingStatus("HATA: Lot servisi yok (HTTP 404) — güncel BC uzantısını publish edin CorrelationId: abc")
        assertTrue(masked.startsWith("HATA: Lot bilgisi doğrulanamadı."))
        assertTrue(masked.contains("REF-"))
        assertFalse(masked.contains("HTTP"))
        assertFalse(masked.contains("CorrelationId"))
        assertEquals(
            "TAMAM: Sayım kaydedildi (sayıcı 2)",
            operatorFacingStatus("TAMAM: Sayım kaydedildi (slot 2) (HTTP 200)"),
        )
    }

    @Test
    fun `raw Business Central errors become Turkish support references`() {
        val visible = operatorFacingApiError("The Item does not exist. Identification fields: No.=X", 404)

        assertTrue(visible.startsWith("HATA: İşlem tamamlanamadı."))
        assertTrue(visible.contains("REF-"))
        assertFalse(visible.contains("Identification"))
        assertFalse(visible.contains("404"))
    }

    @Test
    fun `missing mandatory BC header field names the field for the operator`() {
        val visible = operatorFacingApiError(
            "Araç Sürücü Kodu must have a value in Warehouse Receipt Header: No.=RE000624. It cannot be zero or empty.  CorrelationId:  5331615a-d761",
            400,
        )
        assertTrue(visible, visible.startsWith("HATA: Zorunlu alan boş: Araç Sürücü Kodu (mal kabul başlığı)."))
        assertTrue(visible.contains("REF-"))
        assertFalse(visible.contains("CorrelationId"))
        assertFalse(visible.contains("No.="))
        assertTrue(
            operatorFacingApiError("Vendor Shipment No. must have a value in Warehouse Receipt Header: No.=RE1.", 400)
                .contains("Tedarikçi İrsaliye No"),
        )
    }

    @Test
    fun `operator missing from Local WMS Users is explained instead of masked`() {
        val visible = operatorFacingStatus(
            "HATA: Sayım V2 oluşturulamadı — The field User ID of table Count Counter contains a value (DYNOPS) that cannot be found in the related table (Local WMS User).  CorrelationId:  07a7d7e7",
        )
        assertTrue(visible, visible.contains("Terminal kullanıcısı (DYNOPS) bu şirketin Local WMS Users listesinde kayıtlı değil"))
        assertTrue(visible.contains("REF-"))
        assertFalse(visible.contains("CorrelationId"))
    }

    @Test
    fun `Turkish BCWMS AL errors reach the operator without the correlation tail`() {
        val visible = operatorFacingStatus(
            "HATA: Sayım V2 oluşturulamadı — Terminal kullanıcısı DYNOPS, BS GROUP şirketinin Local WMS Users listesinde kayıtlı değil. BC'de bu kullanıcıyı ekleyin.  CorrelationId:  8c7872a0-3fc9-4d36-98fb-d5cd70b6504b.",
        )
        assertEquals(
            "HATA: Sayım V2 oluşturulamadı — Terminal kullanıcısı DYNOPS, BS GROUP şirketinin Local WMS Users listesinde kayıtlı değil. BC'de bu kullanıcıyı ekleyin.",
            visible,
        )
        val posted = operatorFacingApiError("Araç bilgileri eksik (plaka ve sürücü). Terminalde \"Araç / Sürücü\" kartından girip tekrar kaydedin.  CorrelationId:  aa-bb.", 400)
        assertTrue(posted, posted.startsWith("HATA: Araç bilgileri eksik (plaka ve sürücü)."))
        assertTrue(posted.contains("REF-"))
        assertFalse(posted.contains("CorrelationId"))
        // English BC text stays masked even when it has Turkish captions inside.
        assertTrue(operatorFacingStatus("HATA: Araç Sürücü Kodu must have a value in Warehouse Receipt Header: No.=RE1.").contains("Zorunlu alan boş"))
    }

    @Test
    fun `common English AL validations never reach the operator`() {
        listOf(
            "HATA: Item No. is required.",
            "HATA: Quantity must be greater than zero.",
            "HATA: Cannot determine the source bin.",
            "HATA: The document is already posted.",
            "HATA: Nothing to register.",
            "HATA: Target bin was not found.",
        ).forEach { raw ->
            val visible = operatorFacingStatus(raw)
            assertTrue(raw, visible.startsWith("HATA:"))
            assertTrue(raw, visible.contains("REF-"))
            assertFalse(raw, visible.contains(raw.removePrefix("HATA: "), ignoreCase = true))
        }
    }

    @Test
    fun `quantity input accepts Turkish decimal comma and keeps a single separator`() {
        assertEquals("12.5", normalizeQtyInput("12,5"))
        assertEquals("200.5", normalizeQtyInput("200,5"))
        assertEquals("1.55", normalizeQtyInput("1.5.5"))
        assertEquals("100", normalizeQtyInput("1a0b0"))
    }

    @Test
    fun `known English BC business errors become actionable Turkish text`() {
        fun check(raw: String, expected: String) {
            val v = operatorFacingApiError(raw, 400)
            assertTrue("raw=<$raw> visible=<$v>", v.contains(expected))
        }
        check("You cannot handle more than the outstanding 300 units.  CorrelationId:  a1", "Kalan miktardan fazla giremezsiniz (kalan: 300)")
        check("Qty. to Ship must not be greater than 350 units in Warehouse Shipment Line No.='SH1',Line No.='10000'.", "(350) fazla olamaz")
        check("Status must be equal to 'Open'  in Warehouse Shipment Header: No.=SH1. Current value is 'Released'.", "serbest bırakılmış")
        check("Qty. to Handle (Base) in the item tracking assigned to the document line for item HM.00054 is currently 300. It must be 350.", "HM.00054 ürününün lot dağılımı (300) sevk miktarıyla (350) uyuşmuyor")
        // ASCII-only Turkish BADE rule text must reach the operator verbatim.
        check("Sevkiyat Acente Kodu zorunludur. Belge No: SAO.A100387  CorrelationId:  dd707135", "HATA: Sevkiyat Acente Kodu zorunludur. Belge No: SAO.A100387")
        check("You cannot assign new numbers from the number series E-IRSALIYE.  CorrelationId:  ea2bc9a8", "E-IRSALIYE numara serisi yeni numara veremiyor")
        check("Nothing to handle. Try the \"Show Summary (Directed Put-away and Pick)\" option when creating pick to inspect the error.", "Toplanacak miktar yok")
    }
}
