package dev.sctvdl.domain.download

enum class DownloadState {
    Preparing,
    Pending,
    Running,
    Waiting,
    Failed,
    Completed,
    Cancelled,
    Missing,
    Paused,
    Finalizing
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
    Unknown,
    ResumeRequired,
    Publication,
    BackgroundLimit
}

val DownloadState.isActive: Boolean get() = this in setOf(
    DownloadState.Preparing,
    DownloadState.Pending,
    DownloadState.Running,
    DownloadState.Waiting,
    DownloadState.Paused,
    DownloadState.Finalizing
)
