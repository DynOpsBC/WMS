package com.dynops.bcwms

import com.dynops.bcwms.feature.allowAdminBypass
import com.dynops.bcwms.ui.assignedToMeClause
import com.dynops.bcwms.ui.canLoadAssignedOnlyList
import com.dynops.bcwms.ui.operatorFacingApiError
import com.dynops.bcwms.ui.operatorSupportReference
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
        assertFalse(allowAdminBypass("bade"))
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

        // 16 Eyl 2026: "does not exist" artık kaydın adıyla açıklanır, REF kodu kalır.
        assertTrue(visible, visible.startsWith("HATA: Ürün kaydı bulunamadı (No.=X)."))
        assertTrue(visible.contains("REF-"))
        assertFalse(visible.contains("Identification"))
        assertFalse(visible.contains("404"))
    }

    @Test
    fun `on-device error log resolves the REF code shown to the operator and stays bounded`() {
        ApiErrorLog.clear(null)
        val raw = "Report 60150 could not be rendered as PDF.  CorrelationId:  aa-bb."
        val entry = ApiErrorLog.record(null, "POST", "licensePlates('LP000025')/Microsoft.NAV.printMte", 400, raw)
        val shown = operatorFacingApiError(raw, 400)
        assertTrue(shown, shown.contains(entry.ref))
        assertEquals(operatorSupportReference(raw, 400), entry.ref)
        assertEquals(raw.trim(), ApiErrorLog.entries(null).first().message)
        repeat(ApiErrorLog.MAX_ENTRIES + 5) { i -> ApiErrorLog.record(null, "GET", "x/$i", 500, "e$i") }
        assertEquals(ApiErrorLog.MAX_ENTRIES, ApiErrorLog.entries(null).size)
        assertEquals("e${ApiErrorLog.MAX_ENTRIES + 4}", ApiErrorLog.entries(null).first().message)
        ApiErrorLog.clear(null)
    }

    @Test
    fun `report render failures from BC carry the real cause to the operator`() {
        // BADE 16 Eyl 2026: LP000025 MTE Yazdır yalnız REF-534F3BFA gösteriyordu.
        val permission = operatorFacingApiError(
            "60150 Madde Tanımlama Etiketi raporu PDF olarak oluşturulamadı. BC hatası: You do not have the following permissions on Report Madde Tanımlama Etiketi: Execute.  CorrelationId:  aa-bb.",
            400,
        )
        assertTrue(permission, permission.startsWith("HATA: 60150 Madde Tanımlama Etiketi raporu PDF olarak oluşturulamadı. Neden: Terminal kullanıcısının BC'de 'Madde Tanımlama Etiketi' (Report) nesnesi için Execute yetkisi yok."))
        assertFalse(permission.contains("CorrelationId"))

        val reportRule = operatorFacingApiError(
            "60150 Madde Tanımlama Etiketi raporu PDF olarak oluşturulamadı. BC hatası: Etiket basılacak kayıt bulunamadı. Filtre/selection kontrol edin.  CorrelationId:  aa-bb.",
            400,
        )
        assertTrue(reportRule, reportRule.contains("Neden: Etiket basılacak kayıt bulunamadı. Filtre/selection kontrol edin."))

        val qr = operatorFacingApiError("LP000025 LP QR belgesi oluşturulamadı. BC hatası: The report layout is missing.", 400)
        assertTrue(qr, qr.contains("LP000025 LP QR belgesi oluşturulamadı. Neden: The report layout is missing."))
    }

    @Test
    fun `license guard errors tell the operator that the license lapsed`() {
        val v = operatorFacingApiError("License is not active (Expired). Verification failed (expired)  CorrelationId:  aa-bb.", 400)
        assertTrue(v, v.startsWith("HATA: BCWMS lisansı aktif değil (Expired): Verification failed (expired). Yöneticiniz BC Kurulum"))
        assertFalse(v.contains("CorrelationId"))
        val tier = operatorFacingApiError("Feature PrintBridge requires the Advanced tier. Current license: Essentials.", 400)
        assertTrue(tier, tier.contains("PrintBridge için Advanced paketi gerekir (mevcut: Essentials)"))
        val seats = operatorFacingApiError("License seat limit reached (5 of 5). Upgrade the license or remove inactive devices.", 400)
        assertTrue(seats, seats.contains("cihaz sınırı doldu (5/5)"))
    }

    @Test
    fun `missing LP or overlong value errors name the record and value`() {
        val lp = operatorFacingApiError(
            "The DOPSWHS LP Header does not exist. Identification fields and values: No.='LP00099'  CorrelationId:  aa-bb.",
            400,
        )
        assertTrue(lp, lp.startsWith("HATA: LP kaydı bulunamadı (No.='LP00099'). Numarayı kontrol edip tekrar deneyin."))
        val tooLong = operatorFacingApiError(
            "The length of the string is 60, but it must be less than or equal to 50 characters. Value: ABCDEFGHIJ  CorrelationId:  aa-bb.",
            400,
        )
        assertTrue(tooLong, tooLong.contains("Girilen değer çok uzun (60 karakter, en fazla 50): ABCDEFGHIJ"))
        val perm = operatorFacingApiError("You do not have the following permissions on TableData Employee: Read.", 400)
        assertTrue(perm, perm.contains("'Employee' (TableData) nesnesi için Read yetkisi yok"))
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

    @Test
    fun `printer setup errors name the missing device selection`() {
        fun check(raw: String, expected: String) {
            val v = operatorFacingApiError(raw, 400)
            assertTrue("$raw -> $v", v.contains(expected))
            assertFalse(v.contains("Yazıcı ayarı tamamlanamadı"))
        }
        check("No WMS bridge printer is mapped for LP label printing. Configure Device Printer Mapping or pass a Printer Code.  CorrelationId:  aa-bb.", "etiket yazıcısı seçilmemiş")
        check("No PDF document printer is selected for LP QR printing.", "belge yazıcısı seçilmemiş")
        // BADE 15 Eyl 2026: MTE PDF route without a document printer / onto the ZPL printer.
        check("No WMS bridge printer is mapped for Receipt. Select a document printer or configure Device Printer Mapping.", "belge yazıcısı seçilmemiş")
        check("No WMS bridge printer is mapped for Receipt. Configure Device Printer Mapping or pass a Printer Code.", "belge yazıcısı seçilmemiş")
        check("Printer P2CC342466B9F4561 is configured for ZPL. Receipt document printing requires a PDF printer.  CorrelationId:  aa-bb.", "seçili yazıcı (P2CC342466B9F4561) ZPL etiket yazıcısı")
        check("Printer ZEBRA-01 is not registered.  CorrelationId:  aa-bb.", "Seçili yazıcı (ZEBRA-01) BC'de kayıtlı değil")
        check("Mapped printer PDF-02 is inactive.", "Seçili yazıcı (PDF-02) pasif")
        check("The LP label job was saved but Azure dispatch failed: Printer ZEBRA-01 has no Station ID.", "yazıcı ajanına iletilemedi")
    }
}
