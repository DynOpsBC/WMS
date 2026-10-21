package com.dynops.bcwms.feature

import com.dynops.bcwms.DeviceAuth
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceSignInResumeTest {
    private class MemoryStore(var raw: String? = null) : PendingSignInStore {
        override fun read(): String? = raw
        override fun write(raw: String?) { this.raw = raw }
    }

    private var now = 1_000_000L
    private val code = DeviceAuth.DeviceCode(
        deviceCode = "DEVICE-CODE-123",
        userCode = "CLECSHQNV",
        verificationUri = "https://login.microsoft.com/device",
        interval = 5,
        expiresIn = 900,
        message = "",
        tenantSegment = "atesci.com",
    )

    @Test
    fun `only the EMU flavor gets the simple Microsoft sign-in`() {
        assertTrue(simpleMicrosoftSignIn("emu"))
        assertFalse(simpleMicrosoftSignIn("bade"))
        assertFalse(simpleMicrosoftSignIn("kitoko"))
        assertFalse(simpleMicrosoftSignIn("dynops"))
    }

    @Test
    fun `pending code survives process death and resumes with the same data`() {
        val store = MemoryStore()
        val saved = PendingDeviceSignInRepository(store) { now }.save(code, " deniz@atesci.com ")

        // New process: new repository over the same SharedPreferences content, 2 minutes later.
        now += 120_000L
        val resumed = PendingDeviceSignInRepository(store) { now }.resumable()

        assertEquals(saved, resumed)
        resumed!!
        assertEquals("DEVICE-CODE-123", resumed.deviceCode)
        assertEquals("CLECSHQNV", resumed.userCode)
        assertEquals("https://login.microsoft.com/device", resumed.verificationUri)
        assertEquals("atesci.com", resumed.tenantSegment)
        assertEquals("deniz@atesci.com", resumed.email)
        assertEquals(5_000L, resumed.pollIntervalMs())
        assertEquals(780_000L, resumed.remainingMs(now))

        // The resumed code polls the same tenant with the remaining lifetime.
        val polled = resumed.toDeviceCode(now)
        assertEquals("DEVICE-CODE-123", polled.deviceCode)
        assertEquals("atesci.com", polled.tenantSegment)
        assertEquals(780, polled.expiresIn)
    }

    @Test
    fun `expired code is not resumed and is removed`() {
        val store = MemoryStore()
        PendingDeviceSignInRepository(store) { now }.save(code, "deniz@atesci.com")

        now += 900_000L
        assertNull(PendingDeviceSignInRepository(store) { now }.resumable())
        assertNull(store.raw)
    }

    @Test
    fun `code about to expire counts as expired`() {
        val pending = PendingDeviceSignIn.from(code, "deniz@atesci.com", now)
        assertFalse(pending.isExpired(now + 889_000L))
        assertTrue(pending.isExpired(now + 891_000L))
    }

    @Test
    fun `corrupt or incomplete stored data is ignored and removed`() {
        val corrupt = MemoryStore("{not json")
        assertNull(PendingDeviceSignInRepository(corrupt) { now }.resumable())
        assertNull(corrupt.raw)

        val noDeviceCode = MemoryStore("""{"userCode":"ABC","expiresAtMs":9999999999}""")
        assertNull(PendingDeviceSignInRepository(noDeviceCode) { now }.resumable())
        assertNull(noDeviceCode.raw)

        assertNull(PendingDeviceSignInRepository(MemoryStore()) { now }.resumable())
    }

    @Test
    fun `cancel and success clear the pending code`() {
        val store = MemoryStore()
        val repo = PendingDeviceSignInRepository(store) { now }
        repo.save(code, "deniz@atesci.com")
        repo.clear()
        assertNull(store.raw)
        assertNull(repo.resumable())
    }

    @Test
    fun `a new code replaces the previous one`() {
        val store = MemoryStore()
        val repo = PendingDeviceSignInRepository(store) { now }
        repo.save(code, "deniz@atesci.com")
        repo.save(code.copy(deviceCode = "SECOND", userCode = "NEWCODE12"), "deniz@atesci.com")
        assertEquals("SECOND", repo.resumable()?.deviceCode)
        assertEquals("NEWCODE12", repo.resumable()?.userCode)
    }

    @Test
    fun `missing verification uri falls back to the Microsoft device login page`() {
        val pending = PendingDeviceSignIn.from(code.copy(verificationUri = "", tenantSegment = ""), "", now)
        assertEquals("https://microsoft.com/devicelogin", pending.verificationUri)
        assertEquals("organizations", pending.tenantSegment)
        assertEquals(pending, PendingDeviceSignIn.decode(pending.encode()))
    }

    @Test
    fun `network error keeps waiting instead of ending the sign-in`() {
        val pending = PendingDeviceSignIn.from(code, "deniz@atesci.com", now)
        val step = nextDevicePollStep(DeviceAuth.PollResult.Offline("Unable to resolve host"), 5_000L, pending, now + 30_000L)
        assertEquals(DevicePollStep.Wait(5_000L, offline = true), step)
    }

    @Test
    fun `pending approval waits and slow_down backs off`() {
        val pending = PendingDeviceSignIn.from(code, "deniz@atesci.com", now)
        assertEquals(
            DevicePollStep.Wait(5_000L, offline = false),
            nextDevicePollStep(DeviceAuth.PollResult.Waiting(), 5_000L, pending, now),
        )
        assertEquals(
            DevicePollStep.Wait(10_000L, offline = false),
            nextDevicePollStep(DeviceAuth.PollResult.Waiting(slowDown = true), 5_000L, pending, now),
        )
    }

    @Test
    fun `approval finishes, expiry and rejection stop`() {
        val pending = PendingDeviceSignIn.from(code, "deniz@atesci.com", now)
        val token = DeviceAuth.TokenResult.Success("access", "refresh", 3600)
        assertEquals(
            DevicePollStep.Done(token),
            nextDevicePollStep(DeviceAuth.PollResult.Success(token), 5_000L, pending, now),
        )
        // Approval that arrives right at the end still wins over the local clock.
        assertEquals(
            DevicePollStep.Done(token),
            nextDevicePollStep(DeviceAuth.PollResult.Success(token), 5_000L, pending, now + 899_000L),
        )
        val expired = nextDevicePollStep(DeviceAuth.PollResult.Failed("Kod süresi doldu", expired = true), 5_000L, pending, now)
        assertTrue(expired is DevicePollStep.Stop && expired.expired)
        val declined = nextDevicePollStep(DeviceAuth.PollResult.Failed("Giriş reddedildi."), 5_000L, pending, now)
        assertEquals(DevicePollStep.Stop("Giriş reddedildi.", expired = false), declined)
        val locallyExpired = nextDevicePollStep(DeviceAuth.PollResult.Waiting(), 5_000L, pending, now + 900_000L)
        assertTrue(locallyExpired is DevicePollStep.Stop && locallyExpired.expired)
    }

    @Test
    fun `remaining time is shown as minutes and seconds`() {
        assertEquals("15:00", formatRemaining(900_000L))
        assertEquals("0:05", formatRemaining(5_400L))
        assertEquals("0:00", formatRemaining(-1L))
    }
}
