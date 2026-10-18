package dev.sctvdl.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.repository.HistoryRepository
import dev.sctvdl.domain.repository.SettingsRepository
import dev.sctvdl.domain.repository.StorageMaintenance
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

@HiltViewModel
internal class SettingsViewModel @Inject constructor(
    private val repository: SettingsRepository,
    private val history: HistoryRepository,
    private val storage: StorageMaintenance
) : ViewModel() {
    private val mutableSettings = MutableStateFlow(AppSettings())
    val uiState = mutableSettings.asStateFlow()

    private val mutableError = MutableStateFlow<AppError?>(null)
    val error = mutableError.asStateFlow()

    private val writes = Mutex()
    private var observation: Job? = null
    private var failedUpdate: (AppSettings.() -> AppSettings)? = null

    private val mutableMaintenance = MutableStateFlow(StorageSettingsState())
    val maintenance = mutableMaintenance.asStateFlow()

    init {
        observeSettings()
    }

    private fun observeSettings() {
        if (observation?.isActive == true) return
        observation = viewModelScope.launch {
            try {
                repository.settings.collect {
                    mutableSettings.value = it
                    if (failedUpdate == null) mutableError.value = null
                }
            } catch (failure: CancellationException) {
                throw failure
            } catch (_: Exception) {
                mutableError.value = AppError(ErrorKind.Storage, "无法读取设置，请重试")
            }
        }
    }

    fun retry() {
        observeSettings()
        failedUpdate?.let(::change)
    }

    fun clearCache() = maintain {
        val result = storage.clearCache()
        listOfNotNull(result.metadataFailure?.message, result.imageFailure?.message).joinToString("；")
            .ifEmpty { "节目与图片缓存已清理" }
    }

    fun clearHistory() = maintain {
        history.clear()
        "观看记录已清空"
    }

    private fun maintain(action: suspend () -> String) {
        if (mutableMaintenance.value.busy) return
        mutableMaintenance.value = StorageSettingsState(busy = true)
        viewModelScope.launch {
            try {
                mutableMaintenance.value = StorageSettingsState(message = action())
            } catch (failure: CancellationException) {
                throw failure
            } catch (_: Exception) {
                mutableMaintenance.value = StorageSettingsState(message = "操作失败，请重试")
            }
        }
    }

    fun setTheme(value: ThemeMode) = change { copy(theme = value) }

    fun setDynamicColour(value: Boolean) = change { copy(dynamicColour = value) }

    fun setQuality(value: Quality) = change { copy(initialQuality = value) }

    fun setWifiOnly(value: Boolean) = change { copy(wifiOnlyDownloads = value) }

    private fun change(update: AppSettings.() -> AppSettings) {
        viewModelScope.launch {
            writes.withLock {
                try {
                    repository.update(repository.settings.first().update())
                    failedUpdate = null
                    mutableError.value = null
                    observeSettings()
                } catch (failure: CancellationException) {
                    throw failure
                } catch (_: Exception) {
                    failedUpdate = update
                    mutableError.value = AppError(ErrorKind.Storage, "设置未保存，请重试")
                }
            }
        }
    }
}

internal data class StorageSettingsState(val busy: Boolean = false, val message: String? = null)
