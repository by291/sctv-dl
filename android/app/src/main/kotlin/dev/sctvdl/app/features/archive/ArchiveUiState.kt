package dev.sctvdl.app.features.archive

import dev.sctvdl.domain.BroadcastDate
import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.Programme
import dev.sctvdl.domain.ProgrammeContent
import dev.sctvdl.domain.isFullEpisode

data class ArchiveUiState(
    val programmeId: String = "",
    val programme: Programme? = null,
    val favourite: Boolean = false,
    val dates: CachedResource<List<BroadcastDate>> = CachedResource(),
    val date: BroadcastDate? = null,
    val contents: CachedResource<List<ProgrammeContent>> = CachedResource(),
    val selectionMode: Boolean = false,
    val selectedIds: Set<String> = emptySet(),
    val hasUpdate: Boolean = false
) {
    val fullEpisodes: List<ProgrammeContent> get() = contents.data.orEmpty().filter { item ->
        date?.let { isFullEpisode(item, programme?.name.orEmpty(), it.date) } == true
    }
    val clips: List<ProgrammeContent> get() = contents.data.orEmpty().filterNot { item ->
        item in fullEpisodes
    }
}
