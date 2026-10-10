package dev.sctvdl.feature.programmes.archive

import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.programme.isFullEpisode
import dev.sctvdl.domain.programme.sortContentsByPublicationTime

internal data class ArchiveUiState(
    val programmeId: String = "",
    val programme: Programme? = null,
    val favourite: Boolean = false,
    val dates: CachedResource<List<BroadcastDate>> = CachedResource(),
    val date: BroadcastDate? = null,
    val contents: CachedResource<List<ProgrammeContent>> = CachedResource(),
    val selectionMode: Boolean = false,
    val selectedIds: Set<String> = emptySet(),
    val hasUpdate: Boolean = false,
    val clipSortAscending: Boolean = true
) {
    val fullEpisodes: List<ProgrammeContent> get() = contents.data.orEmpty().filter { item ->
        date?.let { isFullEpisode(item, programme?.name.orEmpty(), it.date) } == true
    }
    val clips: List<ProgrammeContent> get() = sortContentsByPublicationTime(
        contents.data.orEmpty().filterNot { item -> item in fullEpisodes },
        ascending = clipSortAscending
    )
}
