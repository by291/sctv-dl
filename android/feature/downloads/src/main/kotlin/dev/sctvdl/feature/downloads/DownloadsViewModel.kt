package dev.sctvdl.feature.downloads

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.common.AppException
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.repository.DownloadRepository
import dev.sctvdl.ui.downloads.batchResultMessage
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@HiltViewModel
internal class DownloadsViewModel @Inject constructor(
    private val repository: DownloadRepository,
    private val saved: SavedStateHandle
) : ViewModel() {
    private val selectedTab = saved.getStateFlow("downloadTab", DownloadTab.Active.name)
    val uiState = combine(repository.observeTasks(), selectedTab) { tasks, selected ->
        DownloadsUiState(
            tasks,
            DownloadTab.entries.firstOrNull { it.name == selected } ?: DownloadTab.Active,
            false
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DownloadsUiState())
    val message = saved.getStateFlow<String?>("taskMessage", null)

    fun tab(tab: DownloadTab) {
        saved["downloadTab"] = tab.name
    }
    fun cancel(id: String) = action { repository.cancel(id) }
    fun retry(id: String) = action { saved["taskMessage"] = batchResultMessage(repository.retry(id)) }
    fun remove(id: String) = action {
        repository.removeRecord(id)
        saved["taskMessage"] =
            "已移除记录，下载文件会保留"
    }
    fun consumeMessage() {
        saved["taskMessage"] = null
    }
    fun showMessage(text: String) {
        saved["taskMessage"] = text
    }

    fun withFile(id: String, onReady: (DownloadTask) -> Unit) = action {
        repository.reconcile()
        val task = repository.observeTasks().first().firstOrNull { it.id == id }
        if (task?.state == DownloadState.Completed && task.contentUri != null) {
            onReady(task)
        } else {
            saved["taskMessage"] = "下载文件已不可用，请重新下载"
        }
    }

    private fun action(block: suspend () -> Unit) {
        viewModelScope.launch {
            try {
                block()
            } catch (
                error: CancellationException
            ) {
                throw error
            } catch (error: Exception) {
                saved["taskMessage"] =
                    (error as? AppException)?.error?.message ?: "操作未完成，请重试"
            }
        }
    }
}
