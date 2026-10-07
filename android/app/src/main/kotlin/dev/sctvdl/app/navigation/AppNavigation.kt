package dev.sctvdl.app.navigation

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.LiveTv
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.rememberDecoratedNavEntries
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay

class AppNavigator(val open: (AppRoute) -> Unit, val back: () -> Unit)

@Composable
fun AppNavigationShell(
    onBackCommitted: () -> Unit = {},
    downloadsRequest: Int = 0,
    content: @Composable (AppRoute, AppNavigator) -> Unit
) {
    val catalogue = rememberNavBackStack(AppRoute.Catalogue)
    val favourites = rememberNavBackStack(AppRoute.Favourites)
    val downloads = rememberNavBackStack(AppRoute.Downloads)
    val stacks = listOf(catalogue, favourites, downloads)
    var selected by rememberSaveable { mutableIntStateOf(0) }
    LaunchedEffect(downloadsRequest) {
        if (downloadsRequest > 0) {
            onBackCommitted()
            selected = 2
        }
    }
    val stack = stacks[selected]
    val current = stack.last() as AppRoute
    val isPlayer = current is AppRoute.Playback || current is AppRoute.LocalPlayback
    val back = {
        if (stack.size > 1) {
            onBackCommitted()
            stack.removeLastOrNull()
            Unit
        }
    }
    val navigator = AppNavigator({ route ->
        if (stack.last() != route) {
            if (stack.last() is AppRoute.Archive &&
                route is AppRoute.Archive
            ) {
                stack[stack.lastIndex] = route
            } else {
                stack.add(route)
            }
        }
    }, back)
    val decoratedStacks = stacks.mapIndexed { index, backStack ->
        key(index) {
            rememberDecoratedNavEntries(
                backStack = backStack,
                entryDecorators = listOf(
                    rememberSaveableStateHolderNavEntryDecorator(),
                    rememberViewModelStoreNavEntryDecorator()
                ),
                entryProvider = { route ->
                    NavEntry(key = route, contentKey = "$index:$route") {
                        content(it as AppRoute, navigator)
                    }
                }
            )
        }
    }
    val tabs = listOf(AppRoute.Catalogue, AppRoute.Favourites, AppRoute.Downloads)
    val labels = listOf("栏目", "收藏", "下载")
    val icons =
        listOf(Icons.Outlined.LiveTv, Icons.Outlined.FavoriteBorder, Icons.Outlined.Download)

    BoxWithConstraints {
        val rail = maxWidth >= 600.dp && !isPlayer
        Scaffold(bottomBar = {
            if (!rail &&
                !isPlayer
            ) {
                NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                    tabs.forEachIndexed { index, route ->
                        NavigationBarItem(selected = selected == index, onClick = {
                            selected = index
                        }, icon = {
                            Icon(icons[index], null)
                        }, label = {
                            Text(labels[index])
                        }, modifier = Modifier.testTag("tab-${route::class.simpleName}"))
                    }
                }
            }
        }) { padding ->
            Row(Modifier.fillMaxSize().padding(padding)) {
                if (rail) {
                    NavigationRail(containerColor = MaterialTheme.colorScheme.surface) {
                        Spacer(Modifier.height(24.dp))
                        tabs.forEachIndexed { index, route ->
                            NavigationRailItem(selected = selected == index, onClick = {
                                selected = index
                            }, icon = {
                                Icon(icons[index], null)
                            }, label = {
                                Text(labels[index])
                            }, modifier = Modifier.testTag("tab-${route::class.simpleName}"))
                        }
                        Spacer(Modifier.weight(1f))
                        IconButton(onClick = {
                            navigator.open(AppRoute.Settings)
                        }) { Icon(Icons.Outlined.Settings, "设置") }
                    }
                }
                NavDisplay(
                    entries = decoratedStacks[selected],
                    onBack = back,
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}
