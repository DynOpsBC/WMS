package com.dynops.bcwms.feature

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ItemLookupTest {
    @Test fun `lookup searches partial item number and description`() {
        val paths = itemLookupPaths("100")
        assertEquals(2, paths.size)
        assertTrue(paths.any { it.contains("contains(no,'100')") })
        assertTrue(paths.any { it.contains("contains(description,'100')") })
        assertTrue(paths.none { it.contains(" or ") })
        assertTrue(paths.all { it.endsWith("\$top=25") })
    }

    @Test fun `lookup escapes OData quotes`() {
        assertTrue(itemLookupPaths("A'1").all { it.contains("A''1", ignoreCase = true) })
    }

    @Test fun `lookup merges number and description matches without duplicates`() {
        val first = JSONObject().put("no", "STR 26").put("description", "KOVAN")
        val duplicate = JSONObject().put("no", "str 26").put("description", "KOVAN 9X19")
        val second = JSONObject().put("no", "9MM KOVAN").put("description", "STR-26")

        val rows = mergeItemLookupRows(listOf(listOf(first), listOf(duplicate, second)))

        assertEquals(listOf("9MM KOVAN", "STR 26"), rows.map { it.getString("no") })
    }

    @Test fun `spare parts lookup includes category and description filter`() {
        val paths = itemLookupPaths("CONV", sparePartsOnly = true)
        // no + açıklamanın üç yazılışı (CONV, conv, Conv)
        assertEquals(4, paths.size)
        assertTrue(paths.all { it.contains("contains(itemCategoryCode,'YEDEK')") })
    }

    @Test fun `isSparePart detects spare parts from category, description or number`() {
        val spareByCat = JSONObject().put("no", "ITM-01").put("description", "V KAYIS").put("itemCategoryCode", "YEDEK")
        val spareByDesc = JSONObject().put("no", "ITM-02").put("description", "YEDEK PARCA CIVATA")
        val spareByNo = JSONObject().put("no", "YP-100").put("description", "SOMUN")
        val normalItem = JSONObject().put("no", "ITM-03").put("description", "STANDART URUN")

        assertTrue(isSparePart(spareByCat))
        assertTrue(isSparePart(spareByDesc))
        assertTrue(isSparePart(spareByNo))
        assertTrue(!isSparePart(normalItem))
    }

    @Test fun `description is asked in the common spellings because BC compares case`() {
        val paths = itemLookupPaths("kovan")
        assertTrue(paths.any { it.contains("contains(no,'kovan')") })
        assertTrue(paths.any { it.contains("contains(description,'KOVAN')") })
        assertTrue(paths.any { it.contains("contains(description,'kovan')") })
        assertTrue(paths.any { it.contains("contains(description,'Kovan')") })
        assertTrue(paths.none { it.contains(" or ") })
    }

    @Test fun `turkish letters are upper cased the turkish way and the plain way`() {
        assertTrue(itemSearchVariants("deliği").contains("DELİĞİ"))
        assertTrue(itemSearchVariants("zimba").containsAll(listOf("ZİMBA", "ZIMBA")))
    }

    @Test fun `several words ask the server for the longest and keep rows holding all`() {
        val paths = itemLookupPaths("alev zımbası")
        assertTrue(paths.any { it.contains("contains(description,'ZIMBASI')") })
        assertTrue(paths.none { it.contains("contains(description,'ALEV')") })
        assertTrue(paths.all { it.endsWith("\$top=200") })

        val both = JSONObject().put("no", "A1").put("description", "KOVAN ALEV DELİĞİ BASKI ZIMBASI ( BB 9x19 )")
        val one = JSONObject().put("no", "A2").put("description", "KOVAN MARKALAMA BASKI ZIMBASI")
        val rows = mergeItemLookupRows(listOf(listOf(both, one)), search = "alev zımbası")
        assertEquals(listOf("A1"), rows.map { it.getString("no") })
    }

    @Test fun `search ignores case and dotless i when matching rows`() {
        val row = JSONObject().put("no", "( BB 9X19 )").put("description", "KOVAN ALEV DELİĞİ BASKI ZIMBASI")
        assertTrue(itemMatchesSearch(row, "zimba"))
        assertTrue(itemMatchesSearch(row, "Deliği kovan"))
        assertTrue(itemMatchesSearch(row, "bb 9x19"))
        assertTrue(!itemMatchesSearch(row, "luger"))
    }
}
