package dev.sctvdl.domain.repository

import dev.sctvdl.domain.download.BatchDownloadResult
import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadActionResult
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.download.DownloadTask
import kotlinx.coroutines.flow.Flow

/** Persists download attempts and derives progress from their managed or legacy platform owner. */
interface DownloadRepository {
    /** Apply an action to the exact attempt, or return [DownloadActionResult.Skipped] if it is stale. */
    suspend fun perform(target: DownloadTarget, action: DownloadAction): DownloadActionResult =
        DownloadActionResult.Skipped

    /** Consume a one-time authorization token and recheck its attempt and file before deleting. */
    suspend fun completeFileConsent(target: DownloadTarget, token: String, granted: Boolean): DownloadActionResult =
        DownloadActionResult.Skipped

    /** Observe the current task index, including native progress. */
    fun observeTasks(): Flow<List<DownloadTask>>

    /** Returns per-item submission outcomes; queued items have not necessarily finished transferring. */
    suspend fun enqueue(requests: List<DownloadRequest>): BatchDownloadResult

    /** Cancels the active attempt and schedules private/partial-file cleanup; published files have a separate action. */
    suspend fun cancel(taskId: String)

    /** Request a replacement attempt for a task that can be retried. */
    suspend fun retry(taskId: String): BatchDownloadResult

    /** Removes an inactive history record while preserving its downloaded file. */
    suspend fun removeRecord(taskId: String)

    /** Recovers interrupted transfers/publications and rechecks native progress and completed content URIs. */
    suspend fun reconcile()
}
