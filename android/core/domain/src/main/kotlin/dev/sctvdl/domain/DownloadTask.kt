package dev.sctvdl.domain

import java.time.Instant
import java.time.LocalDate

enum class DownloadState {
    Preparing,
    Pending,
    Running,
    Waiting,
    Failed,
    Completed,
    Cancelled,
    Missing
}
enum class DownloadReason {
    Network,
    Wifi,
    Retry,
    Http,
    Storage,
    Removed,
    FileMissing,
    Interrupted,
    Ambiguous,
    Cancelled,
    Unknown
}
val DownloadState.isActive: Boolean get() = this in setOf(
    DownloadState.Preparing,
    DownloadState.Pending,
    DownloadState.Running,
    DownloadState.Waiting
)
data class DownloadRequest(
    val programmeName: String,
    val broadcastDate: LocalDate,
    val content: ProgrammeContent,
    val requestedQuality: Quality,
    val wifiOnly: Boolean
)
data class DownloadTask(
    val id: String,
    val contentId: String,
    val title: String,
    val programmeName: String,
    val broadcastDate: LocalDate,
    val requestedQuality: Quality,
    val actualQuality: Quality,
    val url: String,
    val filename: String,
    val wifiOnly: Boolean,
    val systemId: Long? = null,
    val contentUri: String? = null,
    val bytes: Long = 0,
    val totalBytes: Long? = null,
    val state: DownloadState = DownloadState.Preparing,
    val reason: String? = null,
    val createdAt: Instant,
    val reasonCode: DownloadReason? = null
)
data class DownloadFailure(val contentId: String, val error: AppError)
data class BatchDownloadResult(val queued: Int, val fallbacks: Int, val failures: List<DownloadFailure>)
