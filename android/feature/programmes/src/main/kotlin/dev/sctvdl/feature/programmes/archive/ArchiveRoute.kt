package dev.sctvdl.feature.programmes.archive

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.width
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.feature.programmes.catalogue.CatalogueRoute
import dev.sctvdl.feature.programmes.presentation.ProgrammeLibraryState

@Composable
fun ArchiveRoute(
    programmeId: String,
    library: ProgrammeLibraryState,
    wifiOnly: Boolean,
    onBack: () -> Unit,
    onOpenProgramme: (String) -> Unit,
    onPlay: (ArchivePlaybackSelection) -> Unit,
    onDownload: (List<DownloadRequest>) -> Unit
) {
    // Capture accepted artwork before the entry is resumed; pending metadata must not replace it.
    val entryProgramme = remember(programmeId) {
        library.state.value.resource.data.orEmpty().firstOrNull { it.id == programmeId }
    }
    val model: ArchiveViewModel = hiltViewModel(key = "archive-$programmeId")
    val archive by model.uiState.collectAsStateWithLifecycle()

    val displayed = if (archive.programme == null) {
        archive.copy(programme = entryProgramme, favourite = programmeId in library.state.value.favourites)
    } else {
        archive
    }

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { model.open(programmeId, entryProgramme) }

    BoxWithConstraints {
        val expanded = maxWidth >= 840.dp

        Row {
            if (expanded) {
                Box(Modifier.width(340.dp)) { CatalogueRoute(library, onOpenProgramme, embedded = true) }
                VerticalDivider()
            }
            Box(Modifier.weight(1f)) {
                ArchiveScreen(
                    displayed,
                    wifiOnly,
                    onBack,
                    model::selectDate,
                    model::refresh,
                    model::toggleFavourite,
                    { content ->
                        archive.date?.let { date ->
                            onPlay(
                                ArchivePlaybackSelection(
                                    programmeId,
                                    date.id,
                                    content,
                                    archive.programme?.name ?: "节目",
                                    date.date
                                )
                            )
                        }
                    },
                    model::beginSelection,
                    model::selectAll,
                    model::selectFullEpisodes,
                    model::toggleContent,
                    model::exitSelection,
                    onDownload,
                    onApplyUpdates = model::applyUpdates,
                    onToggleClipSort = model::toggleClipSort
                )
            }
        }
    }
}
