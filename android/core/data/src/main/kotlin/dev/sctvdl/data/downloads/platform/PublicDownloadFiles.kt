package dev.sctvdl.data.downloads.platform

import dev.sctvdl.domain.download.DownloadTask

internal sealed interface FileDeleteResult {
    data object Deleted : FileDeleteResult

    data object Missing : FileDeleteResult

    data class ConsentRequired(val token: String) : FileDeleteResult
}

internal interface PublicDownloadFiles {
    suspend fun reserve(task: DownloadTask): String

    suspend fun copyCached(task: DownloadTask, pendingUri: String): Long

    suspend fun finalize(pendingUri: String)

    suspend fun isReadable(uri: String): Boolean

    suspend fun isPublished(task: DownloadTask, uri: String): Boolean

    suspend fun delete(uri: String): FileDeleteResult

    suspend fun findPlanned(task: DownloadTask): List<String>
}
