package com.dynops.bcwms

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Yeni APK, yayındaki BC paketinde bulunmayan bir action'ı asla çağırmamalıdır.
 * Yetenekler OData $metadata üzerinden okunur; eksikse ilgili ekran bu paketten
 * önceki akışa döner.
 */
class LpScanCapabilitiesTest {
    @Test fun productionPreparationRequiresAllThreeExactActions() {
        val actions = listOf("prepareProductionLPFor", "deliverProductionLPFor", "startProductionLPFor")
        val metadata = actions.joinToString("") { "<edm:Action Name='$it'/>" }
        assertTrue(BcApi.parseLpScanCapabilities(metadata).productionLpPreparation)
        actions.forEach { omitted ->
            assertFalse(BcApi.parseLpScanCapabilities(metadata.replace("<edm:Action Name='$omitted'/>", "")).productionLpPreparation)
        }
        assertFalse(BcApi.parseLpScanCapabilities(metadata.replace("Action", "Property")).productionLpPreparation)
        assertFalse(BcApi.parseLpScanCapabilities(metadata.replace("LPFor", "LPForPreview")).productionLpPreparation)
    }

    @Test
    fun `multi entry single LP action is detected exactly from metadata`() {
        assertTrue(
            BcApi.parseLpScanCapabilities(
                """<Action Name="createSingleLicensePlateFromEntriesIdempotent" IsBound="true"/>""",
            ).multiEntrySingleLp,
        )
        assertFalse(
            BcApi.parseLpScanCapabilities(
                """<Action Name="createLicensePlatesIdempotent" IsBound="true"/>""",
            ).multiEntrySingleLp,
        )
    }


    @Test fun `production registration never downgrades from scanned LP action`() {
        val legacy = BcApi.parseLpScanCapabilities("""<Action Name="registerFor"/>""")
        val previousScanned = BcApi.parseLpScanCapabilities("""<Action Name="registerScannedFor"/>""")
        val current = BcApi.parseLpScanCapabilities("""<Action Name="registerProductionPalletsFor"/>""")
        org.junit.Assert.assertNull(BcApi.pickRegistrationAction(legacy, requireIntactProductionLp = true))
        org.junit.Assert.assertNull(BcApi.pickRegistrationAction(previousScanned, requireIntactProductionLp = true))
        org.junit.Assert.assertEquals("registerProductionPalletsFor", BcApi.pickRegistrationAction(current, requireIntactProductionLp = true))
        org.junit.Assert.assertNull(BcApi.pickRegistrationAction(current.copy(metadataLoaded = false), requireIntactProductionLp = true))
        org.junit.Assert.assertEquals("registerFor", BcApi.pickRegistrationAction(legacy))
    }

    @Test fun `production support requires exact action not old scanned protocol or a property`() {
        assertTrue(BcApi.parseLpScanCapabilities("""<edm:Action Name='registerProductionPalletsFor'/>""").registerProductionPallets)
        listOf(
            """<Action Name="registerScannedFor"/>""",
            """<Action Name="registerProductionPalletsForPreview"/>""",
            """<Property Name="registerProductionPalletsFor"/>""",
        ).forEach { metadata ->
            val caps = BcApi.parseLpScanCapabilities(metadata)
            assertFalse(caps.registerProductionPallets)
            org.junit.Assert.assertNull(BcApi.pickRegistrationAction(caps, requireIntactProductionLp = true))
        }
    }

    @org.junit.Test fun metadataFailureNeverDowngradesToLegacyPosting() {
        val old = BcApi.parseLpScanCapabilities("""<Action Name="registerFor"/>""")
        val current = BcApi.parseLpScanCapabilities("""<Action Name="registerScannedFor"/>""")
        org.junit.Assert.assertEquals("registerFor", BcApi.pickRegistrationAction(old))
        org.junit.Assert.assertEquals("registerScannedFor", BcApi.pickRegistrationAction(current))
        org.junit.Assert.assertNull(BcApi.pickRegistrationAction(current.copy(metadataLoaded = false, httpCode = 503)))
        org.junit.Assert.assertNull(BcApi.pickRegistrationAction(old.copy(metadataLoaded = false, httpCode = 401)))
    }
    @org.junit.Test fun exactRegistrationRequiresTheActualAction() {
        org.junit.Assert.assertTrue(BcApi.parseLpScanCapabilities("""<Action Name="registerScannedFor" IsBound="true"/>""").registerScannedPick)
        org.junit.Assert.assertTrue(BcApi.parseLpScanCapabilities("""<edm:Action Name='registerScannedFor'/>""").registerScannedPick)
        org.junit.Assert.assertFalse(BcApi.parseLpScanCapabilities("""<Action Name="registerScannedForPreview"/>""").registerScannedPick)
        org.junit.Assert.assertFalse(BcApi.parseLpScanCapabilities("""<Property Name="registerScannedFor"/>""").registerScannedPick)
        org.junit.Assert.assertFalse(BcApi.parseLpScanCapabilities("""<Action Name="registerFor"/>""").registerScannedPick)
    }

    private val currentMetadata = """
        <Action Name="pickLineSources" />
        <Action Name="setPlacementFromLp" />
        <Action Name="createLicensePlatesFromPlanIdempotent" />
    """.trimIndent()

    private val previousPackageMetadata = """
        <Action Name="confirmLine" />
        <Action Name="setPlacement" />
        <Action Name="createLicensePlatesIdempotent" />
    """.trimIndent()

    @Test
    fun `current package exposes every lp scan action`() {
        val caps = BcApi.parseLpScanCapabilities(currentMetadata)
        assertTrue(caps.metadataLoaded)
        assertTrue(caps.pickLineSources)
        assertTrue(caps.putAwayPlacementFromLp)
        assertTrue(caps.bulkLpPlan)
    }

    @Test
    fun `previous package exposes none of them`() {
        val caps = BcApi.parseLpScanCapabilities(previousPackageMetadata)
        assertTrue(caps.metadataLoaded)
        assertFalse(caps.pickLineSources)
        assertFalse(caps.putAwayPlacementFromLp)
        assertFalse(caps.bulkLpPlan)
    }

    @Test
    fun `the legacy placement action alone must not look like the verified one`() {
        // "setPlacement" alt dize olarak "setPlacementFromLp" içinde geçmez;
        // ters yönde bir yanlış eşleşme yeni akışı eski sunucuda açardı.
        val caps = BcApi.parseLpScanCapabilities("""<Action Name="setPlacement" />""")
        assertFalse(caps.putAwayPlacementFromLp)
    }

    @Test
    fun `partially upgraded metadata enables only what exists`() {
        val caps = BcApi.parseLpScanCapabilities("""<Action Name="pickLineSources" />""")
        assertTrue(caps.pickLineSources)
        assertFalse(caps.putAwayPlacementFromLp)
        assertFalse(caps.bulkLpPlan)
    }
}
