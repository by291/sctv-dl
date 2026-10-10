package dev.sctvdl.feature.programmes.presentation

import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.snapshotFlow

// Retain positions, rather than sharing a layout controller between overlapping archive entries.
internal class CatalogueScrollPosition(var index: Int = 0, var offset: Int = 0) {
    companion object {
        val Saver = listSaver<CatalogueScrollPosition, Int>(
            save = { listOf(it.index, it.offset) },
            restore = { CatalogueScrollPosition(it[0], it[1]) }
        )
    }
}

@Composable
internal fun rememberCatalogueScrollState(position: CatalogueScrollPosition?): LazyGridState {
    val state = rememberLazyGridState(position?.index ?: 0, position?.offset ?: 0)
    LaunchedEffect(state, position) {
        if (position != null) {
            snapshotFlow {
                state.firstVisibleItemIndex to state.firstVisibleItemScrollOffset
            }.collect { (index, offset) ->
                position.index = index
                position.offset = offset
            }
        }
    }
    return state
}
