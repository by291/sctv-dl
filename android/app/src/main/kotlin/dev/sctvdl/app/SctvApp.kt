package dev.sctvdl.app

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import dev.sctvdl.app.features.archive.ArchiveScreen
import dev.sctvdl.app.features.archive.ArchiveViewModel
import dev.sctvdl.app.features.catalogue.CatalogueScreen
import dev.sctvdl.app.features.catalogue.CatalogueViewModel
import dev.sctvdl.app.features.downloads.DownloadCoordinatorViewModel
import dev.sctvdl.app.features.downloads.DownloadsScreen
import dev.sctvdl.app.features.downloads.DownloadsViewModel
import dev.sctvdl.app.features.downloads.openDownloadFile
import dev.sctvdl.app.features.downloads.openSystemDownloads
import dev.sctvdl.app.features.player.LocalPlayerViewModel
import dev.sctvdl.app.features.player.PlaybackSelection
import dev.sctvdl.app.features.player.PlayerScreen
import dev.sctvdl.app.features.player.PlayerViewModel
import dev.sctvdl.app.features.player.mainActivity
import dev.sctvdl.app.features.settings.SettingsScreen
import dev.sctvdl.app.features.settings.SettingsViewModel
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.app.navigation.AppRoute
import dev.sctvdl.design.SctvTheme
import kotlinx.coroutines.delay

