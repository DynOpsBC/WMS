package com.dynops.bcwms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProductionAccessTest {
    @Test fun `Kitoko discovers Production while retaining its sandbox default`() {
        assertTrue(BuildConfig.BC_ALLOW_PRODUCTION)
        assertTrue("Production" in BcApi.KNOWN_ENVIRONMENTS)
        // Kitoko (20 Eki 2026): varsayılan ortam Sand2010 oldu (build.gradle.kts).
        assertEquals("Sand2010", BcApi.DEFAULT_ENVIRONMENT)
    }

    private val restricted = setOf(
        Screen.Shipping, Screen.Packing, Screen.Picking, Screen.Production,
    )

    @Test fun `receiving and put-away are open to every production operator`() {
        for (screen in listOf(Screen.Receiving, Screen.PutAway)) {
            assertTrue("$screen", productionScreenAllowed(screen, "Production", manager = false))
        }
    }

    @Test fun `label screen is open to every production operator`() {
        // Kitoko (19 Eki 2026): Etiket Çıkar stok değiştirmez; yönetici kapısı yok.
        assertTrue(productionScreenAllowed(Screen.Labels, "Production", manager = false))
    }

    @Test fun `production operators can access only operations already rolled out`() {
        for (environment in listOf("Production", "production", " PRODUCTION ")) {
            for (screen in Screen.entries) {
                assertEquals("$environment $screen", screen !in restricted,
                    productionScreenAllowed(screen, environment, manager = false))
            }
        }
    }

    @Test fun `production managers retain access to every screen`() {
        for (screen in Screen.entries) {
            assertTrue(productionScreenAllowed(screen, "Production", manager = true))
        }
    }

    @Test fun `sandbox access stays unchanged for operators and managers`() {
        for (environment in listOf("Sandbox", "E-DefterSandbox", "Sandbox3007")) {
            for (screen in Screen.entries) {
                for (manager in listOf(false, true)) {
                    assertTrue(productionScreenAllowed(screen, environment, manager))
                }
            }
        }
    }

    @Test fun `only an explicit terminal admin profile grants manager access`() {
        assertTrue(isTerminalManager("""{"terminalAdmin":true}"""))
        for (profile in listOf("", "invalid", "{}", """{"terminalAdmin":false}""",
            """{"displayName":"Yönetici"}""")) {
            assertFalse(isTerminalManager(profile))
        }
    }
}
