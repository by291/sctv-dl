package dev.sctvdl.app.navigation

import androidx.activity.compose.BackHandler
import androidx.compose.animation.SharedTransitionLayout
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.LiveTv
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
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
import androidx.navigation3.ui.LocalNavAnimatedContentScope
import androidx.navigation3.ui.NavDisplay
import dev.sctvdl.design.LocalProgrammeCoverAnimationScope
import dev.sctvdl.design.LocalProgrammeCoverSharedScope
import dev.sctvdl.design.LocalProgrammeCoverTransitionState
import dev.sctvdl.design.ProgrammeCoverTransitionState

class AppNavigator(val open: (AppRoute) -> Unit, val back: () -> Unit)

@Composable
fun AppNavigationShell(
    onBackCommitted: () -> Unit = {},
    downloadsRequest: Int = 0,
    content: @Composable (AppRoute, AppNavigator) -> Unit
) {
    val coverTransition = remember { ProgrammeCoverTransitionState() }
    val catalogue = rememberNavBackStack(AppRoute.Catalogue)
    val downloads = rememberNavBackStack(AppRoute.Downloads)
    val settings = rememberNavBackStack(AppRoute.Settings)
    val stacks = listOf(catalogue, downloads, settings)
    val tabs = listOf(AppRoute.Catalogue, AppRoute.Downloads, AppRoute.Settings)
    var selected by rememberSaveable { mutableIntStateOf(0) }
    LaunchedEffect(downloadsRequest) {
        if (downloadsRequest > 0) {
            onBackCommitted()
            while (downloads.size > 1) downloads.removeLastOrNull()
            selected = 1
        }
    }
    val stack = stacks[selected]
    val current = stack.last() as AppRoute
    val isPlayer = current is AppRoute.Playback || current is AppRoute.LocalPlayback
    val back: () -> Unit = {
        if (stack.size > 1) {
            onBackCommitted()
            stack.removeLastOrNull()
        } else if (selected != 0) {
            selected = 0
        }
    }
    BackHandler(stack.size == 1 && selected != 0) { selected = 0 }
    val navigator = AppNavigator({ route ->
        val primaryIndex = tabs.indexOf(route)
        if (primaryIndex >= 0) {
            onBackCommitted()
            selected = primaryIndex
        } else if (stack.last() != route) {
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
                        CompositionLocalProvider(
                            LocalProgrammeCoverAnimationScope provides LocalNavAnimatedContentScope.current
                        ) {
                            content(it as AppRoute, navigator)
                        }
                    }
                }
            )
        }
    }
    val labels = listOf("节目库", "下载", "设置")
    val icons =
        listOf(Icons.Outlined.LiveTv, Icons.Outlined.Download, Icons.Outlined.Settings)

    BoxWithConstraints {
        val rail = maxWidth >= 600.dp && !isPlayer
        val primary = current in tabs
        Scaffold(bottomBar = {
            if (!rail && primary) {
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
            Row(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)) {
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
                    }
                }
                SharedTransitionLayout(Modifier.weight(1f)) {
                    CompositionLocalProvider(
                        LocalProgrammeCoverSharedScope provides this,
                        LocalProgrammeCoverTransitionState provides coverTransition
                    ) {
                        NavDisplay(
                            entries = decoratedStacks[selected],
                            onBack = back,
                            sharedTransitionScope = this@SharedTransitionLayout
                        )
                    }
                }
            }
        }
    }
}
