@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package dev.sctvdl.data.downloads.managed

import android.content.Context
import android.net.Uri
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.test.core.app.ApplicationProvider
import dev.sctvdl.data.di.DownloadFileConsentRegistry
import dev.sctvdl.data.downloads.platform.FileDeleteResult
import dev.sctvdl.data.downloads.platform.MediaStoreDownloadFiles
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.media.Quality
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okio.Buffer
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ManagedPublicationTest {
    @Test fun httpRangeContinuesAfterPauseAndRecreationThenPublishesExactBytes() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val directory = context.noBackupFilesDir.resolve("transfer-${UUID.randomUUID()}")
        val provider = StandaloneDatabaseProvider(context)
        val server = MockWebServer()
        val bytes = ByteArray(2 * 1024 * 1024) { (it % 251).toByte() }
        val offsets = java.util.concurrent.CopyOnWriteArrayList<Long>()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val start = request.getHeader("Range")?.substringAfter("bytes=")?.substringBefore('-')?.toLong() ?: 0
                offsets += start
                return MockResponse().setResponseCode(if (start == 0L) 200 else 206)
                    .setHeader("Content-Type", "video/mp4")
                    .setHeader("ETag", "\"fixture\"")
                    .setHeader("Accept-Ranges", "bytes")
                    .setHeader("Content-Range", "bytes $start-${bytes.lastIndex}/${bytes.size}")
                    .setBody(Buffer().write(bytes, start.toInt(), bytes.size - start.toInt()))
                    .throttleBody(32 * 1024, 30, TimeUnit.MILLISECONDS)
            }
        }
        server.start()
        val task = DownloadTask(
            "fixture", "1", "Fixture", "Programme", LocalDate.of(2026, 10, 17),
            Quality.Standard, Quality.Standard,
            server.url(
                "/media.mp4"
            ).toString(),
            "fixture-${UUID.randomUUID()}.mp4", false,
            createdAt = Instant.EPOCH,
            owner = DownloadOwner.Media3,
            cacheKey = directory.name,
            totalBytes = bytes.size.toLong()
        )
        val client = OkHttpClient()

        fun engine() = Media3TransferGateway(context, directory, provider, directory.name.replace("-", "")) {
            OkHttpDataSource.Factory(client)
        }
        var gateway = engine()
        var publicUri: String? = null
        try {
            gateway.enqueue(task)
            gateway.allow(task, true)
            withTimeout(15_000) { while (gateway.snapshots().none { it.bytes >= 128 * 1024 }) delay(50) }
            gateway.pause(task.attemptId)
            withTimeout(5_000) { while (gateway.snapshots().single().phase != ManagedTransferPhase.Paused) delay(25) }
            delay(200)
            val paused = gateway.snapshots().single().bytes
            assertTrue(paused < bytes.size)
            delay(150)
            assertEquals(paused, gateway.snapshots().single().bytes)
            gateway.shutdown()
            gateway = engine()
            gateway.enqueue(task.copy(userPaused = true))
            delay(150)
            val restoredBytes = gateway.snapshots().single().bytes
            assertTrue("Persisted spans may exclude the last in-memory buffer", restoredBytes in 1..paused)
            gateway.resume(task.attemptId)
            gateway.allow(task, true)
            withTimeout(20_000) {
                while (gateway.snapshots().none { it.phase == ManagedTransferPhase.Complete }) delay(50)
            }
            assertTrue("A resumed HTTP request must begin after zero", offsets.any { it > 0 })
            assertArrayEquals(bytes, gateway.openCached(task).use { it.readBytes() })

            val files = MediaStoreDownloadFiles(context, gateway, DownloadFileConsentRegistry())
            val uri = files.reserve(task)
            publicUri = uri
            assertFalse(files.isPublished(task, uri))
            assertEquals(listOf(uri), files.findPlanned(task))
            assertEquals(bytes.size.toLong(), files.copyCached(task, uri))
            files.finalize(uri)
            assertTrue(files.isPublished(task, uri))
            assertArrayEquals(bytes, context.contentResolver.openInputStream(Uri.parse(uri))!!.use { it.readBytes() })
            assertEquals(FileDeleteResult.Deleted, files.delete(uri))
            assertFalse(files.isReadable(uri))
            publicUri = null
            gateway.remove(task.attemptId)
        } finally {
            publicUri?.let { context.contentResolver.delete(Uri.parse(it), null, null) }
            gateway.shutdown()
            provider.close()
            server.shutdown()
            client.connectionPool.evictAll()
            client.dispatcher.executorService.shutdown()
            directory.deleteRecursively()
        }
    }
}
