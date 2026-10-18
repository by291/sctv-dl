@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package dev.sctvdl.data.downloads.managed

import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.ByteArrayDataSource
import androidx.media3.datasource.DataSource
import androidx.test.core.app.ApplicationProvider
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.media.Quality
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class ManagedTransferTest {
    @Test fun restoredQueueAndInterruptedRemovalDoNotNeedAnInMemoryTaskContext() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val directory = context.noBackupFilesDir.resolve("restore-${UUID.randomUUID()}")
        val provider = StandaloneDatabaseProvider(context)
        val name = directory.name.replace("-", "")
        val index = androidx.media3.exoplayer.offline.DefaultDownloadIndex(provider, name)
        for ((id, state) in listOf("one" to 0, "two" to 0, "removing" to 5)) {
            val request = androidx.media3.exoplayer.offline.DownloadRequest.Builder(
                id,
                android.net.Uri.parse("https://fscgc.scgchc.com/$id.mp4")
            )
                .setMimeType("video/mp4").setCustomCacheKey(id).build()
            index.putDownload(androidx.media3.exoplayer.offline.Download(request, state, 0, 0, -1, 0, 0))
        }
        val opened = java.util.concurrent.atomic.AtomicInteger()
        val gateway = Media3TransferGateway(context, directory, provider, name) {
            opened.incrementAndGet()
            DataSource.Factory { ByteArrayDataSource(byteArrayOf(1)) }
        }
        try {
            gateway.snapshots()
            withTimeout(10_000) { while (gateway.snapshots().any { it.attemptId == "removing" }) delay(50) }
            assertEquals(0, opened.get())
            assertEquals(2, gateway.snapshots().size)
            org.junit.Assert.assertTrue(gateway.snapshots().all { it.phase == ManagedTransferPhase.Waiting })
        } finally {
            gateway.shutdown()
            provider.close()
            directory.deleteRecursively()
        }
    }

    @Test fun bootstrapStaysStoppedAndCompletedBytesSurviveRecreation() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val directory = context.noBackupFilesDir.resolve("fixture-${UUID.randomUUID()}")
        val provider = StandaloneDatabaseProvider(context)
        val bytes = ByteArray(128 * 1024) { (it % 251).toByte() }
        val task = DownloadTask(
            "id", "1", "Fixture", "Programme", LocalDate.of(2026, 10, 17), Quality.Standard,
            Quality.Standard, "https://fscgc.scgchc.com/a.mp4", "a.mp4", false, createdAt = Instant.EPOCH,
            owner = DownloadOwner.Media3, cacheKey = "fixture", totalBytes = bytes.size.toLong()
        )

        fun engine() = Media3TransferGateway(context, directory, provider, directory.name.replace("-", "")) {
            DataSource.Factory { ByteArrayDataSource(bytes) }
        }
        var gateway = engine()
        try {
            gateway.enqueue(task)
            delay(250)
            assertEquals(0, gateway.snapshots().single().bytes)
            gateway.allow(task, true)
            withTimeout(10_000) {
                while (gateway.snapshots().none { it.phase == ManagedTransferPhase.Complete }) delay(50)
            }
            gateway.shutdown()
            gateway = engine()
            assertArrayEquals(bytes, gateway.openCached(task).use { it.readBytes() })
            gateway.remove(task.attemptId)
        } finally {
            gateway.shutdown()
            provider.close()
            directory.deleteRecursively()
        }
    }
}
