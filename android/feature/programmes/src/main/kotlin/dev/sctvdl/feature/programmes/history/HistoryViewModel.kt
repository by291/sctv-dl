package dev.sctvdl.feature.programmes.history

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingKey
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.repository.HistoryRepository
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

internal data class HistoryUiState(
    val entries: List<ViewingEntry> = emptyList(),
    val query: String = "",
    val loading: Boolean = true,
    val error: String? = null
)

@HiltViewModel
internal class HistoryViewModel @Inject constructor(
    private val history: HistoryRepository,
    private val saved: SavedStateHandle
) : ViewModel() {
    private val mutableState = MutableStateFlow(HistoryUiState())
    val state = mutableState.asStateFlow()

    private var observation: kotlinx.coroutines.Job? = null

    init {
        observe()
    }

    fun query(value: String) {
        saved["historyQuery"] = value
    }

    fun retry() = observe()

    private fun observe() {
        observation?.cancel()
        observation = viewModelScope.launch {
            combine(history.observeEntries(), saved.getStateFlow("historyQuery", "")) { entries, query ->
                HistoryUiState(
                    entries.filter {
                        it.target.searchText().contains(query.trim(), ignoreCase = true)
                    },
                    query,
                    false
                )
            }.catch { failure ->
                if (failure is CancellationException) throw failure
                mutableState.update { it.copy(loading = false, error = "无法读取观看记录，请重试") }
            }.collect { mutableState.value = it }
        }
    }

    fun remove(key: ViewingKey) {
        viewModelScope.launch {
            try {
                history.remove(key)
                mutableState.update { it.copy(error = null) }
            } catch (failure: CancellationException) {
                throw failure
            } catch (_: Exception) {
                mutableState.update { it.copy(error = "删除记录失败，请重试") }
            }
        }
    }
}

private fun ViewingTarget.searchText() = when (this) {
    is ViewingTarget.Online -> "${selection.content.title} ${selection.programme.name} ${selection.broadcast.date}"
    is ViewingTarget.LegacyDownload -> "$title $programmeName $broadcastDate"
}
