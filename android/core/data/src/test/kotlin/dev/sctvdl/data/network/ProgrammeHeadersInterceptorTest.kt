package dev.sctvdl.data.network

import dev.sctvdl.data.di.NetworkModule
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProgrammeHeadersInterceptorTest {
    @Test fun theSharedTransportDoesNotAddProgrammeIdentityToOtherServices() {
        val server = MockWebServer()
        server.start()
        val client = NetworkModule.client()
        try {
            server.enqueue(MockResponse().setBody("fixture"))

            client.newCall(Request.Builder().url(server.url("/cover.jpg")).build()).execute().use {
                assertEquals(200, it.code)
            }
            val recorded = requireNotNull(server.takeRequest(2, TimeUnit.SECONDS))

            assertNull(recorded.getHeader("deviceId"))
            assertNull(recorded.getHeader("Authorization"))
            assertNull(recorded.getHeader("appVersion"))
        } finally {
            client.dispatcher.cancelAll()
            client.connectionPool.evictAll()
            server.shutdown()
        }
    }

    @Test fun programmeRequestsUseTheOfficialGuestProfileAndKeepTheirDeviceIdentity() {
        val server = MockWebServer()
        server.start()
        val interceptor = ProgrammeHeadersInterceptor(
            deviceId = { "dd6694f8-a985-4dd5-8425-d7c6d811793d" },
            brand = "samsung",
            model = "SM-S9280",
            systemVersion = "14"
        )
        val client = OkHttpClient.Builder().addNetworkInterceptor(interceptor).build()
        try {
            for (path in listOf(
                "/app/v1/programs?page=0&size=100",
                "/app/v1/programs/1/dates/list",
                "/app/v1/programs/1/dates/2/contents/list"
            )) {
                server.enqueue(MockResponse().setBody("{}"))
                val request = Request.Builder().url(server.url(path))
                    .header("Authorization", "Bearer stale-token")
                    .header("userId", "stale-user")
                    .build()

                client.newCall(request).execute().use { assertEquals(200, it.code) }
                val recorded = requireNotNull(server.takeRequest(2, TimeUnit.SECONDS))

                assertEquals(path, recorded.path)
                assertEquals("GET", recorded.method)
                assertEquals(0L, recorded.bodySize)
                assertEquals("", recorded.getHeader("userId"))
                assertEquals("", recorded.getHeader("Authorization"))
                assertEquals("dd6694f8-a985-4dd5-8425-d7c6d811793d", recorded.getHeader("deviceId"))
                assertEquals("samsung", recorded.getHeader("deviceBrand"))
                assertEquals("SM-S9280", recorded.getHeader("deviceModel"))
                assertEquals("14", recorded.getHeader("systemVersion"))
                assertEquals("android", recorded.getHeader("deviceType"))
                assertEquals("9.6.1.5", recorded.getHeader("appVersion"))
                assertEquals("", recorded.getHeader("captchaId"))
                assertEquals("okhttp/4.12.0", recorded.getHeader("User-Agent"))
                assertEquals("gzip", recorded.getHeader("Accept-Encoding"))
                assertNull(recorded.getHeader("Cookie"))
                assertNull(recorded.getHeader("Referer"))
            }
        } finally {
            client.dispatcher.cancelAll()
            client.connectionPool.evictAll()
            server.shutdown()
        }
    }
}
