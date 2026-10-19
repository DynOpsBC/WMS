package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CountV2StaleBinTest {
    private val lines = listOf(
        JSONObject("""{"lpNo":"LP000186","binCode":"A.B07.11","foundFromBin":"A.B10.33"}"""),
        JSONObject("""{"lpNo":"LP000186","binCode":"A.B10.33","foundFromBin":""}"""),
        JSONObject("""{"lpNo":"","binCode":"A.B10.34","foundFromBin":""}"""),
    )

    @Test fun `live BADE message resolves the LP's own bin`() {
        val live = "HATA: R49799657BE5F4999A0D sayım belgesindeki LP000186 LP numarasının 10000 satırında güvenli olmayan " +
            "sistem miktarı var (sayım: 8,000, LP: 6,000). Önce Sayımı Yeniden Başlat eylemini çalıştırıp LP'yi yeniden okutun " +
            "veya yeni sayım belgesi oluşturun. (HTTP 400)"
        assertEquals("A.B10.33", countV2StaleBin(live, lines))
    }

    @Test fun `bin named in the message wins`() {
        val msg = "HATA: Raf A.B10.34 madde AB.00724 için kayıtlı stok sayım başladıktan sonra değişmiş veya LP dağılımı uyuşmuyor. " +
            "Sayım kartında bu raf için Rafı Yenile eylemini çalıştırıp rafı yeniden sayın."
        assertEquals("A.B10.34", countV2StaleBin(msg, lines))
    }

    @Test fun `other errors offer no refresh`() {
        assertNull(countV2StaleBin("HATA: Önce raf/bin barkodunu okutun.", lines))
        assertNull(countV2StaleBin("TAMAM: kaydedildi", lines))
    }

    @Test fun `refresh body carries the bin`() {
        assertEquals("A.B10.33", JSONObject(countV2RefreshBinBody("A.B10.33")).getString("binCode"))
    }
}
