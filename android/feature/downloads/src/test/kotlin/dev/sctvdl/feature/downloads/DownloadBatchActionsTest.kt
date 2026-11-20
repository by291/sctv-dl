package dev.sctvdl.feature.downloads

import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadActionResult
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.repository.DownloadRepository
import dev.sctvdl.domain.testing.FakeDownloads
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
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
            DownloadBatchRequest(
                repository = repository,
                action = DownloadAction.Pause,
                targets = listOf("first", "second", "changed", "third").map { DownloadTarget(it, "attempt") },
                requestConsent = { false }
            )
        )

        assertEquals(setOf("first", "third"), result.appliedIds)
        assertEquals(setOf("changed"), result.skippedIds)
        assertEquals(setOf("second"), result.failures.keys)
    }

    @Test fun cancellingWhileAuthorizationIsPendingDiscardsTheOneShotToken() = runTest {
        val repository = ConsentRepository()
        val target = DownloadTarget("record", "attempt")
        val prompt = CompletableDeferred<String>()

        val batch = launch {
            runDownloadBatch(
                DownloadBatchRequest(
                    repository = repository,
                    action = DownloadAction.DeleteFile,
                    targets = listOf(target),
                    requestConsent = { token ->
                        prompt.complete(token)
                        awaitCancellation()
                    }
                )
            )
        }
        val token = withTimeout(1_000) { prompt.await() }
        withTimeout(1_000) { batch.cancelAndJoin() }

        assertTrue(batch.isCancelled)
        assertEquals(
            DownloadActionResult.Skipped,
            repository.completeFileConsent(target, token, granted = true)
        )
        assertTrue(repository.fileExists)
    }

    private class ConsentRepository : DownloadRepository by FakeDownloads() {
        var fileExists = true
            private set

        private var pendingToken: String? = null

        override suspend fun perform(target: DownloadTarget, action: DownloadAction) =
            DownloadActionResult.ConsentRequired("pending-delete").also { pendingToken = it.token }

        override suspend fun completeFileConsent(
            target: DownloadTarget,
            token: String,
            granted: Boolean
        ): DownloadActionResult {
            // Suspending here proves the batch settles cleanup after cancellation.
            delay(1)
            if (token != pendingToken) {
                return DownloadActionResult.Skipped
            }

            pendingToken = null
            if (!granted) {
                return DownloadActionResult.Skipped
            }
            fileExists = false
            return DownloadActionResult.Applied
        }
    }
}
