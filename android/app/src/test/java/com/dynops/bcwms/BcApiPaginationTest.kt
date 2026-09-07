package com.dynops.bcwms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test
import kotlinx.coroutines.runBlocking

class BcApiPaginationTest {
    @Test
    fun `every page is required before a document can be declared complete`() = runBlocking {
        val visited = mutableListOf<String>()
        val result = BcApi.collectODataPages("first") { path ->
            visited += path
            if (path == "first") BcApi.ApiResult(true, 200, """{"value":[{"lineNo":1}],"@odata.nextLink":"second"}""")
            else BcApi.ApiResult(true, 200, """{"value":[{"lineNo":2}],"@odata.nextLink":null}""")
        }
        assertEquals(listOf("first", "second"), visited)
        assertEquals(true, result.complete)
        assertEquals(2, result.rows.size)
    }

    @Test
    fun `partial data after a failed page never enables posting`() = runBlocking {
        val result = BcApi.collectODataPages("first") { path ->
            if (path == "first") BcApi.ApiResult(true, 200, """{"value":[{"lineNo":1}],"@odata.nextLink":"second"}""")
            else BcApi.ApiResult(false, 503, "offline")
        }
        assertEquals(false, result.complete)
        assertEquals(1, result.rows.size)
        assertEquals(503, result.error?.httpCode)
    }

    @Test
    fun `cyclic malformed and truncated pages fail closed`() = runBlocking {
        for (body in listOf("""{"value":[],"@odata.nextLink":"first"}""",
            """{"value":[],"@odata.nextLink":123}""", """{"value":[null]}""", """{"unexpected":[]}""")) {
            val result = BcApi.collectODataPages("first", maxPages = 3) { BcApi.ApiResult(true, 200, body) }
            assertEquals(body, false, result.complete)
        }
    }

    @Test
    fun `page limit cannot mark a partially read document complete`() = runBlocking {
        val result = BcApi.collectODataPages("first", maxPages = 1) {
            BcApi.ApiResult(true, 200, """{"value":[],"@odata.nextLink":"second"}""")
        }
        assertEquals(false, result.complete)
    }

    @Test
    fun `odata next link is returned exactly for the following page`() {
        val url = "https://api.example.test/lines?%24skiptoken=abc"
        assertEquals(url, BcApi.odataNextLink("""{"value":[],"@odata.nextLink":"$url"}"""))
    }

    @Test
    fun `last page and malformed response have no next link`() {
        assertNull(BcApi.odataNextLink("""{"value":[]}"""))
        assertNull(BcApi.odataNextLink("not-json"))
    }

    @Test
    fun `connection probe accepts local user endpoint without depending on LP data`() {
        val localUsers = BcApi.ApiResult(true, 200, "{}")
        val licensePlates = BcApi.ApiResult(false, 500, "LP data error")

        assertSame(localUsers, BcApi.selectConnectionProbeResult(localUsers, licensePlates))
    }

    @Test
    fun `connection probe accepts legacy LP endpoint when local user endpoint is absent`() {
        val localUsers = BcApi.ApiResult(false, 404, "missing")
        val licensePlates = BcApi.ApiResult(true, 200, "{}")

        assertSame(licensePlates, BcApi.selectConnectionProbeResult(localUsers, licensePlates))
    }

    @Test
    fun `connection failure explains missing BC package`() {
        val result = BcApi.ApiResult(false, 404, "missing")

        assertEquals(
            "WMS BC paketi bu ortamda erişilebilir değil. Doğru ortama güncel paketi yükleyin.",
            BcApi.connectionFailureMessage(result),
        )
    }

    @Test
    fun `connection retries temporary route and server failures`() {
        listOf(-1, 404, 408, 425, 429, 500, 503).forEach { code ->
            assertEquals(true, BcApi.isRetryableConnectionFailure(BcApi.ApiResult(false, code, "")))
        }
    }

    @Test
    fun `connection does not retry authentication and permission failures`() {
        listOf(400, 401, 403, 405).forEach { code ->
            assertEquals(false, BcApi.isRetryableConnectionFailure(BcApi.ApiResult(false, code, "")))
        }
    }

    @Test
    fun `mutation validation errors are definite but transport failures are ambiguous`() {
        listOf(-1, 301, 307, 308, 408, 425, 429, 500, 503).forEach { code ->
            assertEquals(true, BcApi.isAmbiguousMutationFailure(BcApi.ApiResult(false, code, "")))
        }
        listOf(400, 401, 403, 404, 405, 409, 422).forEach { code ->
            assertEquals(false, BcApi.isAmbiguousMutationFailure(BcApi.ApiResult(false, code, "")))
        }
    }
}
