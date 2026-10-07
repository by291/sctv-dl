package dev.sctvdl.app.features.downloads

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.AppException
import dev.sctvdl.domain.BatchDownloadResult
import dev.sctvdl.domain.DownloadRepository
import dev.sctvdl.domain.DownloadRequest
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

@HiltViewModel
class DownloadCoordinatorViewModel @Inject constructor(
    private val repository: DownloadRepository,
    private val saved: SavedStateHandle
) : ViewModel() {
    val message = saved.getStateFlow<String?>("downloadMessage", null)
    fun consumeMessage() {
        saved["downloadMessage"] = null
    }

    fun enqueue(requests: List<DownloadRequest>) {
        if (requests.isEmpty()) return
        viewModelScope.launch {
            try {
                saved["downloadMessage"] = batchResultMessage(repository.enqueue(requests))
            } catch (
                error: CancellationException
            ) {
                throw error
            } catch (error: Exception) {
                saved["downloadMessage"] =
                    (error as? AppException)?.error?.message ?: "无法创建下载任务，请重试"
            }
        }
    }

    suspend fun reconcile() {
        try {
            repository.reconcile()
        } catch (
            error: CancellationException
        ) {
            throw error
        } catch (
            _: Exception
        ) { /* The next visible poll retries; existing tasks remain visible. */ }
    }
}

fun batchResultMessage(result: BatchDownloadResult): String = buildString {
    append("已加入 ${result.queued} 个下载")
    if (result.fallbacks > 0) append("，${result.fallbacks} 个使用可用清晰度")
    if (result.failures.isNotEmpty()) {
        append(
            "；${result.failures.size} 个未加入：${result.failures.first().error.message}"
        )
    }
}
