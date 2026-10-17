package dev.sctvdl.feature.downloads

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.sctvdl.feature.downloads.platform.openDownloadFile
import dev.sctvdl.feature.downloads.platform.openSystemDownloads
import kotlinx.coroutines.launch

// Keep the original SavedStateHandle owner key across package/type moves.
private const val DOWNLOADS_VIEW_MODEL_KEY =
    "androidx.lifecycle.ViewModelProvider.DefaultKey:dev.sctvdl.app.features.downloads.DownloadsViewModel"

@Composable
fun DownloadsRoute(
    onLocalPlayback: (String) -> Unit,
    onMessage: suspend (String) -> Unit,
    requestFileConsent: suspend (String) -> Boolean = { false }
) {
    val model: DownloadsViewModel = hiltViewModel(key = DOWNLOADS_VIEW_MODEL_KEY)
    val state by model.uiState.collectAsStateWithLifecycle()
    val message by model.message.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

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
        { openSystemDownloads(context, model::showMessage) },
        model::beginSelection, model::exitSelection, model::selectAll, model::toggle,
        onReload = model::reload,
        onAction = { action, targets -> scope.launch { model.perform(action, targets, requestFileConsent) } }
    )
}
