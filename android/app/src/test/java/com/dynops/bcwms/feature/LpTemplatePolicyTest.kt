package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LpTemplatePolicyTest {
    private fun row(code: String, description: String = "") = code to description

    @Test
    fun `purpose selects explicit company template without hardcoded code`() {
        val rows = listOf(row("A01", "Euro Palet"), row("B02", "Kargo Kolisi"))
        assertEquals("A01", chooseLpTemplate(rows, LpPurpose.PALLET))
        assertEquals("B02", chooseLpTemplate(rows, LpPurpose.CARTON))
    }

    @Test
    fun `ambiguous templates fail closed`() {
        assertNull(chooseLpTemplate(listOf(row("ONE"), row("TWO")), LpPurpose.PALLET))
    }

    @Test
    fun `single template is safe default`() {
        assertEquals("ONLY", chooseLpTemplate(listOf(row("ONLY")), LpPurpose.CARTON))
    }
}
