package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDateTime

class ServiceWorkflowTest {
    private val now = LocalDateTime.of(2026, 11, 16, 12, 34, 56)
    @Test fun `status labels and colors cover standard statuses and preserve unknown labels`() {
        val labels = mapOf("Pending" to "Bekliyor", "In Process" to "İşlemde", "Finished" to "Tamamlandı", "On Hold" to "Beklemede")
        labels.forEach { (key, label) -> assertEquals(label, serviceStatusLabel(key)) }
        assertEquals("Yeni", serviceStatusLabel("Yeni"))
        assertEquals("success", serviceStatusColor("Finished"))
        assertEquals("warning", serviceStatusColor("On Hold"))
        assertEquals("primary", serviceStatusColor("In Process"))
        assertEquals("neutral", serviceStatusColor("Pending"))
    }
    @Test fun `priority labels and semantic colors`() {
        listOf(Triple("High", "Yüksek", "danger"), Triple("Medium", "Orta", "warning"), Triple("Low", "Düşük", "success"), Triple("Other", "Other", "neutral")).forEach {
            assertEquals(it.second, servicePriorityLabel(it.first))
            assertEquals(it.third, servicePriorityColor(it.first))
        }
    }
    @Test fun `hours round upward across dates using fallback for invalid rounding`() {
        assertEquals(0.0, serviceElapsedHours(null, now, .25), 0.0)
        assertEquals(0.0, serviceElapsedHours(now.plusSeconds(1), now, .25), 0.0)
        assertEquals(.25, serviceElapsedHours(now.minusSeconds(1), now, 0.0), 0.0)
        assertEquals(.25, serviceElapsedHours(now.minusMinutes(15), now, -1.0), 0.0)
        assertEquals(.5, serviceElapsedHours(now.minusMinutes(16), now, .25), 0.0)
        assertEquals(24.25, serviceElapsedHours(now.minusDays(1).minusSeconds(1), now, .25), 0.0)
        assertEquals(.25, serviceElapsedHours(now.minusSeconds(1), now, Double.NaN), 0.0)
        assertEquals(3.0, serviceElapsedHours(now.minusMinutes(180), now, .1), 0.0)
        assertEquals(.3, serviceElapsedHours(now.minusMinutes(17), now, .1), 0.0)
    }
    @Test fun `odata quotes are doubled without changing other characters`() {
        assertEquals("O''Brien & A", serviceODataText("O'Brien & A"))
        assertEquals("", serviceODataText(""))
    }
    @Test fun `menu preserves warehouse categories when disabled and supports all setup combinations`() {
        val warehouse = listOf("Gelen", "Giden", "İç Operasyon", "Üretim", "Kalite", "Sorgu", "Destek ve Ayarlar")
        assertEquals(warehouse, serviceCategories(false, false))
        assertEquals(listOf("Servis") + warehouse, serviceCategories(true, false))
        assertEquals(listOf("Servis", "Destek ve Ayarlar"), serviceCategories(true, true))
        assertEquals(warehouse, serviceCategories(false, true))
    }
    @Test fun `setup missing malformed and empty collection are safe`() {
        listOf("{}", "bad", "{\"value\":[]}").forEach { assertEquals(ServiceSetup(), parseServiceSetup(it)) }
        val setup = parseServiceSetup("""{"value":[{"enabled":true,"hideWarehouseModules":true,"allowTerminalPosting":true,"requireSignature":true,"isDispatcher":true,"laborRoundingHours":0.5,"defaultWorkTypeCode":"TAMIR"}]}""")
        assertEquals(ServiceSetup(true, true, true, true, .5, "TAMIR", true), setup)
        assertEquals(.25, parseServiceSetup("""{"laborRoundingHours":0}""").laborRoundingHours, 0.0)
        assertFalse(parseServiceSetup("""{"enabled":true}""").allowTerminalPosting)
    }
    @Test fun `file names use precise timestamp and attachment type`() {
        assertEquals("FOTO-SRV-1-20261116123456.jpg", serviceFileName("SRV-1", false, now))
        assertEquals("IMZA-SRV-1-20261116123456.png", serviceFileName("SRV-1", true, now))
    }
    @Test fun `action body preserves numeric boolean date and escaped text types`() {
        val json = JSONObject(serviceActionBody("serviceItemLineNo" to 10000, "hours" to 1.25, "consume" to false, "allocationDate" to "2026-11-16", "text" to "a\"\nğ"))
        assertEquals(10000, json.getInt("serviceItemLineNo"))
        assertTrue(json.get("hours") is Number)
        assertEquals(1.25, json.getDouble("hours"), 0.0)
        assertFalse(json.getBoolean("consume"))
        assertEquals("2026-11-16", json.getString("allocationDate"))
        assertEquals("a\"\nğ", json.getString("text"))
        assertEquals(0, JSONObject(serviceActionBody()).length())
    }
    @Test fun `bitmap scaling keeps aspect ratio and never upscales`() {
        assertEquals(1600 to 800, serviceBitmapSize(3200,1600))
        assertEquals(800 to 1600, serviceBitmapSize(1600,3200))
        assertEquals(300 to 200, serviceBitmapSize(300,200))
        assertEquals(1 to 1600, serviceBitmapSize(1,3200))
    }
    @Test(expected = IllegalArgumentException::class) fun `zero bitmap size is rejected`() { serviceBitmapSize(0, 1) }
    @Test fun `signature dimensions contain all points including fractional coordinates`() {
        assertEquals(1 to 1, serviceSignatureSize(emptyList()))
        assertEquals(12 to 22, serviceSignatureSize(listOf(10.1f to 20.5f, 2f to 3f)))
    }
    @Test fun `base64 is standard without line wrapping and handles empty input`() {
        assertEquals("", serviceBase64(byteArrayOf()))
        assertEquals("AAECA//+", serviceBase64(byteArrayOf(0,1,2,3,-1,-2)))
        assertFalse(serviceBase64(ByteArray(4000)).contains('\n'))
    }

