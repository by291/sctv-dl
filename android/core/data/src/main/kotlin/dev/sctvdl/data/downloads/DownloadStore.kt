package dev.sctvdl.data.downloads

import dev.sctvdl.domain.DownloadTask
import kotlinx.coroutines.flow.Flow

interface DownloadStore {
    fun observe(): Flow<List<DownloadTask>>
    suspend fun all(): List<DownloadTask>
    suspend fun get(id: String): DownloadTask?
    suspend fun reserve(task: DownloadTask): Boolean
    suspend fun update(task: DownloadTask)
    suspend fun remove(id: String)
}

fun activeDownloadKey(task: DownloadTask) = "${task.contentId}|${task.actualQuality.name}"
