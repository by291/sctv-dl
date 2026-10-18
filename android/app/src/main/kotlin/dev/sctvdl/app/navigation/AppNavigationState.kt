package dev.sctvdl.app.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableIntState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.navigation3.runtime.NavBackStack
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.rememberNavBackStack

/** Each primary destination keeps its own entries; callbacks always resolve the currently selected stack. */
internal class AppNavigationState(
    val stacks: List<NavBackStack<NavKey>>,
    private val selection: MutableIntState,
    private val onBackCommitted: () -> Unit
) {
    val selected: Int get() = selection.intValue
    val current: AppRoute get() = stacks[selected].last() as AppRoute
    val navigator = AppNavigator(::open, ::back)

    fun select(index: Int) {
        selection.intValue = index
    }

    fun showDownloads() {
        onBackCommitted()
        val downloads = stacks[1]
        while (downloads.size > 1) downloads.removeLastOrNull()
        select(1)
    }

    private fun back() {
        val activeStack = stacks[selected]
        if (activeStack.size > 1) {
            onBackCommitted()
            activeStack.removeLastOrNull()
        } else if (selected != 0) {
            select(0)
        }
    }

    private fun open(route: AppRoute) {
        val activeStack = stacks[selected]
        val primaryIndex = stacks.indexOfFirst { it.first() == route }
        if (primaryIndex >= 0) {
            onBackCommitted()
            select(primaryIndex)
        } else if (activeStack.last() != route) {
            if (activeStack.last() is AppRoute.Archive && route is AppRoute.Archive) {
                activeStack[activeStack.lastIndex] = route
            } else {
                activeStack.add(route)
            }
        }
    }
}

@Composable
internal fun rememberAppNavigation(downloadsRequest: Int, onBackCommitted: () -> Unit): AppNavigationState {
    val catalogue = rememberNavBackStack(AppRoute.Catalogue)
    val downloads = rememberNavBackStack(AppRoute.Downloads)
    val settings = rememberNavBackStack(AppRoute.Settings)
    val selection = rememberSaveable { mutableIntStateOf(0) }
    val currentBackCommitted by rememberUpdatedState(onBackCommitted)
    val navigation = remember {
        AppNavigationState(listOf(catalogue, downloads, settings), selection) { currentBackCommitted() }
    }

    LaunchedEffect(downloadsRequest) {
        if (downloadsRequest > 0) navigation.showDownloads()
    }
    return navigation
}
