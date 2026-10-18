package dev.sctvdl.data.downloads.managed

import dev.sctvdl.domain.download.DownloadReason
import dev.sctvdl.domain.download.DownloadTask
import java.io.InputStream
import kotlinx.coroutines.flow.Flow

internal enum class ManagedTransferPhase { Pending, Running, Waiting, Paused, Complete, Failed }

internal data class ManagedTransferSnapshot(
    val attemptId: String,
    val phase: ManagedTransferPhase,
    val bytes: Long,
    val total: Long?,
    val cacheKey: String,
    val resumable: Boolean,
    val failure: DownloadReason? = null
)

internal interface ManagedTransferGateway {
    val updates: Flow<ManagedTransferSnapshot>

    suspend fun enqueue(task: DownloadTask)

    suspend fun allow(task: DownloadTask, permitted: Boolean)

    suspend fun pause(attemptId: String)

    suspend fun resume(attemptId: String)

    suspend fun remove(attemptId: String)

    suspend fun snapshots(): List<ManagedTransferSnapshot>

    suspend fun openCached(task: DownloadTask): InputStream

    suspend fun shutdown()
}
