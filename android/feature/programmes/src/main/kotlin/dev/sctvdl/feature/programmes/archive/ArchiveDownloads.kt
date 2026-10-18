package dev.sctvdl.feature.programmes.archive

import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.videoVariants
import dev.sctvdl.domain.programme.ProgrammeSelection

/** Uses only accepted rows, so pending refreshes cannot change a confirmed download or its history identity. */
internal fun archiveDownloadRequests(
    state: ArchiveUiState,
    selectedIds: Set<String>,
    quality: Quality,
    wifiOnly: Boolean
): List<DownloadRequest> {
    val date = state.date ?: return emptyList()
    val programme = state.programme?.takeIf { it.id == state.programmeId }
    val selected = state.contents.data.orEmpty().filter { it.id in selectedIds && videoVariants(it).isNotEmpty() }

    return selected.map { content ->
        DownloadRequest(
            programmeName = programme?.name ?: "节目",
            broadcastDate = date.date,
            content = content,
            requestedQuality = quality,
            wifiOnly = wifiOnly,
            selection = programme?.let { ProgrammeSelection(it, date, content) }
        )
    }
}
