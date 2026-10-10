package dev.sctvdl.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.repository.SettingsRepository
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

@HiltViewModel
internal class SettingsViewModel @Inject constructor(private val repository: SettingsRepository) : ViewModel() {
    val uiState = repository.settings.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        AppSettings()
    )

    private val writes = Mutex()

    fun setTheme(value: ThemeMode) = change { copy(theme = value) }

    fun setDynamicColour(value: Boolean) = change { copy(dynamicColour = value) }

    fun setQuality(value: Quality) = change { copy(initialQuality = value) }

    fun setWifiOnly(value: Boolean) = change { copy(wifiOnlyDownloads = value) }

    private fun change(update: AppSettings.() -> AppSettings) {
        viewModelScope.launch {
            writes.withLock { repository.update(repository.settings.first().update()) }
        }
    }
}
