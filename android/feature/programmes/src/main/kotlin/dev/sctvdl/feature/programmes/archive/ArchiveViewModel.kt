package dev.sctvdl.feature.programmes.archive

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.repository.FavouriteRepository
import dev.sctvdl.domain.repository.ProgrammeRepository
import dev.sctvdl.feature.programmes.presentation.AcceptedResourceState
import dev.sctvdl.feature.programmes.presentation.FavouriteState
import dev.sctvdl.feature.programmes.presentation.onReadFailure
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

@HiltViewModel
internal class ArchiveViewModel @Inject constructor(
    private val repository: ProgrammeRepository,
    favourites: FavouriteRepository,
    private val saved: SavedStateHandle
) : ViewModel() {
    private val favouriteActions = FavouriteState(favourites, viewModelScope)

    private val mutableState = MutableStateFlow(ArchiveUiState())
    val uiState = mutableState.asStateFlow()

    private var contextJob: Job? = null
    private var datesJob: Job? = null
    private var contentsJob: Job? = null
    private var datesRefreshJob: Job? = null
    private var contentsRefreshJob: Job? = null

    private var datesSnapshot = AcceptedResourceState<List<BroadcastDate>>()
    private var contentsSnapshot = AcceptedResourceState<List<ProgrammeContent>>()

    private var programmes = emptyList<Programme>()
    private var favouriteIds = emptySet<String>()

    private var requestedDateId: String? = saved["dateId"]
    private val restoredProgrammeId: String? = saved["programmeId"]
    private var restoredSelection = saved.get<ArrayList<String>>("selectedIds").orEmpty().toSet()
    private var restoredSelectionMode = saved.get<Boolean>("selectionMode") ?: false
    private var started = false

    init {
        viewModelScope.launch {
            favouriteActions.error.collect { error -> mutableState.update { it.copy(favouriteError = error) } }
        }

        viewModelScope.launch {
            favouriteActions.ids.filterNotNull().collect { ids ->
                favouriteIds = ids
                mutableState.update { it.copy(favourite = it.programmeId in ids) }
            }
        }
        observeProgrammeContext()
    }

    private fun observeProgrammeContext() {
        if (contextJob?.isActive == true) return
        contextJob = viewModelScope.launch {
            repository.observeProgrammes().onReadFailure { error ->
                mutableState.update { it.copy(contextError = error) }
            }.collect { catalogue ->
                programmes = catalogue.data.orEmpty()
                mutableState.update { current ->
                    current.copy(
                        programme = current.programme ?: programmes.firstOrNull { it.id == current.programmeId },
                        contextError = null
                    )
                }
                publishUpdateFlag()
            }
        }
    }

    fun open(programmeId: String, initialProgramme: Programme? = null) {
        if (started && uiState.value.programmeId == programmeId) {
            refresh()
            return
        }

        started = true
        datesJob?.cancel()
        contentsJob?.cancel()
        datesRefreshJob?.cancel()
        contentsRefreshJob?.cancel()

        datesSnapshot = AcceptedResourceState()
        contentsSnapshot = AcceptedResourceState()

        // Saved date and batch selections belong only to the archive they were captured from.
        if (restoredProgrammeId != programmeId) {
            requestedDateId = null
            restoredSelection = emptySet()
            restoredSelectionMode = false
        }

        val clipSortAscending = if (saved.get<String>("programmeId") == programmeId) {
            saved.get<Boolean>("clipSortAscending") ?: true
        } else {
            true
        }

        saved["programmeId"] = programmeId
        saved["clipSortAscending"] = clipSortAscending
        mutableState.value =
            ArchiveUiState(
                programmeId = programmeId,
                programme = initialProgramme?.takeIf { it.id == programmeId }
                    ?: programmes.firstOrNull { it.id == programmeId },
                favourite = programmeId in favouriteIds,
                clipSortAscending = clipSortAscending,
                favouriteError = favouriteActions.error.value,
                contextError = uiState.value.contextError
            )

        observeDates(programmeId)
        refreshDates(programmeId)
    }

    private fun observeDates(programmeId: String) {
        if (datesJob?.isActive == true) return
        datesJob = viewModelScope.launch {
            repository.observeDates(programmeId).onReadFailure { error ->
                if (uiState.value.programmeId == programmeId) {
                    datesSnapshot.fail(error)
                    presentDates(datesSnapshot.resource)
                }
            }.collect { resource ->
                // Cancellation can race a final emission from the previous archive observer.
                if (uiState.value.programmeId != programmeId) return@collect

                presentDates(datesSnapshot.observe(resource))
            }
        }
    }

    private fun presentDates(resource: CachedResource<List<BroadcastDate>>) {
        mutableState.update { it.copy(dates = resource) }

        val dates = resource.data
        if (dates != null) {
            val selected = dates.firstOrNull { it.id == (uiState.value.date?.id ?: requestedDateId) }
                ?: dates.firstOrNull()
            if (selected == null) {
                contentsJob?.cancel()
                contentsRefreshJob?.cancel()
                contentsSnapshot = AcceptedResourceState()
                mutableState.update {
                    it.copy(date = null, contents = CachedResource(), selectedIds = emptySet(), selectionMode = false)
                }
                persistSelection()
            } else if (selected.id != uiState.value.date?.id) {
                selectDate(selected)
            } else {
                mutableState.update { it.copy(date = selected) }
            }
        }
        publishUpdateFlag()
    }

    fun selectDate(date: BroadcastDate) {
        val current = uiState.value
        if (current.dates.data.orEmpty().none { it.id == date.id } ||
            current.date?.id == date.id
        ) {
            return
        }

        contentsJob?.cancel()
        contentsRefreshJob?.cancel()
        contentsSnapshot = AcceptedResourceState()

        val restore = date.id == requestedDateId
        mutableState.update {
            it.copy(
                date = date,
                contents = CachedResource(),
                selectedIds = if (restore) restoredSelection else emptySet(),
                selectionMode = restore && restoredSelectionMode
            )
        }

        requestedDateId = date.id
        restoredSelection = emptySet()
        restoredSelectionMode = false
        saved["dateId"] = date.id
        persistSelection()

        val programmeId = current.programmeId

        observeContents(programmeId, date.id)
        refreshContents(programmeId, date.id)
        publishUpdateFlag()
    }

    private fun observeContents(programmeId: String, dateId: String) {
        if (contentsJob?.isActive == true) return
        contentsJob = viewModelScope.launch {
            repository.observeContents(programmeId, dateId).onReadFailure { error ->
                if (uiState.value.programmeId == programmeId && uiState.value.date?.id == dateId) {
                    contentsSnapshot.fail(error)
                    presentContents(contentsSnapshot.resource)
                }
            }.collect { resource ->
                // Both identities must still match before an old request can publish its rows.
                if (uiState.value.programmeId != programmeId ||
                    uiState.value.date?.id != dateId
                ) {
                    return@collect
                }

                presentContents(contentsSnapshot.observe(resource))
            }
        }
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
        // Accepting new rows during batch selection would change the items under the user's checkboxes.
        if (uiState.value.selectionMode) return

        val dateId = uiState.value.date?.id
        mutableState.update { current ->
            current.copy(programme = programmes.firstOrNull { it.id == current.programmeId } ?: current.programme)
        }
        presentDates(datesSnapshot.accept())

        // A changed date owns a new content snapshot and request, never the previous date's pending rows.
        if (dateId == uiState.value.date?.id) presentContents(contentsSnapshot.accept())
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
        val current = uiState.value
        if (current.programmeId.isBlank()) return

        observeProgrammeContext()
        observeDates(current.programmeId)
        refreshDates(current.programmeId)
        current.date?.let {
            observeContents(current.programmeId, it.id)
            refreshContents(current.programmeId, it.id)
        }
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
        favouriteActions.toggle(uiState.value.programmeId)
    }

    fun retryFavourites() = favouriteActions.retry()

    fun toggleClipSort() {
        if (uiState.value.selectionMode) return

        mutableState.update { it.copy(clipSortAscending = !it.clipSortAscending) }
        saved["clipSortAscending"] = uiState.value.clipSortAscending
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
        if (id !in selectableIds(uiState.value.contents.data.orEmpty())) return

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

    private fun persistSelection() {
        saved["selectedIds"] = ArrayList(uiState.value.selectedIds)
        saved["selectionMode"] = uiState.value.selectionMode
    }
}
