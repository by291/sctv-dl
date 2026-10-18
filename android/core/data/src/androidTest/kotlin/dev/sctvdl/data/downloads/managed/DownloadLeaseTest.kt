package dev.sctvdl.data.downloads.managed

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.media.Quality
import java.time.Instant
import java.time.LocalDate
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadLeaseTest {
    @Test fun closingTheLastLeaseCancelsTheCallAfterResponseHeadersHaveArrived() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val access = DownloadNetworkAccess(context, OkHttpClient())
        val lease = access.acquire(ExecutionOwner.Foreground)
        val server = MockWebServer()
        server.enqueue(
            MockResponse().setHeader("Content-Type", "video/mp4")
                .setBody(Buffer().write(ByteArray(1024 * 1024))).throttleBody(1024, 30, TimeUnit.MILLISECONDS)
        )
        server.start()
        val task = DownloadTask(
            "lease", "1", "Fixture", "Programme", LocalDate.of(2026, 10, 17),
            Quality.Standard, Quality.Standard, "https://fscgc.scgchc.com/fixture.mp4", "fixture.mp4", false,
            createdAt = Instant.EPOCH
        )
        val client = access.client(task).newBuilder().addInterceptor { chain ->
            chain.proceed(chain.request().newBuilder().url(server.url("/fixture.mp4")).build())
        }.build()
        try {
            val call = client.newCall(Request.Builder().url(task.url).build())
            call.execute().use { response ->
                response.body.byteStream().read()
                lease.close()
                assertTrue("The streaming call must be canceled even after it leaves Dispatcher", call.isCanceled())
            }
        } finally {
            lease.close()
            server.shutdown()
        }
    }
}
