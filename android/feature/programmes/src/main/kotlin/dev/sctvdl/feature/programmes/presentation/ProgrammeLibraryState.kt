package dev.sctvdl.feature.programmes.presentation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.sctvdl.feature.programmes.catalogue.CatalogueUiState
import dev.sctvdl.feature.programmes.catalogue.CatalogueViewModel

// Keep the original SavedStateHandle owner key across package/type moves.
private const val CATALOGUE_VIEW_MODEL_KEY =
    "androidx.lifecycle.ViewModelProvider.DefaultKey:dev.sctvdl.app.features.catalogue.CatalogueViewModel"

/** Retains accepted catalogue data and the library pane position across programme and player destinations. */
class ProgrammeLibraryState internal constructor(
    internal val model: CatalogueViewModel,
    internal val state: State<CatalogueUiState>,
    internal val cataloguePanePosition: CatalogueScrollPosition = CatalogueScrollPosition()
)

@Composable
fun rememberProgrammeLibraryState(): ProgrammeLibraryState {
    val model: CatalogueViewModel = hiltViewModel(key = CATALOGUE_VIEW_MODEL_KEY)
    val state = model.uiState.collectAsStateWithLifecycle()

    val cataloguePanePosition = rememberSaveable(saver = CatalogueScrollPosition.Saver) { CatalogueScrollPosition() }

    return remember(model, cataloguePanePosition) {
        ProgrammeLibraryState(model, state, cataloguePanePosition)
    }
}
