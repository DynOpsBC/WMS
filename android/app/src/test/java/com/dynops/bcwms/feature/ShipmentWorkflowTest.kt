package com.dynops.bcwms.feature

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShipmentWorkflowTest {

    // ---- pickLpChoiceNeeded ----

    @Test
    fun `no options means the server decides without asking`() {
        assertFalse(pickLpChoiceNeeded(0))
    }

    @Test
    fun `a single candidate pallet needs no dialog`() {
        assertFalse(pickLpChoiceNeeded(1))
    }

    @Test
    fun `two or more candidate pallets are an operator choice`() {
        assertTrue(pickLpChoiceNeeded(2))
        assertTrue(pickLpChoiceNeeded(7))
    }

    @Test
    fun `several partial pallets require a combined pick`() {
        val partials = parsePickSourceOptions(
            """[{"lpNo":"LP1","coversFullDemand":false},{"lpNo":"LP2","coversFullDemand":false}]"""
        )
        val oneFull = partials + partials.first().copy(lpNo = "LP3", coversFullDemand = true)

        assertTrue(combinedLpPickRequired(partials))
        assertFalse(combinedLpPickRequired(oneFull))
        assertFalse(combinedLpPickRequired(partials.take(1)))
    }

    // ---- shouldFallbackToLegacyCreatePick ----

    @Test
    fun `missing action on an older BC package falls back silently`() {
        assertTrue(shouldFallbackToLegacyCreatePick(404, ""))
        assertTrue(shouldFallbackToLegacyCreatePick(405, ""))
        assertTrue(shouldFallbackToLegacyCreatePick(501, ""))
        assertTrue(
            shouldFallbackToLegacyCreatePick(
                400,
                """{"error":{"message":"Could not find a property named 'createPickFromLp'."}}""",
            )
        )
        assertTrue(
            shouldFallbackToLegacyCreatePick(400, "No HTTP resource was found that matches the request URI.")
        )
    }

    @Test
    fun `real business errors are never masked as an older server`() {
        assertFalse(shouldFallbackToLegacyCreatePick(400, "LP000023 üzerinde yeterli stok yok."))
        assertFalse(shouldFallbackToLegacyCreatePick(403, "Forbidden"))
        assertFalse(shouldFallbackToLegacyCreatePick(409, "The record is locked by another user."))
        assertFalse(shouldFallbackToLegacyCreatePick(500, "Internal server error"))
    }

    // ---- parsePickSourceOptions ----

    private val sample = """
        [
          {"lpNo":"LP000023","binCode":"A-01-01","itemNo":"ITEM-1","itemDescription":"Bade Kraft 90g",
           "lotNo":"L2026-07","availableQtyBase":1200.0,"uom":"KG","coversFullDemand":true},
          {"lpNo":"LP000024","binCode":"A-01-02","itemNo":"ITEM-1","itemDescription":"Bade Kraft 90g",
           "lotNo":"L2026-08","availableQtyBase":880.0,"uom":"KG","coversFullDemand":false}
        ]
    """.trimIndent()

    @Test
    fun `parses the server array into options in order`() {
        val opts = parsePickSourceOptions(sample)

        assertEquals(2, opts.size)
        val first = opts[0]
        assertEquals("LP000023", first.lpNo)
        assertEquals("A-01-01", first.binCode)
        assertEquals("ITEM-1", first.itemNo)
        assertEquals("Bade Kraft 90g", first.itemDescription)
        assertEquals("L2026-07", first.lotNo)
        assertEquals(1200.0, first.availableQtyBase, 0.001)
        assertEquals("KG", first.uom)
        assertTrue(first.coversFullDemand)
        assertEquals("LP000024", opts[1].lpNo)
        assertFalse(opts[1].coversFullDemand)
    }

    @Test
    fun `source pallets are sorted by natural warehouse bin order then lp number`() {
        val opts = parsePickSourceOptions(
            """
            [
              {"lpNo":"LP20","binCode":"A-10"},
              {"lpNo":"LP02","binCode":"A-2"},
              {"lpNo":"LP01","binCode":"A-2"},
              {"lpNo":"LP99","binCode":""}
            ]
            """.trimIndent()
        )

        assertEquals(listOf("LP01", "LP02", "LP20", "LP99"), opts.map { it.lpNo })
    }

    @Test
    fun `an options payload wrapped in value is still read`() {
        val opts = parsePickSourceOptions("""{"value":$sample}""")

        assertEquals(listOf("LP000023", "LP000024"), opts.map { it.lpNo })
    }

    @Test
    fun `blank malformed or empty payloads yield no options so the system decides`() {
        assertTrue(parsePickSourceOptions("").isEmpty())
        assertTrue(parsePickSourceOptions("   ").isEmpty())
        assertTrue(parsePickSourceOptions("[]").isEmpty())
        assertTrue(parsePickSourceOptions("not json at all").isEmpty())
        assertTrue(parsePickSourceOptions("""{"error":{"message":"x"}}""").isEmpty())
    }

    @Test
    fun `entries without an LP number are dropped`() {
        val opts = parsePickSourceOptions(
            """[{"lpNo":"","binCode":"A-01-01"},{"lpNo":"  ","binCode":"B"},{"lpNo":"LP000025"}]"""
        )

        assertEquals(listOf("LP000025"), opts.map { it.lpNo })
    }

    @Test
    fun `missing optional fields default without throwing`() {
        val opts = parsePickSourceOptions("""[{"lpNo":"LP000030"}]""")

        assertEquals(1, opts.size)
        val o = opts[0]
        assertEquals("", o.binCode)
        assertEquals("", o.lotNo)
        assertEquals("", o.uom)
        assertEquals(0.0, o.availableQtyBase, 0.001)
        assertFalse(o.coversFullDemand)
    }

    // ---- formatting ----

    @Test
    fun `whole quantities lose a pointless decimal tail`() {
        assertEquals("1200", formatPickQty(1200.0))
        assertEquals("880", formatPickQty(880.0))
        assertEquals("0", formatPickQty(0.0))
    }

    /**
     * Ondalık ayraç cihazın diline göre değişir (TR terminalde virgül); sabit bir
     * karakter beklemek yerine gereksiz sıfırların atıldığı doğrulanır.
     */
    @Test
    fun `fractional quantities keep one meaningful decimal in any locale`() {
        assertEquals("12" + java.text.DecimalFormatSymbols.getInstance().decimalSeparator + "5", formatPickQty(12.5))
    }

    @Test
    fun `subtitle shows bin lot quantity and item`() {
        val subtitle = pickSourceSubtitle(parsePickSourceOptions(sample)[0])

        assertEquals("Raf: A-01-01 · Lot: L2026-07 · Mevcut: 1200 KG · ITEM-1 — Bade Kraft 90g", subtitle)
    }

    @Test
    fun `subtitle skips empty fields without leaving dangling separators`() {
        val subtitle = pickSourceSubtitle(parsePickSourceOptions("""[{"lpNo":"LP000030","availableQtyBase":40}]""")[0])

        assertEquals("Mevcut: 40", subtitle)
        assertFalse(subtitle.contains("··"))
        assertFalse(subtitle.trim().endsWith("·"))
    }
}
