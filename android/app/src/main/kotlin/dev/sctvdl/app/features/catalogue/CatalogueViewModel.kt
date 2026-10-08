package dev.sctvdl.app.features.catalogue

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.FavouriteRepository
import dev.sctvdl.domain.ProgrammeRepository
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@HiltViewModel
class CatalogueViewModel @Inject constructor(
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
    private val catalogue = repository.observeProgrammes().onEach { resource ->
        val programmes = resource.data ?: return@onEach
        if (programmes.none { it.id == featuredId.value }) {
            saved["featuredId"] = programmes.randomOrNull()?.id
        }
    }
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

    val state = combine(catalogue, favourites.observeIds(), filters, featuredId) { resource, ids, filters, featuredId ->
        filters.copy(resource = resource, favourites = ids, featuredId = featuredId)
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
        refresh()
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
        val programmes = state.value.resource.data.orEmpty()
        val alternatives = programmes.filterNot { it.id == featuredId.value }
        saved["featuredId"] = alternatives.ifEmpty { programmes }.randomOrNull()?.id
    }
    fun refresh() {
        viewModelScope.launch { repository.refreshProgrammes() }
    }
    fun toggleFavourite(id: String) {
        viewModelScope.launch { favourites.toggle(id) }
    }
}
