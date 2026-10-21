package com.dynops.bcwms

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.ServerSocket

class DeviceAuthPollTest {
    private val originalHost = DeviceAuth.loginHost
    private val code = DeviceAuth.DeviceCode(
        deviceCode = "DEVICE-CODE",
        userCode = "ABCDEFGHI",
        verificationUri = "https://login.microsoft.com/device",
        interval = 1,
        expiresIn = 60,
        message = "",
        tenantSegment = "atesci.com",
    )

    @After
    fun restoreHost() {
        DeviceAuth.loginHost = originalHost
    }

    @Test
    fun `token endpoint answers are mapped`() {
        assertEquals(
            DeviceAuth.PollResult.Waiting(),
            DeviceAuth.interpretTokenResponse(400, """{"error":"authorization_pending"}"""),
        )
        assertEquals(
            DeviceAuth.PollResult.Waiting(slowDown = true),
            DeviceAuth.interpretTokenResponse(400, """{"error":"slow_down"}"""),
        )
        val expired = DeviceAuth.interpretTokenResponse(400, """{"error":"expired_token"}""")
        assertTrue(expired is DeviceAuth.PollResult.Failed && expired.expired)
        assertEquals(
            DeviceAuth.PollResult.Failed("Giriş reddedildi."),
            DeviceAuth.interpretTokenResponse(400, """{"error":"authorization_declined"}"""),
        )
        assertEquals(
            DeviceAuth.PollResult.Failed("AADSTS53003: Access has been blocked by Conditional Access policies."),
            DeviceAuth.interpretTokenResponse(
                400,
                """{"error":"invalid_grant","error_description":"AADSTS53003: Access has been blocked by Conditional Access policies.\r\nTrace ID: 1"}""",
            ),
        )
        assertEquals(
            DeviceAuth.PollResult.Success(DeviceAuth.TokenResult.Success("at", "rt", 4000)),
            DeviceAuth.interpretTokenResponse(200, """{"access_token":"at","refresh_token":"rt","expires_in":4000}"""),
        )
        // A proxy/gateway page is not an answer from Entra: keep polling.
        assertEquals(DeviceAuth.PollResult.Waiting(), DeviceAuth.interpretTokenResponse(503, "<html>busy</html>"))
    }

    @Test
    fun `poll without network returns Offline instead of throwing`() {
        // Regression: UnknownHostException from a background poll closed the app.
        val freePort = ServerSocket(0).use { it.localPort }
        DeviceAuth.loginHost = "http://127.0.0.1:$freePort"
        val result = runBlocking { DeviceAuth.pollOnce(code) }
        assertTrue(result is DeviceAuth.PollResult.Offline)
    }

    @Test
    fun `poll loop survives a dropped connection and returns the token`() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START))
            server.enqueue(MockResponse().setResponseCode(400).setBody("""{"error":"authorization_pending"}"""))
            server.enqueue(MockResponse().setBody("""{"access_token":"token-1","refresh_token":"refresh-1","expires_in":3600}"""))
            DeviceAuth.loginHost = server.url("").toString().trimEnd('/')

            val result = runBlocking { DeviceAuth.pollForToken(code) }

            assertEquals(DeviceAuth.TokenResult.Success("token-1", "refresh-1", 3600), result)
            val paths = (1..server.requestCount).mapNotNull {
                server.takeRequest(1, java.util.concurrent.TimeUnit.SECONDS)?.path
            }
            assertTrue(paths.isNotEmpty())
            assertTrue(paths.all { it == "/atesci.com/oauth2/v2.0/token" })
        }
    }
}
