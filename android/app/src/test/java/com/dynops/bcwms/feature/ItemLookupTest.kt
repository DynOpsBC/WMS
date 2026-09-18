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
        assertTrue(itemLookupPaths("A'1").all { it.contains("A''1") })
    }

    @Test fun `lookup merges number and description matches without duplicates`() {
        val first = JSONObject().put("no", "STR 26").put("description", "KOVAN")
        val duplicate = JSONObject().put("no", "str 26").put("description", "KOVAN 9X19")
        val second = JSONObject().put("no", "9MM KOVAN").put("description", "STR-26")

        val rows = mergeItemLookupRows(listOf(listOf(first), listOf(duplicate, second)))

        assertEquals(listOf("9MM KOVAN", "STR 26"), rows.map { it.getString("no") })
    }
}
