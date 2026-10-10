package dev.sctvdl.feature.player.local

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.sctvdl.feature.player.PlaybackHost
import dev.sctvdl.feature.player.PlayerScreen

// Keep the original SavedStateHandle owner key across package/type moves.
private const val LOCAL_PLAYER_VIEW_MODEL_KEY =
    "androidx.lifecycle.ViewModelProvider.DefaultKey:dev.sctvdl.app.features.player.LocalPlayerViewModel"

@Composable
fun LocalPlayerRoute(taskId: String, host: PlaybackHost, onBack: () -> Unit) {
    val model: LocalPlayerViewModel = hiltViewModel(key = LOCAL_PLAYER_VIEW_MODEL_KEY)
    val state by model.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(taskId) { model.open(taskId) }

    PlayerScreen(state, onBack, model::retry, model::savePosition, {}, false, host)
}
