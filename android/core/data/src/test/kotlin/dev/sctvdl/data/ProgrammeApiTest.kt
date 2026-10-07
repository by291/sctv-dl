package dev.sctvdl.data

import dev.sctvdl.data.network.ProgrammeApi
import dev.sctvdl.data.network.RetrofitProgrammeSource
import dev.sctvdl.domain.AppException
import dev.sctvdl.domain.ErrorKind
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import retrofit2.HttpException
import retrofit2.Retrofit

class ProgrammeApiTest {
    @Test fun oversizedMetadataIsRejectedBeforeReadingTheDelayedTail() = runTest {
        val server = MockWebServer()
        server.start()
        val client = OkHttpClient.Builder().readTimeout(500, TimeUnit.MILLISECONDS).build()
        try {
            val limit = 2 * 1024 * 1024
            repeat(3) {
                server.enqueue(
                    MockResponse().setBody("x".repeat(limit + 1024))
                        .throttleBody(limit + 1L, 2, TimeUnit.SECONDS)
                )
            }
            val api = Retrofit.Builder().baseUrl(server.url("/")).client(client).build()
                .create(ProgrammeApi::class.java)
            val source = RetrofitProgrammeSource(api)
            for (fetch in listOf<suspend () -> String>(
                source::programmes,
                { source.dates("1") },
                { source.contents("1", "2") }
            )) {
                val failure = runCatching { fetch() }.exceptionOrNull()
                assertTrue("Expected bounded invalid-data rejection, got $failure", failure is AppException)
                assertEquals(ErrorKind.InvalidData, (failure as AppException).error.kind)
            }
        } finally {
            client.dispatcher.cancelAll()
            client.connectionPool.evictAll()
            server.shutdown()
        }
    }

    @Test fun endpointsUseRecordIdsAndFixedCataloguePagination() = runTest {
        val server = MockWebServer()
        server.start()
        try {
            repeat(3) { server.enqueue(MockResponse().setBody("{\"rs\":200,\"data\":[]}")) }
            val api = Retrofit.Builder().baseUrl(
                server.url("/")
            ).client(
                OkHttpClient.Builder().followRedirects(false).build()
            ).build().create(ProgrammeApi::class.java)
            val source = RetrofitProgrammeSource(api)
            source.programmes()
            source.dates("2107420533961056258")
            source.contents("1", "2107420533961056258")
            assertEquals("/app/v1/programs?page=0&size=100", server.takeRequest().path)
            assertEquals(
                "/app/v1/programs/2107420533961056258/dates/list",
                server.takeRequest().path
            )
            assertEquals(
                "/app/v1/programs/1/dates/2107420533961056258/contents/list",
                server.takeRequest().path
            )
        } finally {
            server.shutdown()
        }
    }

    @Test fun applicationControlledMetadataRequestsRejectRedirects() = runTest {
        val server = MockWebServer()
        server.start()
        try {
            server.enqueue(MockResponse().setResponseCode(302).addHeader("Location", "/other"))
            val api = Retrofit.Builder().baseUrl(
                server.url("/")
            ).client(
                OkHttpClient.Builder().followRedirects(false).build()
            ).build().create(ProgrammeApi::class.java)
            var status: Int? = null
            try {
                RetrofitProgrammeSource(api).programmes()
            } catch (
                error: HttpException
            ) {
                status =
                    error.code()
            }
            assertEquals(302, status)
            assertEquals(1, server.requestCount)
        } finally {
            server.shutdown()
        }
    }
}
