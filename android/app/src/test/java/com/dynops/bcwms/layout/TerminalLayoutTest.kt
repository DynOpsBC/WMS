package com.dynops.bcwms.layout

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

class TerminalLayoutTest {
    private val home = TerminalLayoutCatalog.HOME

    private fun layoutJson(vararg items: String) =
        """{"code":"DEPOCU","version":"DEPOCU.3.c1","items":[${items.joinToString(",")}]}"""

    private fun apiBody(layoutJson: String, version: String = "DEPOCU.3.c1") =
        JSONObject().put("value", org.json.JSONArray().put(JSONObject().put("code", "DEPOCU").put("version", version).put("layoutJson", layoutJson))).toString()

    // Menü kutusu yerine sade tip: (Screen enum adı, etiket)
    private data class Tile(val screenName: String, val label: String)
    private val giden = listOf(Tile("Picking", "Toplama"), Tile("Packing", "Paketleme"), Tile("Shipping", "Sevkiyat"))
    private fun keyOf(t: Tile) = TerminalLayoutCatalog.tileKey(t.screenName)

    @Test
    fun noLayoutKeepsMenuExactlyAsToday() {
        assertSame(giden, applyHomeLayout(giden, null, ::keyOf))
    }

    @Test
    fun hidesAndReordersWithinCategory() {
        val layout = TerminalLayout.parse(layoutJson(
            """{"screen":"HOME","key":"PICKING","visible":true,"sort":50}""",
            """{"screen":"HOME","key":"PACKING","visible":false,"sort":40}""",
            """{"screen":"HOME","key":"SHIPPING","visible":true,"sort":30,"label":"Çıkış"}""",
        ))!!
        val out = applyHomeLayout(giden, layout, ::keyOf)
        assertEquals(listOf("Shipping", "Picking"), out.map { it.screenName })
        assertEquals("Çıkış", layout.label(home, "SHIPPING"))
        assertNull(layout.label(home, "PICKING"))
    }

    @Test
    fun layoutCannotGrantAScreenTheRoleGatingRemoved() {
        // BADE canlı: Toplama yönetici değilse rol kuralıyla zaten çıkarılmış.
        val gated = giden.filter { it.screenName != "Picking" }
        val layout = TerminalLayout.parse(layoutJson("""{"screen":"HOME","key":"PICKING","visible":true,"sort":1}"""))!!
        assertEquals(listOf("Packing", "Shipping"), applyHomeLayout(gated, layout, ::keyOf).map { it.screenName })
    }

    @Test
    fun unknownTilesStayVisibleAfterTheirPredecessor() {
        val tiles = listOf(Tile("Picking", "Toplama"), Tile("BrandNewScreen", "Yeni"), Tile("Shipping", "Sevkiyat"))
        val layout = TerminalLayout.parse(layoutJson(
            """{"screen":"HOME","key":"PICKING","visible":true,"sort":30}""",
            """{"screen":"HOME","key":"SHIPPING","visible":true,"sort":10}""",
        ))!!
        assertEquals(listOf("Shipping", "Picking", "BrandNewScreen"), applyHomeLayout(tiles, layout, ::keyOf).map { it.screenName })
    }

    @Test
    fun missingItemsFallBackToCatalogDefaults() {
        // Yalnız Sevkiyat'ı öne alan yerleşim; diğerleri katalog sırasıyla.
        val layout = TerminalLayout.parse(layoutJson("""{"screen":"HOME","key":"SHIPPING","visible":true,"sort":5}"""))!!
        assertEquals(listOf("Shipping", "Picking", "Packing"), applyHomeLayout(giden, layout, ::keyOf).map { it.screenName })
    }

    @Test
    fun lockedConnectionTileCannotBeHidden() {
        val layout = TerminalLayout.parse(layoutJson("""{"screen":"HOME","key":"CONNECTION","visible":false}"""))!!
        assertTrue(layout.isVisible(home, "CONNECTION"))
    }

    @Test
    fun labelScreenButtonsFollowLayoutAndDefaultToVisible() {
        val layout = TerminalLayout.parse(layoutJson(
            """{"screen":"LABELS","key":"LABELS.RANGES","visible":false,"sort":30}""",
            """{"screen":"HOME","key":"RECEIVING","visible":true,"sort":10,"require":["LOT"],"note":"Lot zorunlu"}""",
        ))!!
        val b = TerminalLayoutCatalog.Buttons
        assertFalse(layout.isVisible(b.LABELS, b.LABELS_RANGES))
        assertTrue(layout.isVisible(b.LABELS, b.LABELS_ALL_ITEMS))
        assertTrue(layout.requires(home, "RECEIVING", "LOT"))
        assertEquals("Lot zorunlu", layout.note(home, "RECEIVING"))
    }

