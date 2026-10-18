package dev.sctvdl.feature.downloads

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.common.AppException
import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.repository.DownloadRepository
import dev.sctvdl.ui.downloads.batchResultMessage
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@HiltViewModel
internal class DownloadsViewModel @Inject constructor(
    private val repository: DownloadRepository,
    private val saved: SavedStateHandle
) : ViewModel() {
    private val selectedTab = saved.getStateFlow("downloadTab", DownloadTab.All.name)

    private val selection = saved.getStateFlow("downloadSelection", hashMapOf<String, String>())
    private val selecting = saved.getStateFlow("downloadSelecting", false)
    private val busy = MutableStateFlow(false)

    private val observationVersion = MutableStateFlow(0)

    @OptIn(ExperimentalCoroutinesApi::class)
    val uiState = observationVersion.flatMapLatest {
        combine(repository.observeTasks(), selectedTab, selection, selecting, busy) {
                tasks,
                selected,
                selectedItems,
                selectionMode,
                working
            ->
            DownloadsUiState(
                tasks,
                DownloadFilter.entries.firstOrNull { it.name == selected } ?: DownloadFilter.All,
                false,
                selectedItems.toMap(),
                selectionMode,
                working
            )
        }.catch { failure ->
            if (failure is CancellationException) throw failure
            emit(DownloadsUiState(loading = false, error = "读取下载记录失败，请重试"))
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DownloadsUiState())
    val message = saved.getStateFlow<String?>("taskMessage", null)

    fun reload() {
        observationVersion.value++
    }

    fun tab(tab: DownloadTab) {
        saved["downloadTab"] = tab.name
        exitSelection()
    }

    fun beginSelection() {
        saved["downloadSelecting"] = true
    }

    fun exitSelection() {
        saved["downloadSelection"] = hashMapOf<String, String>()
        saved["downloadSelecting"] = false
    }

    fun toggle(task: DownloadTask) {
        val selected = HashMap(selection.value)
        if (selected.containsKey(task.id)) selected.remove(task.id) else selected[task.id] = task.attemptId
        saved["downloadSelection"] = selected
    }

    fun selectAll() {
        val visible = uiState.value.visible
        val allSelected = visible.isNotEmpty() && visible.all { it.id in selection.value }
        saved["downloadSelection"] = if (allSelected) {
            hashMapOf<String, String>()
        } else {
            HashMap(visible.associate { it.id to it.attemptId })
        }
    }

    suspend fun perform(
        action: DownloadAction,
        targets: List<DownloadTarget>,
        requestConsent: suspend (String) -> Boolean
    ) {
        if (busy.value) return
        busy.value = true
        try {
            val result = runDownloadBatch(repository, action, targets, requestConsent)
            saved["taskMessage"] =
                "已完成 ${result.appliedIds.size} 项，跳过 ${result.skippedIds.size} 项，失败 ${result.failures.size} 项"
            saved["downloadSelection"] =
                HashMap(selection.value.filterKeys { it !in result.appliedIds && it !in result.skippedIds })
        } finally {
            busy.value = false
        }
    }

    fun cancel(id: String) = action { repository.cancel(id) }

    fun retry(id: String) = action { saved["taskMessage"] = batchResultMessage(repository.retry(id)) }

    fun remove(id: String) = action {
        repository.removeRecord(id)
        saved["taskMessage"] = "已移除记录，下载文件会保留"
    }

    fun consumeMessage() {
        saved["taskMessage"] = null
    }

    fun showMessage(text: String) {
        saved["taskMessage"] = text
    }

    fun withFile(id: String, onReady: (DownloadTask) -> Unit) = action {
        // A completed record can outlive its file or URI permission; reconcile before handing it to another app.
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
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                saved["taskMessage"] = (error as? AppException)?.error?.message ?: "操作未完成，请重试"
            }
        }
    }
}
