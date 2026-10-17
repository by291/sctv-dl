package dev.sctvdl.app

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import dev.sctvdl.app.navigation.AppDestinations
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.app.platform.ActivityPlaybackHost
import dev.sctvdl.app.platform.rememberDownloadFileConsentRequester
import dev.sctvdl.feature.player.PlaybackSelection
import dev.sctvdl.feature.programmes.presentation.rememberProgrammeLibraryState
import dev.sctvdl.ui.theme.SctvAppTheme
import kotlinx.coroutines.delay

// Keep the original SavedStateHandle owner key across package/type moves.
private const val APP_VIEW_MODEL_KEY =
    "androidx.lifecycle.ViewModelProvider.DefaultKey:dev.sctvdl.app.features.downloads.DownloadCoordinatorViewModel"

@Composable
internal fun SctvApp(activity: MainActivity) {
    val model: AppViewModel = hiltViewModel(key = APP_VIEW_MODEL_KEY)
    val state by model.uiState.collectAsStateWithLifecycle()
    val downloadsRequest by activity.downloadsRequest.collectAsStateWithLifecycle()

    var playbackSelection by remember { mutableStateOf<PlaybackSelection?>(null) }

    val fileConsent = rememberDownloadFileConsentRequester(activity.downloadFileConsents)
    val library = rememberProgrammeLibraryState()
    val host = remember(activity) { ActivityPlaybackHost(activity) }
    val snackbar = remember { SnackbarHostState() }
    val lifecycle = LocalLifecycleOwner.current.lifecycle

    LaunchedEffect(lifecycle, model) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                model.reconcile()
                delay(2_000)
            }
        }
    }

    LaunchedEffect(state.downloadMessage) {
        state.downloadMessage?.let {
            snackbar.showSnackbar(it.text)
            model.acknowledgeMessage(it.id)
        }
    }

    SctvAppTheme(state.settings) {
        val darkIcons = MaterialTheme.colorScheme.surface.luminance() > 0.5f

        SideEffect { activity.setSystemBarIcons(darkIcons) }

        Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
            AppNavigationShell(activity::pausePlayerForDismissal, downloadsRequest) { route, navigator, bottomPadding ->
                AppDestinations(
                    route, navigator, library, state.settings, host,
                    { requests ->
                        activity.requestDownloadNotifications()
                        model.enqueue(requests)
                    }, {
                        snackbar.showSnackbar(it)
                    }, playbackSelection, {
                        playbackSelection = it
                    }, bottomContentPadding = bottomPadding, requestFileConsent = fileConsent
                )
            }
            SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).padding(bottom = 88.dp))
        }
    }
}
