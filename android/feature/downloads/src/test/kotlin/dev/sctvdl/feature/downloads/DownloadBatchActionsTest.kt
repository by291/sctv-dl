package dev.sctvdl.feature.downloads

import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadActionResult
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.repository.DownloadRepository
import dev.sctvdl.domain.testing.FakeDownloads
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class DownloadBatchActionsTest {
    @Test fun middleFailureAndStaleAttemptDoNotStopLaterItems() = runTest {
        val repository = object : DownloadRepository by FakeDownloads() {
            override suspend fun perform(target: DownloadTarget, action: DownloadAction): DownloadActionResult =
                when (target.id) {
                    "second" -> error("Disk unavailable")
                    "changed" -> DownloadActionResult.Skipped
                    else -> DownloadActionResult.Applied
                }
        }
        val result = runDownloadBatch(
            repository,
            DownloadAction.Pause,
            listOf("first", "second", "changed", "third").map { DownloadTarget(it, "attempt") }
        ) { false }
        assertEquals(setOf("first", "third"), result.appliedIds)
        assertEquals(setOf("changed"), result.skippedIds)
        assertEquals(setOf("second"), result.failures.keys)
    }
}
