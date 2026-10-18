package dev.sctvdl.feature.player.local

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.repository.DownloadRepository
import dev.sctvdl.domain.repository.HistoryRepository
import dev.sctvdl.feature.player.PlaybackHistoryRecorder
import dev.sctvdl.feature.player.PlayerUiState
import dev.sctvdl.player.model.PlaybackSource
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

@HiltViewModel
internal class LocalPlayerViewModel @Inject constructor(
    private val repository: DownloadRepository,
    private val saved: SavedStateHandle,
    private val history: HistoryRepository
) : ViewModel() {
    private val mutableState = MutableStateFlow(PlayerUiState())
    val uiState = mutableState.asStateFlow()

    private var taskId: String? = null
    private var job: Job? = null

    fun open(taskId: String) {
        if (this.taskId == taskId) return

        this.taskId = taskId
        observe(taskId)
    }

    private fun observe(id: String) {
        job?.cancel()
        mutableState.value = PlayerUiState()

        job = viewModelScope.launch {
            try {
                // Recheck the completed URI before trusting a download record restored from disk.
                repository.reconcile()

                var recorder: PlaybackHistoryRecorder? = null
                var resume = 0L
                repository.observeTasks().collect { tasks ->
                    val task = tasks.firstOrNull { it.id == id }
                    if (task != null && recorder == null) {
                        recorder = PlaybackHistoryRecorder(
                            history,
                            task.selection?.let { ViewingTarget.Online(it) }
                                ?: ViewingTarget.LegacyDownload(
                                    task.id,
                                    task.title,
                                    task.programmeName,
                                    task.broadcastDate
                                ),
                            viewModelScope
                        )
                        resume = requireNotNull(recorder).initialize()
                    }
                    val source = task?.takeIf {
                        it.state == DownloadState.Completed &&
                            it.contentUri != null
                    }?.let {
                        PlaybackSource(
                            "local-${it.id}",
                            it.title,
                            emptyList(),
                            it.contentUri,
                            saved["positionMs"] ?: resume
                        )
                    }
                    if (taskId == id) {
                        mutableState.value =
                            PlayerUiState(
                                false,
                                source,
                                history = recorder,
                                error = if (source == null) {
                                    AppError(ErrorKind.Storage, "下载文件已不可用，请返回下载页重新下载")
                                } else {
                                    null
                                }
                            )
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                mutableState.value =
                    PlayerUiState(false, error = AppError(ErrorKind.Storage, "无法读取下载文件，请重试"))
            }
        }
    }

    fun retry() {
        taskId?.let(::observe)
    }

    fun savePosition(positionMs: Long) {
        saved["positionMs"] = positionMs.coerceAtLeast(0)
    }
}
