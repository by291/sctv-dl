package dev.sctvdl.app.features.player

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.AppError
import dev.sctvdl.domain.DownloadRepository
import dev.sctvdl.domain.DownloadState
import dev.sctvdl.domain.ErrorKind
import dev.sctvdl.player.PlaybackSource
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
class LocalPlayerViewModel @Inject constructor(
    private val repository: DownloadRepository,
    private val saved: SavedStateHandle
) : ViewModel() {
    private val mutableState = MutableStateFlow(PlayerUiState())
    val state = mutableState.asStateFlow()
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
                repository.reconcile()
                repository.observeTasks().collect { tasks ->
                    val task = tasks.firstOrNull { it.id == id }
                    val source = task?.takeIf {
                        it.state == DownloadState.Completed &&
                            it.contentUri != null
                    }?.let {
                        PlaybackSource(
                            "local-${it.id}",
                            it.title,
                            emptyList(),
                            it.contentUri,
                            saved["positionMs"] ?: 0L
                        )
                    }
                    if (taskId == id) {
                        mutableState.value =
                            PlayerUiState(
                                false,
                                source,
                                error = if (source == null) {
                                    AppError(ErrorKind.Storage, "下载文件已不可用，请返回下载页重新下载")
                                } else {
                                    null
                                }
                            )
                    }
                }
            } catch (
                error: CancellationException
            ) {
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
