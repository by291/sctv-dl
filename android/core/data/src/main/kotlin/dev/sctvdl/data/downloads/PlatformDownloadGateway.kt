package dev.sctvdl.data.downloads

import dev.sctvdl.domain.DownloadReason
import dev.sctvdl.domain.DownloadState

data class PlatformDownloadRequest(val url: String, val title: String, val filename: String, val wifiOnly: Boolean)
data class SystemDownloadSnapshot(
    val id: Long,
    val url: String,
    val destination: String?,
    val state: DownloadState,
    val bytes: Long = 0,
    val total: Long? = null,
    val contentUri: String? = null,
    val reason: String? = null,
    val reasonCode: DownloadReason? = null
)

interface PlatformDownloadGateway {
    fun destinationFor(filename: String): String
    suspend fun enqueue(request: PlatformDownloadRequest): Long
    suspend fun query(ids: List<Long>): List<SystemDownloadSnapshot>
    suspend fun queryOwned(): List<SystemDownloadSnapshot>
    suspend fun remove(id: Long)
    suspend fun isAvailable(uri: String): Boolean
}
