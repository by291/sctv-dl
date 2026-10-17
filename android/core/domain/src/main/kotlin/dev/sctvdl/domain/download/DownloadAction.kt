package dev.sctvdl.domain.download

enum class DownloadAction { Pause, Resume, Retry, Publish, Cancel, DeleteFile, RemoveRecord }

sealed interface DownloadActionResult {
    data object Applied : DownloadActionResult

    data object Skipped : DownloadActionResult

    data class ConsentRequired(val token: String) : DownloadActionResult
}

/** Capabilities are recomputed at the mutation boundary; UI state alone never authorizes an old attempt. */
fun supportedActions(task: DownloadTask): Set<DownloadAction> = buildSet {
    if (task.state.isActive) {
        add(DownloadAction.Cancel)
        if (task.owner == DownloadOwner.Media3 && !task.cacheComplete) {
            if (task.state == DownloadState.Paused) {
                add(DownloadAction.Resume)
            } else {
                add(DownloadAction.Pause)
            }
        }
    } else if (task.cacheComplete && task.state == DownloadState.Failed) {
        add(DownloadAction.Publish)
        add(DownloadAction.Cancel)
    } else {
        if (task.reasonCode != DownloadReason.Ambiguous && !task.cleanupPending) add(DownloadAction.RemoveRecord)
        if (task.state == DownloadState.Completed && task.contentUri != null) add(DownloadAction.DeleteFile)
        if (task.state in setOf(DownloadState.Failed, DownloadState.Missing, DownloadState.Cancelled) &&
            task.reasonCode != DownloadReason.Ambiguous && !task.cleanupPending
        ) {
            add(DownloadAction.Retry)
        }
    }
}
