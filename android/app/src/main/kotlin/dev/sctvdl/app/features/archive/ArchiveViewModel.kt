package dev.sctvdl.app.features.archive

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.app.features.PresentedResource
import dev.sctvdl.domain.BroadcastDate
import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.DownloadRequest
import dev.sctvdl.domain.FavouriteRepository
import dev.sctvdl.domain.Programme
import dev.sctvdl.domain.ProgrammeContent
import dev.sctvdl.domain.ProgrammeRepository
import dev.sctvdl.domain.Quality
import dev.sctvdl.domain.videoVariants
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

@HiltViewModel
class ArchiveViewModel @Inject constructor(
    private val repository: ProgrammeRepository,
    private val favourites: FavouriteRepository,
    private val saved: SavedStateHandle
) : ViewModel() {
    private val mutableState = MutableStateFlow(ArchiveUiState())
    val state = mutableState.asStateFlow()
    private var datesJob: Job? = null
    private var contentsJob: Job? = null
    private var datesRefreshJob: Job? = null
    private var contentsRefreshJob: Job? = null
    private var datesSnapshot = PresentedResource<List<BroadcastDate>>()
    private var contentsSnapshot = PresentedResource<List<ProgrammeContent>>()
    private var programmes = emptyList<Programme>()
    private var favouriteIds = emptySet<String>()
    private var requestedDateId: String? = saved["dateId"]
    private val restoredProgrammeId: String? = saved["programmeId"]
    private var restoredSelection = saved.get<ArrayList<String>>("selectedIds").orEmpty().toSet()
    private var restoredSelectionMode = saved.get<Boolean>("selectionMode") ?: false
    private var started = false

    init {
        viewModelScope.launch {
            combine(repository.observeProgrammes(), favourites.observeIds()) { catalogue, ids ->
                catalogue.data.orEmpty() to ids
            }.collect { (rows, ids) ->
                programmes = rows
                favouriteIds = ids
                mutableState.update {
                    it.copy(
                        programme = it.programme ?: rows.firstOrNull { row ->
                            row.id == it.programmeId
                        },
                        favourite = it.programmeId in ids
                    )
                }
                publishUpdateFlag()
            }
        }
    }

    fun open(programmeId: String, initialProgramme: Programme? = null) {
        if (started && state.value.programmeId == programmeId) {
            refresh()
            return
        }
        started = true
        datesJob?.cancel()
        contentsJob?.cancel()
        datesRefreshJob?.cancel()
        contentsRefreshJob?.cancel()
        datesSnapshot = PresentedResource()
        contentsSnapshot = PresentedResource()
        if (restoredProgrammeId != programmeId) {
            requestedDateId = null
            restoredSelection = emptySet()
            restoredSelectionMode = false
        }
        saved["programmeId"] = programmeId
        mutableState.value =
            ArchiveUiState(
                programmeId = programmeId,
                programme = initialProgramme?.takeIf { it.id == programmeId }
                    ?: programmes.firstOrNull { it.id == programmeId },
                favourite = programmeId in favouriteIds
            )

        datesJob = viewModelScope.launch {
            repository.observeDates(programmeId).collect { resource ->
                if (state.value.programmeId != programmeId) return@collect
                presentDates(datesSnapshot.observe(resource))
            }
        }
        refreshDates(programmeId)
    }

    private fun presentDates(resource: CachedResource<List<BroadcastDate>>) {
        mutableState.update { it.copy(dates = resource) }
        val dates = resource.data
        if (dates != null) {
            val selected = dates.firstOrNull { it.id == (state.value.date?.id ?: requestedDateId) }
                ?: dates.firstOrNull()
            if (selected == null) {
                contentsJob?.cancel()
                contentsRefreshJob?.cancel()
                contentsSnapshot = PresentedResource()
                mutableState.update {
                    it.copy(date = null, contents = CachedResource(), selectedIds = emptySet(), selectionMode = false)
                }
                persistSelection()
            } else if (selected.id != state.value.date?.id) {
                selectDate(selected)
            } else {
                mutableState.update { it.copy(date = selected) }
            }
        }
        publishUpdateFlag()
    }

    fun selectDate(date: BroadcastDate) {
        val current = state.value
        if (current.dates.data.orEmpty().none { it.id == date.id } ||
            current.date?.id == date.id
        ) {
            return
        }
        contentsJob?.cancel()
        contentsRefreshJob?.cancel()
        contentsSnapshot = PresentedResource()
        val restore = date.id == requestedDateId
        mutableState.update {
            it.copy(
                date = date,
                contents = CachedResource(),
                selectedIds = if (restore) restoredSelection else emptySet(),
                selectionMode =
                restore && restoredSelectionMode
            )
        }
        requestedDateId = date.id
        restoredSelection = emptySet()
        restoredSelectionMode = false
        saved["dateId"] = date.id
        persistSelection()
        val programmeId = current.programmeId

        contentsJob = viewModelScope.launch {
            repository.observeContents(programmeId, date.id).collect { resource ->
                if (state.value.programmeId != programmeId ||
                    state.value.date?.id != date.id
                ) {
                    return@collect
                }
                presentContents(contentsSnapshot.observe(resource))
            }
        }
        refreshContents(programmeId, date.id)
        publishUpdateFlag()
    }

    private fun presentContents(resource: CachedResource<List<ProgrammeContent>>) {
        mutableState.update {
            it.copy(
                contents = resource,
                selectedIds = resource.data?.let { rows -> it.selectedIds.intersect(selectableIds(rows)) }
                    ?: it.selectedIds
            )
        }
        persistSelection()
        publishUpdateFlag()
    }

    fun applyUpdates() {
        if (state.value.selectionMode) return
        val dateId = state.value.date?.id
        mutableState.update { current ->
            current.copy(programme = programmes.firstOrNull { it.id == current.programmeId } ?: current.programme)
        }
        presentDates(datesSnapshot.accept())
        // A changed date owns a new content snapshot and request, never the previous date's pending rows.
        if (dateId == state.value.date?.id) presentContents(contentsSnapshot.accept())
    }

    private fun publishUpdateFlag() {
        mutableState.update { current ->
            val latestProgramme = programmes.firstOrNull { it.id == current.programmeId }
            current.copy(
                hasUpdate = datesSnapshot.hasUpdate || contentsSnapshot.hasUpdate ||
                    (latestProgramme != null && latestProgramme != current.programme)
            )
        }
    }

    fun refresh() {
        val current = state.value
        if (current.programmeId.isBlank()) return
        refreshDates(current.programmeId)
        current.date?.let { refreshContents(current.programmeId, it.id) }
    }

    private fun refreshDates(programmeId: String) {
        if (datesRefreshJob?.isActive == true) return
        datesRefreshJob = viewModelScope.launch { repository.refreshDates(programmeId) }
    }

    private fun refreshContents(programmeId: String, dateId: String) {
        if (contentsRefreshJob?.isActive == true) return
        contentsRefreshJob = viewModelScope.launch { repository.refreshContents(programmeId, dateId) }
    }

    fun toggleFavourite() {
        viewModelScope.launch { favourites.toggle(state.value.programmeId) }
    }
    fun beginSelection() {
        mutableState.update { it.copy(selectionMode = true) }
        persistSelection()
    }
    fun selectAll() {
        mutableState.update {
            it.copy(selectionMode = true, selectedIds = selectableIds(it.contents.data.orEmpty()))
        }
        persistSelection()
    }
    fun selectFullEpisodes() {
        mutableState.update {
            it.copy(selectionMode = true, selectedIds = selectableIds(it.fullEpisodes))
        }
        persistSelection()
    }

    fun toggleContent(id: String) {
        if (id !in selectableIds(state.value.contents.data.orEmpty())) return
        mutableState.update {
            it.copy(
                selectionMode = true,
                selectedIds = if (id in it.selectedIds) {
                    it.selectedIds - id
                } else {
                    it.selectedIds + id
                }
            )
        }
        persistSelection()
    }

    fun exitSelection() {
        mutableState.update { it.copy(selectionMode = false, selectedIds = emptySet()) }
        persistSelection()
    }

    fun downloadRequests(quality: Quality, wifiOnly: Boolean): List<DownloadRequest> {
        val current = state.value
        val date = current.date ?: return emptyList()
        return current.contents.data.orEmpty().filter {
            it.id in current.selectedIds &&
                videoVariants(it).isNotEmpty()
        }.map { DownloadRequest(current.programme?.name ?: "节目", date.date, it, quality, wifiOnly) }
    }

    private fun persistSelection() {
        saved["selectedIds"] = ArrayList(state.value.selectedIds)
        saved["selectionMode"] = state.value.selectionMode
    }
}
