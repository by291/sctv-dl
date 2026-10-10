package dev.sctvdl.feature.player

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.sctvdl.domain.download.DownloadRequest

// Keep the original SavedStateHandle owner key across package/type moves.
private const val ONLINE_PLAYER_VIEW_MODEL_KEY =
    "androidx.lifecycle.ViewModelProvider.DefaultKey:dev.sctvdl.app.features.player.PlayerViewModel"

@Composable
fun PlayerRoute(
    programmeId: String,
    dateId: String,
    contentId: String,
    selection: PlaybackSelection?,
    wifiOnly: Boolean,
    host: PlaybackHost,
    onBack: () -> Unit,
    onDownload: (List<DownloadRequest>) -> Unit
) {
    val model: OnlinePlayerViewModel = hiltViewModel(key = ONLINE_PLAYER_VIEW_MODEL_KEY)
    val state by model.uiState.collectAsStateWithLifecycle()
    LaunchedEffect(programmeId, dateId, contentId) { model.open(programmeId, dateId, contentId, selection) }
    PlayerScreen(state, onBack, model::retry, model::savePosition, onDownload, wifiOnly, host)
}
