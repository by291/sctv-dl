package dev.sctvdl.feature.downloads

import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.isActive

internal enum class DownloadFilter(val label: String) {
    All("全部"),
    Active("下载中"),
    Unfinished("未完成"),
    Completed("已完成"),
    Removed("文件已移除");

    fun includes(task: DownloadTask): Boolean = when (this) {
        All -> true
        Active -> task.state.isActive
        Unfinished -> task.state in setOf(DownloadState.Failed, DownloadState.Cancelled)
        Completed -> task.state == DownloadState.Completed
        Removed -> task.state == DownloadState.Missing
    }
}

internal typealias DownloadTab = DownloadFilter

val DownloadState.isInActiveSection: Boolean get() = isActive || this == DownloadState.Failed

internal data class DownloadsUiState(
    val tasks: List<DownloadTask> = emptyList(),
    val tab: DownloadFilter = DownloadFilter.Active,
    val loading: Boolean = true,
    val selection: Map<String, String> = emptyMap(),
    val selecting: Boolean = false,
    val busy: Boolean = false,
    val error: String? = null
) {
    val visible: List<DownloadTask> get() = tasks.filter(tab::includes)
    val targets: List<DownloadTarget> get() = selection.map { DownloadTarget(it.key, it.value) }
}
