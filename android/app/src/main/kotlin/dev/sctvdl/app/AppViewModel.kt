package dev.sctvdl.app

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.common.AppException
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.repository.DownloadRepository
import dev.sctvdl.domain.repository.SettingsRepository
import dev.sctvdl.ui.downloads.batchResultMessage
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@HiltViewModel
internal class AppViewModel @Inject constructor(
    settings: SettingsRepository,
    private val downloads: DownloadRepository,
    private val saved: SavedStateHandle
) : ViewModel() {
    private val messages = MutableStateFlow(
        saved.get<String>("downloadMessage")?.let {
            AppMessage(saved["downloadMessageId"] ?: 0L, it)
        }
    )

    val uiState = combine(settings.settings, messages) { preferences, message ->
        AppUiState(preferences, message)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AppUiState(downloadMessage = messages.value))

    fun enqueue(requests: List<DownloadRequest>) {
        if (requests.isEmpty()) return

        viewModelScope.launch {
            try {
                showMessage(batchResultMessage(downloads.enqueue(requests)))
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                showMessage((error as? AppException)?.error?.message ?: "无法创建下载任务，请重试")
            }
        }
    }

    private fun showMessage(text: String) {
        val id = (saved.get<Long>("downloadMessageId") ?: 0L) + 1L

        saved["downloadMessageId"] = id
        saved["downloadMessage"] = text
        messages.value = AppMessage(id, text)
    }

    fun acknowledgeMessage(id: Long) {
        // A dismissed snackbar may finish after a newer download result has already arrived.
        if (messages.value?.id != id) return

        saved["downloadMessage"] = null
        messages.value = null
    }

    suspend fun reconcile() {
        try {
            downloads.reconcile()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            // The next foreground poll retries; existing tasks remain visible.
        }
    }
}
