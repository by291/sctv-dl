package dev.sctvdl.app.features.archive

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.BroadcastDate
import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.DownloadRequest
import dev.sctvdl.domain.FavouriteRepository
import dev.sctvdl.domain.Programme
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
                        programme = rows.firstOrNull { row ->
                            row.id == it.programmeId
                        },
                        favourite = it.programmeId in ids
                    )
                }
            }
        }
    }

    fun open(programmeId: String) {
        if (started && state.value.programmeId == programmeId) return
        started = true
        datesJob?.cancel()
        contentsJob?.cancel()
        if (restoredProgrammeId != programmeId) {
            requestedDateId = null
            restoredSelection = emptySet()
            restoredSelectionMode = false
        }
        saved["programmeId"] = programmeId
        mutableState.value =
            ArchiveUiState(
                programmeId = programmeId,
                programme = programmes.firstOrNull {
                    it.id == programmeId
                },
                favourite = programmeId in favouriteIds
            )

        datesJob = viewModelScope.launch {
            launch { repository.refreshDates(programmeId) }
            repository.observeDates(programmeId).collect { resource ->
                if (state.value.programmeId != programmeId) return@collect
                mutableState.update { it.copy(dates = resource) }
                val dates = resource.data ?: return@collect
                val selected =
                    dates.firstOrNull { it.id == (state.value.date?.id ?: requestedDateId) }
                        ?: dates.firstOrNull()
                if (selected == null) {
                    contentsJob?.cancel()
                    mutableState.update {
                        it.copy(
                            date = null,
                            contents = CachedResource(),
                            selectedIds = emptySet(),
                            selectionMode = false
                        )
                    }
                    persistSelection()
                } else if (selected.id != state.value.date?.id) {
                    selectDate(selected)
                }
            }
        }
    }

    fun selectDate(date: BroadcastDate) {
        val current = state.value
        if (current.dates.data.orEmpty().none { it.id == date.id } ||
            current.date?.id == date.id
        ) {
            return
        }
        contentsJob?.cancel()
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
            launch { repository.refreshContents(programmeId, date.id) }
            repository.observeContents(programmeId, date.id).collect { resource ->
                if (state.value.programmeId != programmeId ||
                    state.value.date?.id != date.id
                ) {
                    return@collect
                }
                val rows = resource.data
                mutableState.update {
                    it.copy(
                        contents = resource,
                        selectedIds = if (rows != null) {
                            it.selectedIds.intersect(selectableIds(rows))
                        } else {
                            it.selectedIds
                        }
                    )
                }
                persistSelection()
            }
        }
    }

    fun refresh() {
        val current = state.value
        viewModelScope.launch {
            launch { repository.refreshDates(current.programmeId) }
            current.date?.let { repository.refreshContents(current.programmeId, it.id) }
        }
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