    @org.junit.Test
    fun bcEncodedEnumNamesAreLabelled() {
        assertEquals("İşlemde", serviceStatusLabel("In_x0020_Process"))
        assertEquals("Beklemede", serviceStatusLabel("On_x0020_Hold"))
        assertEquals("Parça", serviceLineTypeLabel("Item"))
        assertEquals("İşçilik", serviceLineTypeLabel("Resource"))
        assertEquals("Çözüm", serviceCommentTypeLabel("Resolution"))
        assertEquals("", serviceDateText("0001-01-01"))
        assertEquals("16.11.2026", serviceDateText("2026-11-16"))
        assertEquals("14:05", serviceTimeText("14:05:33.12Z"))
        assertEquals("1,5", serviceQtyText(1.5))
        assertEquals("2", serviceQtyText(2.0))
        assertEquals(listOf("High", "Medium", "Low", "?"), listOf("Low", "?", "High", "Medium").sortedBy { servicePriorityRank(it) })
    }
    @Test fun `customer search ignores Turkish letters and case`() {
        assertTrue(serviceSearchMatches("tupras", "TÜPRAŞ İZMİT RAFİNERİ", "120.01.00004", "KÖRFEZ"))
        assertTrue(serviceSearchMatches("İzmit", "TÜPRAŞ İZMİT RAFİNERİ", "120.01.00004", ""))
        assertTrue(serviceSearchMatches("akçansa ataşehir", "AKÇANSA ÇİMENTO", "120.01.00008", "ATAŞEHİR/İSTANBUL"))
        assertTrue(serviceSearchMatches("00008", "AKÇANSA ÇİMENTO", "120.01.00008", ""))
        assertFalse(serviceSearchMatches("aksa", "AKÇANSA ÇİMENTO", "120.01.00008", ""))
        assertFalse(serviceSearchMatches("  ", "AKÇANSA", "1", ""))
    }

    @Test fun `setup parses id and technician flag for Yeni Servis`() {
        val s = parseServiceSetup("""{"value":[{"id":"abc","enabled":true,"isTechnician":true,"isDispatcher":false}]}""")
        assertEquals("abc", s.id)
        assertTrue(s.isTechnician)
        assertFalse(s.isDispatcher)
        assertEquals("", parseServiceSetup("{}").id)
    }
}
