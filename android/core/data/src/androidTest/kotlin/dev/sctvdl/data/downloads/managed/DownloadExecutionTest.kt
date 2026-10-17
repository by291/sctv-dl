package dev.sctvdl.data.downloads.managed

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import dev.sctvdl.data.database.SctvDatabase
import dev.sctvdl.data.downloads.DownloadPublication
import dev.sctvdl.data.downloads.DownloadTransitions
import dev.sctvdl.data.downloads.local.RoomDownloadStore
import dev.sctvdl.data.downloads.platform.FileDeleteResult
import dev.sctvdl.data.downloads.platform.PublicDownloadFiles
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadReason
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.media.Quality
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class DownloadExecutionTest {
    @Test fun interruptedTransferWaitsForAnotherLeaseWithoutReplacingItsAttemptOrCache() = runBlocking {
        checkRecovery(DownloadReason.Network, DownloadState.Waiting, resumed = true)
    }

    @Test fun changedRepresentationRequiresExplicitRestart() = runBlocking {
        checkRecovery(DownloadReason.ResumeRequired, DownloadState.Failed, resumed = false)
    }

    private suspend fun checkRecovery(failure: DownloadReason, expected: DownloadState, resumed: Boolean) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val database = Room.inMemoryDatabaseBuilder(context, SctvDatabase::class.java).build()
        val store = RoomDownloadStore(database)
        val scheduler = DownloadRecoveryScheduler(context, store)
        val gateway = Gateway(failure)
        val access = DownloadNetworkAccess(context, OkHttpClient())
        val transitions = DownloadTransitions()
        val files = Files()
        val runtime = ManagedTransferRuntime(
            context,
            store,
            gateway,
            access,
            DownloadPublication(store, files, transitions),
            files,
            transitions,
            scheduler
        )
        val task = DownloadTask(
            "fixture", "1", "Fixture", "Programme", LocalDate.of(2026, 10, 17),
            Quality.Standard, Quality.Standard, "https://fscgc.scgchc.com/fixture.mp4", "fixture.mp4", false,
            createdAt = Instant.EPOCH, owner = DownloadOwner.Media3, state = DownloadState.Running,
            cacheKey = "retained", mediaChecked = true
        )
        var lease = runtime.acquire(ExecutionOwner.Foreground)
        try {
            store.update(task)
            runtime.reconcile()
            assertEquals(expected, store.get(task.id)?.state)
            assertEquals(task.attemptId, store.get(task.id)?.attemptId)
            assertEquals("retained", store.get(task.id)?.cacheKey)
            assertEquals(resumed, gateway.recovered)
            assertFalse(runtime.hasWork(ExecutionOwner.Foreground))
            if (resumed) {
                lease.close()
                lease = runtime.acquire(ExecutionOwner.Foreground)
                runtime.reconcile()
                assertEquals(DownloadState.Pending, store.get(task.id)?.state)
                assertEquals(4096L, store.get(task.id)?.bytes)
            }
        } finally {
            lease.close()
            store.remove(task.id)
            scheduler.reconcile()
            database.close()
        }
    }

    private class Gateway(failure: DownloadReason) : ManagedTransferGateway {
        override val updates = emptyFlow<ManagedTransferSnapshot>()
        var current =
            ManagedTransferSnapshot("fixture", ManagedTransferPhase.Failed, 4096, null, "retained", true, failure)
        var recovered = false

        override suspend fun enqueue(task: DownloadTask) = Unit

        override suspend fun allow(task: DownloadTask, permitted: Boolean) = Unit

        override suspend fun pause(attemptId: String) = Unit

        override suspend fun resume(attemptId: String) {
            recovered = true
            current = current.copy(phase = ManagedTransferPhase.Waiting, failure = null)
        }

        override suspend fun remove(attemptId: String) = Unit

        override suspend fun snapshots() = listOf(current)

        override suspend fun openCached(task: DownloadTask) = error("No publication expected")

        override suspend fun shutdown() = Unit
    }

    private class Files : PublicDownloadFiles {
        override suspend fun reserve(task: DownloadTask) = error("No publication expected")

        override suspend fun copyCached(task: DownloadTask, pendingUri: String) = error("No publication expected")

        override suspend fun finalize(pendingUri: String) = Unit

        override suspend fun isReadable(uri: String) = true

        override suspend fun isPublished(task: DownloadTask, uri: String) = false

        override suspend fun delete(uri: String) = FileDeleteResult.Missing

        override suspend fun findPlanned(task: DownloadTask) = emptyList<String>()
    }
}
