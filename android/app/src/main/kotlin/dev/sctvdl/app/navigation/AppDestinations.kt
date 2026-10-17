package dev.sctvdl.app.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.downloads.DownloadsRoute
import dev.sctvdl.feature.player.PlaybackHost
import dev.sctvdl.feature.player.PlaybackSelection
import dev.sctvdl.feature.player.PlayerRoute
import dev.sctvdl.feature.player.local.LocalPlayerRoute
import dev.sctvdl.feature.programmes.archive.ArchiveRoute
import dev.sctvdl.feature.programmes.catalogue.CatalogueRoute
import dev.sctvdl.feature.programmes.presentation.ProgrammeLibraryState
import dev.sctvdl.feature.settings.SettingsRoute

@Composable
internal fun AppDestinations(
    route: AppRoute,
    navigator: AppNavigator,
    library: ProgrammeLibraryState,
    settings: AppSettings,
    host: PlaybackHost,
    onDownload: (List<DownloadRequest>) -> Unit,
    onMessage: suspend (String) -> Unit,
    playbackSelection: PlaybackSelection?,
    onPlaybackSelection: (PlaybackSelection) -> Unit,
    bottomContentPadding: Dp = 0.dp,
    requestFileConsent: suspend (String) -> Boolean = { false }
) {
    when (route) {
        AppRoute.Settings -> SettingsRoute()
        AppRoute.Catalogue -> CatalogueRoute(
            library,
            { navigator.open(AppRoute.Archive(it)) },
            bottomContentPadding = bottomContentPadding
        )
        is AppRoute.Archive -> ArchiveRoute(
            route.programmeId,
            library,
            settings.wifiOnlyDownloads,
            navigator.back,
            { navigator.open(AppRoute.Archive(it)) },
            { selection ->
                onPlaybackSelection(
                    PlaybackSelection(
                        selection.programmeId,
                        selection.dateId,
                        selection.content,
                        selection.programmeName,
                        selection.broadcastDate
                    )
                )
                navigator.open(AppRoute.Playback(selection.programmeId, selection.dateId, selection.content.id))
            },
            onDownload,
            bottomContentPadding = bottomContentPadding
        )
        AppRoute.Downloads -> DownloadsRoute({
            navigator.open(AppRoute.LocalPlayback(it))
        }, onMessage, requestFileConsent)
        is AppRoute.Playback -> PlayerRoute(
            route.programmeId,
            route.dateId,
            route.contentId,
            playbackSelection,
            settings.wifiOnlyDownloads,
            host,
            navigator.back,
            onDownload
        )
        is AppRoute.LocalPlayback -> LocalPlayerRoute(route.taskId, host, navigator.back)
    }
}
