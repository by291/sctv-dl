package dev.sctvdl.data.downloads.preflight

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OkHttpMediaProbeTest {
    @Test fun headAndRangeUseMediaHeadersWithoutMetadataIdentity() = runTest {
        val server = MockWebServer()
        server.start()
        val client = OkHttpClient()
        try {
            val probe = OkHttpMediaProbe(client)
            for ((method, range) in listOf("HEAD" to null, "GET" to "bytes=0-0")) {
                server.enqueue(MockResponse().setHeader("Content-Type", "video/mp4"))

                val response = probe.request(server.url("/clip.mp4").toString(), method, range)
                val request = requireNotNull(server.takeRequest(2, TimeUnit.SECONDS))

                assertEquals(200, response.status)
                assertEquals(method, request.method)
                assertEquals(range, request.getHeader("Range"))
                assertEquals("https://scgc.video.play/", request.getHeader("Referer"))
                assertEquals("okhttp/4.12.0", request.getHeader("User-Agent"))
                assertNull(request.getHeader("deviceId"))
                assertNull(request.getHeader("appVersion"))
                assertNull(request.getHeader("Authorization"))
            }
        } finally {
            client.dispatcher.cancelAll()
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
            server.shutdown()
        }
    }
}
