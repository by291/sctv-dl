package dev.sctvdl.data.downloads

import dev.sctvdl.data.downloads.platform.FileDeleteResult
import dev.sctvdl.data.downloads.platform.PublicDownloadFiles
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.target
import dev.sctvdl.domain.media.Quality
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadPublicationTest {
    @Test fun recoversInsertionAndFinalizationWithoutDuplicateFiles() = runTest {
        val task = DownloadTask(
            "id", "1", "Episode", "Programme", LocalDate.of(2026, 10, 17), Quality.Standard,
            Quality.Standard, "https://fscgc.scgchc.com/a.mp4", "unique.mp4", false, createdAt = Instant.EPOCH,
            owner = DownloadOwner.Media3, state = DownloadState.Finalizing, cacheComplete = true, totalBytes = 4096,
            publicationStarted = true
        )
        val store = FakeDownloadStore().apply { update(task) }
        val files = Files()
        val publication = DownloadPublication(store, files, DownloadTransitions())
        publication.publish(task.target)
        assertEquals(0, files.reservations)
        assertEquals(DownloadState.Completed, store.get("id")?.state)
        assertTrue(store.get("id")?.cleanupPending == true)
        assertEquals("content://fixture/1", store.get("id")?.contentUri)
    }

    @Test fun publicationFailureRetainsPrivateMediaAndRetriesOnlyPublication() = runTest {
        val task = DownloadTask(
            "id", "1", "Episode", "Programme", LocalDate.of(2026, 10, 17), Quality.Standard,
            Quality.Standard, "https://fscgc.scgchc.com/a.mp4", "unique.mp4", false, createdAt = Instant.EPOCH,
            owner = DownloadOwner.Media3, state = DownloadState.Finalizing, cacheComplete = true, totalBytes = 4096
        )
        val store = FakeDownloadStore().apply { update(task) }
        val files = Files().apply {
            exists = false
            published = false
            failCopy = true
        }
        val publication = DownloadPublication(store, files, DownloadTransitions())
        publication.publish(task.target)
        assertEquals(DownloadState.Failed, store.get("id")?.state)
        assertTrue(store.get("id")?.cacheComplete == true)
        files.failCopy = false
        publication.publish(task.target)
        assertEquals(DownloadState.Completed, store.get("id")?.state)
        assertEquals(1, files.reservations)
    }

    private class Files : PublicDownloadFiles {
        var exists = true
        var published = true
        var failCopy = false
        var reservations = 0

        override suspend fun reserve(task: DownloadTask): String {
            reservations++
            exists = true
            return "content://fixture/1"
        }

        override suspend fun copyCached(task: DownloadTask, pendingUri: String): Long {
            if (failCopy) error("Disk full")
            return 4096
        }

        override suspend fun finalize(pendingUri: String) {
            published = true
        }

        override suspend fun isReadable(uri: String) = exists

        override suspend fun isPublished(task: DownloadTask, uri: String) = exists && published

        override suspend fun delete(uri: String): FileDeleteResult {
            exists = false
            return FileDeleteResult.Deleted
        }

        override suspend fun findPlanned(task: DownloadTask) =
            if (exists) listOf("content://fixture/1") else emptyList()
    }
}
