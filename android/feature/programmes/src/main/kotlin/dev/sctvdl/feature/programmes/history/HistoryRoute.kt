package dev.sctvdl.feature.programmes.history

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.sctvdl.domain.history.ViewingTarget

@Composable
fun HistoryRoute(onBack: () -> Unit, onOpen: (ViewingTarget) -> Unit) {
    val model: HistoryViewModel = hiltViewModel()
    val state by model.state.collectAsStateWithLifecycle()
    HistoryScreen(state, onBack, onOpen, model::query, model::remove, model::retry)
}
