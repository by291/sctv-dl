package dev.sctvdl.data.downloads.local

import dev.sctvdl.domain.download.DownloadTask
import kotlinx.coroutines.flow.Flow

internal interface DownloadStore {
    fun observe(): Flow<List<DownloadTask>>

    suspend fun all(): List<DownloadTask>

    suspend fun get(id: String): DownloadTask?

    suspend fun reserve(task: DownloadTask): Boolean

    suspend fun update(task: DownloadTask)

    suspend fun remove(id: String)
}

internal fun activeDownloadKey(task: DownloadTask) = "${task.contentId}|${task.actualQuality.name}"
