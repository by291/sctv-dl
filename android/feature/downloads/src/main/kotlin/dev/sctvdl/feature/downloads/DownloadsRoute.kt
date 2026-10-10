package dev.sctvdl.feature.downloads

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.sctvdl.feature.downloads.platform.openDownloadFile
import dev.sctvdl.feature.downloads.platform.openSystemDownloads

// Keep the original SavedStateHandle owner key across package/type moves.
private const val DOWNLOADS_VIEW_MODEL_KEY =
    "androidx.lifecycle.ViewModelProvider.DefaultKey:dev.sctvdl.app.features.downloads.DownloadsViewModel"

@Composable
fun DownloadsRoute(onLocalPlayback: (String) -> Unit, onMessage: suspend (String) -> Unit) {
    val model: DownloadsViewModel = hiltViewModel(key = DOWNLOADS_VIEW_MODEL_KEY)
    val state by model.uiState.collectAsStateWithLifecycle()
    val message by model.message.collectAsStateWithLifecycle()
    val context = LocalContext.current
    LaunchedEffect(message) {
        message?.let {
            onMessage(it)
            model.consumeMessage()
        }
    }
    DownloadsScreen(
        state,
        model::tab,
        model::cancel,
        model::retry,
        model::remove,
        onLocalPlayback,
        { task -> model.withFile(task.id) { openDownloadFile(context, it, true, model::showMessage) } },
        { task -> model.withFile(task.id) { openDownloadFile(context, it, false, model::showMessage) } },
        { openSystemDownloads(context, model::showMessage) }
    )
}
