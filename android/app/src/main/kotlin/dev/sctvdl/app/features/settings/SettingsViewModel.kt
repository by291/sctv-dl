package dev.sctvdl.app.features.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.Quality
import dev.sctvdl.domain.SettingsRepository
import dev.sctvdl.domain.ThemeMode
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

@HiltViewModel
class SettingsViewModel @Inject constructor(private val repository: SettingsRepository) : ViewModel() {
    val settings = repository.settings.stateIn(
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
