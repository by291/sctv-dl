package dev.sctvdl.feature.programmes.catalogue

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.download.isActive
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.repository.FavouriteRepository
import dev.sctvdl.domain.repository.ProgrammeRepository
import dev.sctvdl.feature.programmes.presentation.AcceptedResourceState
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@HiltViewModel
internal class CatalogueViewModel @Inject constructor(
    private val repository: ProgrammeRepository,
    private val favourites: FavouriteRepository,
    private val saved: SavedStateHandle
) : ViewModel() {
    private val query = saved.getStateFlow("query", "")
    private val byName = saved.getStateFlow("byName", false)

    private val favouritesQuery = saved.getStateFlow("favouritesQuery", "")
    private val favouritesByName = saved.getStateFlow("favouritesByName", false)
    private val favouritesOnly = saved.getStateFlow("favouritesOnly", false)
    private val featuredId = saved.getStateFlow<String?>("featuredId", null)

    private val snapshot = AcceptedResourceState<List<Programme>>()
    private val catalogue = MutableStateFlow(CatalogueUiState())
    private val favouriteState = MutableStateFlow<FavouriteState?>(null)

    private var refreshJob: Job? = null

    private val filters = combine(query, byName, favouritesQuery, favouritesByName, favouritesOnly) {
            query,
            byName,
            favouritesQuery,
            favouritesByName,
            favouritesOnly
        ->
        CatalogueUiState(
            query = if (favouritesOnly) favouritesQuery else query,
            byName = if (favouritesOnly) favouritesByName else byName,
            favouritesOnly = favouritesOnly
        )
    }

    val uiState = combine(catalogue, favouriteState.filterNotNull(), filters, featuredId) {
            catalogue,
            favourites,
            filters,
            featuredId
        ->
        filters.copy(
            resource = catalogue.resource,
            hasUpdate = catalogue.hasUpdate,
            favourites = favourites.current,
            orderingFavourites = favourites.ordering,
            featuredId = featuredId
        )
    }.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        CatalogueUiState(
            query = if (favouritesOnly.value) favouritesQuery.value else query.value,
            byName = if (favouritesOnly.value) favouritesByName.value else byName.value,
            favouritesOnly = favouritesOnly.value,
            featuredId = featuredId.value
        )
    )

    init {
        viewModelScope.launch {
            favourites.observeIds().collect { ids ->
                favouriteState.value = FavouriteState(ids, favouriteState.value?.ordering ?: ids)
            }
        }

        viewModelScope.launch {
            repository.observeProgrammes().collect { resource ->
                snapshot.observe(resource)
                publish()
            }
        }
    }

    fun enter() {
        refresh()
    }

    fun applyUpdates() {
        snapshot.accept()
        publish()
    }

    private fun publish() {
        catalogue.value = CatalogueUiState(resource = snapshot.resource, hasUpdate = snapshot.hasUpdate)

        val programmes = snapshot.resource.data ?: return
        if (programmes.none { it.id == featuredId.value }) {
            saved["featuredId"] = programmes.randomOrNull()?.id
        }
    }

    fun query(value: String) {
        saved[if (favouritesOnly.value) "favouritesQuery" else "query"] = value.take(200)
    }

    fun sort(byName: Boolean) {
        saved[if (favouritesOnly.value) "favouritesByName" else "byName"] = byName
    }

    fun filter(favouritesOnly: Boolean) {
        saved["favouritesOnly"] = favouritesOnly
    }

    fun exploreAnother() {
        val programmes = uiState.value.resource.data.orEmpty()
        val alternatives = programmes.filterNot { it.id == featuredId.value }

        saved["featuredId"] = alternatives.ifEmpty { programmes }.randomOrNull()?.id
    }

    fun refresh() {
        if (refreshJob?.isActive == true) return

        refreshJob = viewModelScope.launch { repository.refreshProgrammes() }
    }

    fun toggleFavourite(id: String) {
        viewModelScope.launch { favourites.toggle(id) }
    }

    // Keep startup favourite priority for this library's lifetime; hearts and favourite membership stay live.
    private data class FavouriteState(val current: Set<String>, val ordering: Set<String>)
}
