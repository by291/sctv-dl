package dev.sctvdl.data.downloads

import dev.sctvdl.data.di.DownloadFileConsentRegistry
import dev.sctvdl.data.downloads.local.LegacyDownloadStore
import dev.sctvdl.data.downloads.managed.ManagedDownloadControl
import dev.sctvdl.data.downloads.platform.FileDeleteResult
import dev.sctvdl.data.downloads.platform.PublicDownloadFiles
import dev.sctvdl.data.downloads.preflight.MediaPreflight
import dev.sctvdl.data.downloads.preflight.ProbeResponse
import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadActionResult
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.target
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.repository.DownloadRepository
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ManagedDownloadRepositoryTest {
    @Test fun retryChangesAttemptAndOldBatchTargetCannotCancelIt() = runTest {
        val store = FakeDownloadStore().apply { update(task(DownloadState.Failed)) }
        val control = Control()
        val repo = repository(store, control, Files())
        val old = requireNotNull(store.get("id"))
        assertEquals(DownloadActionResult.Applied, repo.perform(old.target, DownloadAction.Retry))
        val retried = requireNotNull(store.get("id"))
        assertNotEquals(old.attemptId, retried.attemptId)
        assertEquals(DownloadOwner.Media3, retried.owner)
        assertEquals(DownloadActionResult.Skipped, repo.perform(old.target, DownloadAction.Cancel))
        assertEquals(DownloadState.Preparing, store.get("id")?.state)
    }

    @Test fun deletingFileRetainsRecordAndRemovingRecordRetainsFile() = runTest {
        val store = FakeDownloadStore().apply { update(task(DownloadState.Completed)) }
        val files = Files()
        val repo = repository(store, Control(), files)
        repo.perform(requireNotNull(store.get("id")).target, DownloadAction.DeleteFile)
        assertEquals(DownloadState.Missing, store.get("id")?.state)
        assertEquals(1, files.deletions)
        store.update(task(DownloadState.Completed))
        repo.perform(requireNotNull(store.get("id")).target, DownloadAction.RemoveRecord)
        assertTrue(store.all().isEmpty())
        assertEquals(1, files.deletions)
    }

    @Test fun removingFailedRecordCleansPrivateTransferBeforeDroppingIdentity() = runTest {
        val store = FakeDownloadStore().apply { update(task(DownloadState.Failed)) }
        val control = Control()
        val repo = repository(store, control, Files())
        repo.perform(requireNotNull(store.get("id")).target, DownloadAction.RemoveRecord)
        assertEquals(listOf("id"), control.removed)
        assertTrue(store.all().isEmpty())
    }

    private fun repository(store: FakeDownloadStore, control: Control, files: Files): DownloadRepository =
        ManagedDownloadRepository(
            store,
            DownloadManagerRepository(
                LegacyDownloadStore(store),
                FakeDownloadGateway(),
                MediaPreflight { _, _, _ ->
                    ProbeResponse(200, "video/mp4", 4096)
                },
                Clock.systemUTC(),
                Dispatchers.Unconfined
            ),
            control,
            files,
            DownloadFileConsentRegistry(),
            DownloadTransitions(),
            Clock.systemUTC()
        )

    private fun task(state: DownloadState) = DownloadTask(
        "id", "1", "Episode", "Programme", LocalDate.of(2026, 10, 17), Quality.Standard,
        Quality.Standard, "https://fscgc.scgchc.com/a.mp4", "a.mp4", false, createdAt = Instant.EPOCH,
        owner = DownloadOwner.Media3, state = state, contentUri = "content://fixture/1"
    )

    private class Control : ManagedDownloadControl {
        val removed = mutableListOf<String>()

        override suspend fun reconcile() = Unit

        override suspend fun start() = Unit

        override suspend fun stop(task: DownloadTask) = Unit

        override suspend fun remove(task: DownloadTask) {
            removed += task.attemptId
        }
    }

    private class Files : PublicDownloadFiles {
        var deletions = 0

        override suspend fun reserve(task: DownloadTask) = "content://fixture/1"

        override suspend fun copyCached(task: DownloadTask, pendingUri: String) = 4096L

        override suspend fun finalize(pendingUri: String) = Unit

        override suspend fun isReadable(uri: String) = true

        override suspend fun isPublished(task: DownloadTask, uri: String) = true

        override suspend fun delete(uri: String): FileDeleteResult {
            deletions++
            return FileDeleteResult.Deleted
        }

        override suspend fun findPlanned(task: DownloadTask) = emptyList<String>()
    }
}
