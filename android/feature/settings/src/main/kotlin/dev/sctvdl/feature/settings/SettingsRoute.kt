package dev.sctvdl.feature.settings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun SettingsRoute() {
    val model: SettingsViewModel = hiltViewModel()
    val settings by model.uiState.collectAsStateWithLifecycle()

    SettingsScreen(settings, model::setTheme, model::setDynamicColour, model::setQuality, model::setWifiOnly)
}
