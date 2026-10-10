package dev.sctvdl.app.navigation

import androidx.activity.compose.BackHandler
import androidx.compose.animation.SharedTransitionLayout
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
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
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.rememberDecoratedNavEntries
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.LocalNavAnimatedContentScope
import androidx.navigation3.ui.NavDisplay
import dev.sctvdl.ui.programme.LocalProgrammeCoverAnimationScope
import dev.sctvdl.ui.programme.LocalProgrammeCoverSharedScope
import dev.sctvdl.ui.programme.LocalProgrammeCoverTransitionState
import dev.sctvdl.ui.programme.ProgrammeCoverTransitionState

@Composable
internal fun AppNavigationShell(
    onBackCommitted: () -> Unit = {},
    downloadsRequest: Int = 0,
    content: @Composable (route: AppRoute, navigator: AppNavigator, bottomContentPadding: Dp) -> Unit
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
    val labels = listOf("节目库", "下载", "设置")
    val icons =
        listOf(Icons.Outlined.LiveTv, Icons.Outlined.Download, Icons.Outlined.Settings)

    BoxWithConstraints {
        val rail = maxWidth >= 600.dp
        Scaffold(
            contentWindowInsets = WindowInsets.systemBars.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal)
        ) { padding ->
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
                                    val destination = it as AppRoute

                                    // Navigation and its reserved space leave with their page, without resizing it first.
                                    Scaffold(bottomBar = {
                                        if (!rail && destination in tabs) {
                                            NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                                                tabs.forEachIndexed { tabIndex, route ->
                                                    NavigationBarItem(
                                                        selected = selected == tabIndex,
                                                        onClick = { selected = tabIndex },
                                                        icon = { Icon(icons[tabIndex], null) },
                                                        label = { Text(labels[tabIndex]) },
                                                        modifier = Modifier.testTag("tab-${route::class.simpleName}")
                                                    )
                                                }
                                            }
                                        }
                                    }) { destinationPadding ->
                                        val scrollsBehindNavigation = destination is AppRoute.Archive ||
                                            (destination == AppRoute.Catalogue && rail)
                                        val bottomPadding = destinationPadding.calculateBottomPadding()

                                        // A bottom bar bounds the library; beside a rail, lists own the system inset.
                                        Box(
                                            Modifier.fillMaxSize().padding(
                                                bottom = if (scrollsBehindNavigation) 0.dp else bottomPadding
                                            ).consumeWindowInsets(destinationPadding)
                                        ) {
                                            content(
                                                destination,
                                                navigator,
                                                if (scrollsBehindNavigation) bottomPadding else 0.dp
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    )
                }
            }
            val direction = LocalLayoutDirection.current

            Row(
                Modifier.fillMaxSize().padding(
                    start = padding.calculateStartPadding(direction),
                    top = padding.calculateTopPadding(),
                    end = padding.calculateEndPadding(direction)
                ).consumeWindowInsets(padding)
            ) {
                if (rail && !isPlayer) {
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
