package dev.sctvdl.domain.repository

import dev.sctvdl.domain.download.BatchDownloadResult
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.download.DownloadTask
import kotlinx.coroutines.flow.Flow

/** Persists download attempts and derives transfer progress and file availability from the system service. */
interface DownloadRepository {
    fun observeTasks(): Flow<List<DownloadTask>>

    /** Returns per-item submission outcomes; queued items have not necessarily finished transferring. */
    suspend fun enqueue(requests: List<DownloadRequest>): BatchDownloadResult

    /** Removes an active system job and its partial file. */
    suspend fun cancel(taskId: String)

    suspend fun retry(taskId: String): BatchDownloadResult

    /** Removes an inactive history record while preserving its downloaded file. */
    suspend fun removeRecord(taskId: String)

    /** Recovers interrupted submissions and rechecks system status and completed content URIs. */
    suspend fun reconcile()
}
