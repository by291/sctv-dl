package dev.sctvdl.feature.downloads

import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.isActive

internal enum class DownloadTab { Active, Completed }

val DownloadState.isInActiveSection: Boolean get() = isActive || this == DownloadState.Failed

internal data class DownloadsUiState(
    val tasks: List<DownloadTask> = emptyList(),
    val tab: DownloadTab = DownloadTab.Active,
    val loading: Boolean = true
) {
    val visible: List<DownloadTask> get() = tasks.filter {
        it.state.isInActiveSection ==
            (tab == DownloadTab.Active)
    }
}
