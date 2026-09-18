package com.dynops.bcwms.feature

import org.junit.Assert.assertTrue
import org.junit.Test

class ItemLookupTest {
    @Test fun `lookup searches partial item number and description`() {
        val path = itemLookupPath("100")
        assertTrue(path.contains("contains(no,'100')"))
        assertTrue(path.contains("contains(description,'100')"))
        assertTrue(path.endsWith("\$top=12"))
    }

    @Test fun `lookup escapes OData quotes`() {
        assertTrue(itemLookupPath("A'1").contains("A''1"))
    }
}
