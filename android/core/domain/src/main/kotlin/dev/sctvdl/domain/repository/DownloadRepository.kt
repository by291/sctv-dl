package dev.sctvdl.domain.repository

import dev.sctvdl.domain.download.BatchDownloadResult
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.download.DownloadTask
import kotlinx.coroutines.flow.Flow

interface DownloadRepository {
    fun observeTasks(): Flow<List<DownloadTask>>
    suspend fun enqueue(requests: List<DownloadRequest>): BatchDownloadResult
    suspend fun cancel(taskId: String)
    suspend fun retry(taskId: String): BatchDownloadResult
    suspend fun removeRecord(taskId: String)
    suspend fun reconcile()
}
