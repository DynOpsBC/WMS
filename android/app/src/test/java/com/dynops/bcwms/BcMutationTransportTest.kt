package com.dynops.bcwms

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.TimeUnit

class BcMutationTransportTest {
    private fun client() = BcApi.withoutAutomaticMutationReplay(OkHttpClient.Builder()
        .readTimeout(2, TimeUnit.SECONDS).callTimeout(3, TimeUnit.SECONDS).build())

    @Test
    fun `post is not silently repeated when 503 requests immediate retry`() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(503).setHeader("Retry-After", "0"))
            server.enqueue(MockResponse().setResponseCode(200).setBody("duplicate would be written"))
            val client = client()
            try {
                val request = Request.Builder().url(server.url("/post"))
                    .post(BcApi.mutationRequestBody("{}".toRequestBody())).build()
                client.newCall(request).execute().use { assertEquals(503, it.code) }
                assertEquals(1, server.requestCount)
            } finally { client.connectionPool.evictAll(); client.dispatcher.executorService.shutdown() }
        }
    }

    @Test
    fun `lost response after server reads post does not write a second time`() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST))
            server.enqueue(MockResponse().setBody("duplicate"))
            val client = client()
            try {
                val request = Request.Builder().url(server.url("/createLP"))
                    .post(BcApi.mutationRequestBody("{}".toRequestBody())).build()
                assertTrue(runCatching { client.newCall(request).execute().close() }.isFailure)
                assertEquals(1, server.requestCount)
            } finally { client.connectionPool.evictAll(); client.dispatcher.executorService.shutdown() }
        }
    }

    @Test
    fun `mutation redirects cannot move a write to another endpoint`() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(307).setHeader("Location", server.url("/other")))
            server.enqueue(MockResponse().setBody("unexpected write"))
            val client = client()
            try {
                val request = Request.Builder().url(server.url("/post"))
                    .post(BcApi.mutationRequestBody("{}".toRequestBody())).build()
                client.newCall(request).execute().use { assertEquals(307, it.code) }
                assertEquals(1, server.requestCount)
            } finally { client.connectionPool.evictAll(); client.dispatcher.executorService.shutdown() }
        }
    }

    @Test
    fun `BC authentication cannot be forwarded to arbitrary page links`() {
        val base = "https://api.businesscentral.dynamics.com/v2.0/tenant/env/api/companies('company')"
        for (path in listOf("https://evil.example/next", "http://api.businesscentral.dynamics.com/next",
            "https://api.businesscentral.dynamics.com.evil.example/next", "https://user@api.businesscentral.dynamics.com/next")) {
            assertTrue(path, runCatching { BcApi.authenticatedBcUrl(base, path) }.isFailure)
        }
        assertTrue(BcApi.authenticatedBcUrl(base, "countSheets('CNT 1')").contains("CNT%201"))
    }
}
