package dev.sctvdl.domain.download

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
