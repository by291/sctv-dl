package dev.sctvdl.feature.programmes.catalogue

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import dev.sctvdl.feature.programmes.presentation.ProgrammeLibraryState
import dev.sctvdl.feature.programmes.presentation.rememberCatalogueScrollState

@Composable
fun CatalogueRoute(
    library: ProgrammeLibraryState,
    onOpenProgramme: (String) -> Unit,
    embedded: Boolean = false,
    bottomContentPadding: Dp = 0.dp,
    onHistory: (() -> Unit)? = null
) {
    val model = library.model
    val state = library.state.value
    val catalogueScroll = rememberCatalogueScrollState(if (embedded) library.cataloguePanePosition else null)

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { model.enter() }

    CatalogueScreen(
        state,
        state.favouritesOnly,
        model::query,
        model::sort,
        model::refresh,
        model::toggleFavourite,
        onOpenProgramme,
        model::filter,
        model::exploreAnother,
        embedded = embedded,
        onApplyUpdates = model::applyUpdates,
        catalogueScroll = catalogueScroll,
        bottomContentPadding = bottomContentPadding,
        onHistory = onHistory
    )
}
