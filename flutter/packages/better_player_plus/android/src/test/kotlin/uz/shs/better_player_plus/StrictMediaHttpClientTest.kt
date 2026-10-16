package uz.shs.better_player_plus

import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test

class StrictMediaHttpClientTest {
    @Test
    fun rejectsRedirectWithoutContactingDestination() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(302).addHeader("Location", "/target"))
            StrictMediaHttpClient.create().newCall(Request.Builder().url(server.url("/source")).build()).execute().use {
                assertEquals(302, it.code)
            }
            assertEquals(1, server.requestCount)
        }
    }

    @Test
    fun streamsRangeAndClosesWithoutBufferingWholeResponse() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(206).setBody("x".repeat(1024 * 1024)))
            val request = Request.Builder().url(server.url("/source")).header("Range", "bytes=0-1023").build()
            StrictMediaHttpClient.create().newCall(request).execute().use {
                assertEquals(1024, it.body!!.source().readByteArray(1024).size)
            }
            assertEquals("bytes=0-1023", server.takeRequest().getHeader("Range"))
        }
    }
}