@Composable
fun SctvApp() {
    val settingsModel: SettingsViewModel = hiltViewModel()
    val catalogueModel: CatalogueViewModel = hiltViewModel()
    val settings by settingsModel.settings.collectAsStateWithLifecycle()
    val catalogue by catalogueModel.state.collectAsStateWithLifecycle()
    val activity = LocalContext.current.mainActivity()
    val context = LocalContext.current
    val downloadsRequest by (
        activity?.downloadsRequest
            ?: remember { kotlinx.coroutines.flow.MutableStateFlow(0) }
        ).collectAsStateWithLifecycle()
    val coordinator: DownloadCoordinatorViewModel = hiltViewModel()
    val message by coordinator.message.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    var playbackSelection by remember { mutableStateOf<PlaybackSelection?>(null) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                coordinator.reconcile()
                delay(2_000)
            }
        }
    }
    LaunchedEffect(message) {
        message?.let {
            snackbar.showSnackbar(it)
            coordinator.consumeMessage()
        }
    }
    SctvTheme(settings) {
        val darkIcons = MaterialTheme.colorScheme.surface.luminance() > 0.5f
        SideEffect { activity?.setSystemBarIcons(darkIcons) }
        Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
            AppNavigationShell(
                onBackCommitted = { activity?.pausePlayerForDismissal() },
                downloadsRequest = downloadsRequest
            ) {
                    route,
                    navigator
                ->
                when (route) {
                    AppRoute.Settings -> SettingsScreen(
                        settings,
                        settingsModel::setTheme,
                        settingsModel::setDynamicColour,
                        settingsModel::setQuality,
                        settingsModel::setWifiOnly
                    )
                    AppRoute.Catalogue -> {
                        LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { catalogueModel.enter() }
                        CatalogueScreen(
                            catalogue,
                            catalogue.favouritesOnly,
                            catalogueModel::query,
                            catalogueModel::sort,
                            catalogueModel::refresh,
                            catalogueModel::toggleFavourite,
                            { navigator.open(AppRoute.Archive(it)) },
                            catalogueModel::filter,
                            catalogueModel::exploreAnother,
                            onApplyUpdates = catalogueModel::applyUpdates
                        )
                    }
                    is AppRoute.Archive -> {
                        // Keep the accepted catalogue artwork available before the entry becomes resumed.
                        val entryProgramme = remember(route.programmeId) {
                            catalogue.resource.data.orEmpty().firstOrNull { it.id == route.programmeId }
                        }
                        val archiveModel: ArchiveViewModel =
                            hiltViewModel(key = "archive-${route.programmeId}")
                        val archive by archiveModel.state.collectAsStateWithLifecycle()
                        val displayedArchive = if (archive.programme == null) {
                            archive.copy(
                                programme = entryProgramme,
                                favourite = route.programmeId in catalogue.favourites
                            )
                        } else {
                            archive
                        }
                        LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
                            archiveModel.open(route.programmeId, entryProgramme)
                        }
                        BoxWithConstraints {
                            val expanded = maxWidth >= 840.dp
                            Row {
                                if (expanded) {
                                    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { catalogueModel.enter() }
                                    Box(Modifier.width(340.dp)) {
                                        CatalogueScreen(
                                            catalogue,
                                            catalogue.favouritesOnly,
                                            catalogueModel::query,
                                            catalogueModel::sort,
                                            catalogueModel::refresh,
                                            catalogueModel::toggleFavourite,
                                            { navigator.open(AppRoute.Archive(it)) },
                                            catalogueModel::filter,
                                            catalogueModel::exploreAnother,
                                            embedded = true,
                                            onApplyUpdates = catalogueModel::applyUpdates
                                        )
                                    }
                                    VerticalDivider()
                                }
                                Box(Modifier.weight(1f)) {
                                    ArchiveScreen(
                                        displayedArchive,
                                        settings.wifiOnlyDownloads,
                                        navigator.back,
                                        archiveModel::selectDate,
                                        archiveModel::refresh,
                                        archiveModel::toggleFavourite,
                                        { content ->
                                            archive.date?.let {
                                                playbackSelection = PlaybackSelection(
                                                    route.programmeId,
                                                    it.id,
                                                    content,
                                                    archive.programme?.name ?: "节目",
                                                    it.date
                                                )
                                                navigator.open(
                                                    AppRoute.Playback(
                                                        route.programmeId,
                                                        it.id,
                                                        content.id
                                                    )
                                                )
                                            }
                                        },
                                        archiveModel::beginSelection,
                                        archiveModel::selectAll,
                                        archiveModel::selectFullEpisodes,
                                        archiveModel::toggleContent,
                                        archiveModel::exitSelection,
                                        coordinator::enqueue,
                                        onApplyUpdates = archiveModel::applyUpdates
                                    )
                                }
                            }
                        }
                    }
                    AppRoute.Downloads -> {
                        val model: DownloadsViewModel = hiltViewModel()
                        val state by model.state.collectAsStateWithLifecycle()
                        val taskMessage by model.message.collectAsStateWithLifecycle()
                        LaunchedEffect(taskMessage) {
                            taskMessage?.let {
                                snackbar.showSnackbar(it)
                                model.consumeMessage()
                            }
                        }
                        DownloadsScreen(
                            state,
                            model::tab,
                            model::cancel,
                            model::retry,
                            model::remove,
                            { navigator.open(AppRoute.LocalPlayback(it)) },

                            { task ->
                                model.withFile(task.id) {
                                    openDownloadFile(
                                        context,
                                        it,
                                        true,
                                        model::showMessage
                                    )
                                }
                            },

                            { task ->
                                model.withFile(task.id) {
                                    openDownloadFile(
                                        context,
                                        it,
                                        false,
                                        model::showMessage
                                    )
                                }
                            },

                            { openSystemDownloads(context, model::showMessage) }
                        )
                    }
                    is AppRoute.Playback -> {
                        val playerModel: PlayerViewModel = hiltViewModel()
                        val player by playerModel.state.collectAsStateWithLifecycle()
                        LaunchedEffect(route) {
                            playerModel.open(
                                route.programmeId,
                                route.dateId,
                                route.contentId,
                                playbackSelection
                            )
                        }
                        PlayerScreen(
                            player,
                            navigator.back,
                            playerModel::retry,
                            playerModel::savePosition,
                            coordinator::enqueue,
                            settings.wifiOnlyDownloads
                        )
                    }
                    is AppRoute.LocalPlayback -> {
                        val model: LocalPlayerViewModel = hiltViewModel()
                        val state by model.state.collectAsStateWithLifecycle()
                        LaunchedEffect(route.taskId) { model.open(route.taskId) }
                        PlayerScreen(
                            state,
                            navigator.back,
                            model::retry,
                            model::savePosition,
                            {},
                            settings.wifiOnlyDownloads
                        )
                    }
                }
            }
            SnackbarHost(
                snackbar,
                Modifier.align(androidx.compose.ui.Alignment.BottomCenter).padding(bottom = 88.dp)
            )
        }
    }
}
