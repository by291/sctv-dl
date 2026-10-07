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
    val state = combine(repository.observeProgrammes(), favourites.observeIds(), query, byName) {
            resource,
            ids,
            query,
            sort
        ->
        CatalogueUiState(resource, ids, query, sort)
    }.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        CatalogueUiState(query = query.value, byName = byName.value)
    )

    init {
        refresh()
    }

    fun query(value: String) {
        saved["query"] = value.take(200)
    }
    fun sort(byName: Boolean) {
        saved["byName"] = byName
    }
    fun refresh() {
        viewModelScope.launch { repository.refreshProgrammes() }
    }
    fun toggleFavourite(id: String) {
        viewModelScope.launch { favourites.toggle(id) }
    }
}