    @Test
    fun classifiesApiResponses() {
        val body = apiBody(layoutJson("""{"screen":"HOME","key":"PICKING","visible":false,"sort":30}"""))
        val loaded = classifyLayoutResponse(true, 200, body) as LayoutFetchResult.Loaded
        assertEquals("DEPOCU.3.c1", loaded.layout!!.version)
        assertFalse(loaded.layout!!.isVisible(home, "PICKING"))
        assertEquals(LayoutFetchResult.Loaded(null), classifyLayoutResponse(true, 200, """{"value":[]}"""))
        assertEquals(LayoutFetchResult.NotSupported, classifyLayoutResponse(false, 404, """{"error":{"code":"BadRequest_ResourceNotFound"}}"""))
        assertEquals(LayoutFetchResult.Failed, classifyLayoutResponse(false, 500, "boom"))
        assertEquals(LayoutFetchResult.Failed, classifyLayoutResponse(false, 0, "Token yok"))
        assertEquals(LayoutFetchResult.Failed, classifyLayoutResponse(true, 200, "not json"))
        assertEquals(LayoutFetchResult.Failed, classifyLayoutResponse(true, 200, """{"value":[{"layoutJson":"{broken"}]}"""))
    }

    @Test
    fun fallbackRules() {
        val cached = TerminalLayout.parse(layoutJson("""{"screen":"HOME","key":"PICKING","visible":false}"""))!!
        // Eski BC (404): bugünkü davranış.
        assertNull(nextCachedLayout(cached, LayoutFetchResult.NotSupported))
        // Geçici hata: son bilinen yerleşim korunur; önbellek yoksa bugünkü davranış.
        assertSame(cached, nextCachedLayout(cached, LayoutFetchResult.Failed))
        assertNull(nextCachedLayout(null, LayoutFetchResult.Failed))
        // BC'de yerleşim kaldırıldı.
        assertNull(nextCachedLayout(cached, LayoutFetchResult.Loaded(null)))
    }

    @Test
    fun refreshesAtMostEveryFiveMinutesUnlessForced() {
        val t0 = 1_000_000L
        assertTrue(shouldRefreshLayout(0L, t0, force = false))
        assertFalse(shouldRefreshLayout(t0, t0 + 60_000, force = false))
        assertTrue(shouldRefreshLayout(t0, t0 + TERMINAL_LAYOUT_REFRESH_MS, force = false))
        assertTrue(shouldRefreshLayout(t0, t0 + 1, force = true))
        assertTrue("clock moved back", shouldRefreshLayout(t0, t0 - 10, force = false))
    }

    @Test
    fun buildsFilterOnlyFromKnownIdentity() {
        assertEquals("terminalLayouts", terminalLayoutsPath("", ""))
        assertEquals("terminalLayouts?\$filter=terminalCode eq 'DEPO-01' and userName eq 'O''NEIL'", terminalLayoutsPath("DEPO-01", "O'NEIL"))
        assertEquals("terminalLayouts?\$filter=userName eq 'AHMET'", terminalLayoutsPath(" ", "AHMET"))
    }

    @Test
    fun cacheRoundTrip() {
        val layout = TerminalLayout.parse(layoutJson(
            """{"screen":"HOME","key":"RECEIVING","visible":false,"sort":15,"label":"Giriş","require":["LP","LOT"]}""",
        ))!!
        assertEquals(layout, TerminalLayout.parse(layout.toJson()))
    }

    @Test
    fun kitokoFirstCountTileCanBeHiddenOrRenamed() {
        // Kitoko menüsü: Sayım (CountV2) + İlk Sayım (FirstCount); klasik Sayım yok.
        val tiles = listOf(Tile("CountV2", "Sayım"), Tile("FirstCount", "İlk Sayım"))
        assertEquals("FIRST_COUNT", TerminalLayoutCatalog.tileKey("FirstCount"))
        val hidden = TerminalLayout.parse(layoutJson("""{"screen":"HOME","key":"FIRST_COUNT","visible":false,"sort":115}"""))!!
        assertEquals(listOf("CountV2"), applyHomeLayout(tiles, hidden, ::keyOf).map { it.screenName })
        val renamed = TerminalLayout.parse(layoutJson("""{"screen":"HOME","key":"FIRST_COUNT","visible":true,"sort":105,"label":"Açılış Sayımı"}"""))!!
        assertEquals(listOf("FirstCount", "CountV2"), applyHomeLayout(tiles, renamed, ::keyOf).map { it.screenName })
        assertEquals("Açılış Sayımı", renamed.label(home, "FIRST_COUNT"))
    }

    @Test
    fun catalogKeysMatchBusinessCentral() {
        val al = File("../../al/src/Panels/TerminalDesigner/TerminalLayoutMgt.Codeunit.al")
        assumeTrue("AL kaynağı bu çalışma dizininde yok", al.exists())
        val text = al.readText()
        val tiles = Regex("""AddTile\('[^']*', '([A-Z_0-9]+)'""").findAll(text).map { it.groupValues[1] }.toSet()
        val buttons = Regex("""AddButton\('([A-Z_]+)', '([A-Z_.0-9]+)'""").findAll(text)
            .groupBy({ it.groupValues[1] }, { it.groupValues[2] })
        assertEquals(TerminalLayoutCatalog.tileKeys, tiles)
        assertEquals(TerminalLayoutCatalog.Buttons.all.mapValues { it.value.toSet() }, buttons.mapValues { it.value.toSet() })
        tiles.forEach { key ->
            val sort = Regex("""AddTile\('[^']*', '$key', '(?:[^']|'')*', '(?:[^']|'')*', (\d+),""").find(text)?.groupValues?.get(1)?.toInt()
            assertEquals("default sort of $key", TerminalLayoutCatalog.defaultTileSort(key), sort)
        }
    }
}
