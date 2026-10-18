package dev.sctvdl.feature.downloads

import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.isActive

internal enum class DownloadFilter(val label: String) {
    All("全部"),
    Active("下载中"),
    Completed("已完成"),

    // Keep the saved filter name from versions that combined failed and cancelled tasks.
    Unfinished("下载失败"),
    Cancelled("已取消"),
    Removed("文件已移除");

    fun includes(task: DownloadTask): Boolean = when (this) {
        All -> true
        Active -> task.state.isActive
        Completed -> task.state == DownloadState.Completed
        Unfinished -> task.state == DownloadState.Failed
        Cancelled -> task.state == DownloadState.Cancelled
        Removed -> task.state == DownloadState.Missing
    }
}

internal typealias DownloadTab = DownloadFilter

val DownloadState.isInActiveSection: Boolean get() = isActive || this == DownloadState.Failed

internal data class DownloadsUiState(
    val tasks: List<DownloadTask> = emptyList(),
    val tab: DownloadFilter = DownloadFilter.All,
    val loading: Boolean = true,
    val selection: Map<String, String> = emptyMap(),
    val selecting: Boolean = false,
    val busy: Boolean = false,
    val error: String? = null
) {
    val visible: List<DownloadTask> get() = DownloadFilter.entries
        .filter { it != DownloadFilter.All && (tab == DownloadFilter.All || it == tab) }
        .flatMap { filter -> tasks.filter(filter::includes).sortedWith(downloadTaskOrder) }
    val targets: List<DownloadTarget> get() = selection.map { DownloadTarget(it.key, it.value) }
}

// Progress and repository emission order must not move cards while a transfer is running.
private val downloadTaskOrder = compareByDescending<DownloadTask> { it.createdAt }.thenBy { it.id }
