package dev.sctvdl.app.navigation

import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.SharedTransitionLayout
import androidx.compose.animation.SharedTransitionScope
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
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
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.rememberDecoratedNavEntries
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.scene.NavigationBackHandler
import androidx.navigation3.scene.Scene
import androidx.navigation3.scene.SinglePaneSceneStrategy
import androidx.navigation3.scene.rememberNavigationEventState
import androidx.navigation3.scene.rememberSceneState
import androidx.navigation3.ui.LocalNavAnimatedContentScope
import androidx.navigation3.ui.NavDisplay
import androidx.navigationevent.NavigationEvent
import androidx.navigationevent.NavigationEventTransitionState
import dev.sctvdl.design.theme.PAGE_TRANSITION_DURATION_MILLIS
import dev.sctvdl.ui.programme.LocalProgrammeCoverAnimationScope
import dev.sctvdl.ui.programme.LocalProgrammeCoverSharedScope
import dev.sctvdl.ui.programme.LocalProgrammeCoverTransitionState
import dev.sctvdl.ui.programme.ProgrammeCoverTransitionState

private const val PRIMARY_DESTINATION_KEY = "dev.sctvdl.app.navigation.primaryDestination"
private const val PRIMARY_NAVIGATION_KEY = "dev.sctvdl.app.navigation.primaryBar"
private const val PRIMARY_EXIT_MILLIS = 90
private const val PRIMARY_ENTER_MILLIS = 160
private const val PRIMARY_TRANSITION_MILLIS = PRIMARY_EXIT_MILLIS + PRIMARY_ENTER_MILLIS
private val LocalNavigationSharedScope = compositionLocalOf<SharedTransitionScope?> { null }
private val LocalNavigationGestureInProgress = compositionLocalOf { false }

private data class PrimaryDestination(val route: AppRoute, val label: String, val icon: ImageVector)

private val PrimaryDestinations = listOf(
    PrimaryDestination(AppRoute.Catalogue, "节目库", Icons.Outlined.LiveTv),
    PrimaryDestination(AppRoute.Downloads, "下载", Icons.Outlined.Download),
    PrimaryDestination(AppRoute.Settings, "设置", Icons.Outlined.Settings)
)

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
    val tabs = PrimaryDestinations.map { it.route }
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
    val density = LocalDensity.current
    val primaryDistance = with(density) { 20.dp.roundToPx() }
    val pageDistance = with(density) { 30.dp.roundToPx() }

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
                            NavEntry(
                                key = route,
                                contentKey = "$index:$route",
                                metadata = mapOf(PRIMARY_DESTINATION_KEY to index)
                            ) {
                                val animationScope = LocalNavAnimatedContentScope.current
                                CompositionLocalProvider(
                                    LocalProgrammeCoverAnimationScope provides animationScope
                                ) {
                                    val destination = it as AppRoute

                                    // Navigation and its reserved space leave with their page, without resizing it first.
                                    Scaffold(bottomBar = {
                                        if (!rail && destination in tabs) {
                                            PrimaryNavigationBar(
                                                sharedScope = requireNotNull(LocalNavigationSharedScope.current),
                                                selected = selected,
                                                onSelect = { selected = it }
                                            )
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
                        PrimaryDestinations.forEachIndexed { index, destination ->
                            NavigationRailItem(selected = selected == index, onClick = {
                                selected = index
                            }, icon = {
                                Icon(destination.icon, null)
                            }, label = {
                                Text(destination.label)
                            }, modifier = Modifier.testTag("tab-${destination.route::class.simpleName}"))
                        }
                    }
                }
                SharedTransitionLayout(Modifier.weight(1f).clipToBounds()) {
                    CompositionLocalProvider(
                        LocalNavigationSharedScope provides this,
                        LocalProgrammeCoverSharedScope provides this,
                        LocalProgrammeCoverTransitionState provides coverTransition
                    ) {
                        val sceneState = rememberSceneState(
                            sceneStrategies = listOf(SinglePaneSceneStrategy()),
                            entries = if (selected == 0) {
                                decoratedStacks[0]
                            } else {
                                decoratedStacks[0] + decoratedStacks[selected]
                            },
                            onBack = back,
                            sharedTransitionScope = this@SharedTransitionLayout
                        )
                        val navigationEventState = rememberNavigationEventState(sceneState)
                        NavigationBackHandler(sceneState, navigationEventState, onBackCompleted = back)

                        CompositionLocalProvider(
                            LocalNavigationGestureInProgress provides
                                (navigationEventState.transitionState !is NavigationEventTransitionState.Idle)
                        ) {
                            NavDisplay(
                                sceneState = sceneState,
                                navigationEventState = navigationEventState,
                                modifier = Modifier.fillMaxSize().clipToBounds(),
                                transitionSpec = { destinationTransition(primaryDistance, pageDistance, pop = false) },
                                popTransitionSpec = {
                                    destinationTransition(primaryDistance, pageDistance, pop = true)
                                },
                                predictivePopTransitionSpec = { edge ->
                                    destinationTransition(primaryDistance, pageDistance, pop = true, edge = edge)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PrimaryNavigationBar(sharedScope: SharedTransitionScope, selected: Int, onSelect: (Int) -> Unit) {
    val animationScope = LocalNavAnimatedContentScope.current
    val lifecycleState by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    // NavDisplay resumes the settled entry after cancellation; its child visibility transition can remain unfinished.
    val interactive = lifecycleState == Lifecycle.State.RESUMED && !LocalNavigationGestureInProgress.current
    val semantics = if (interactive) Modifier else Modifier.clearAndSetSemantics { }

    // Equal shared bounds keep one bar at rest across primary entries while each Scaffold retains its own spacing.
    val modifier = with(sharedScope) {
        Modifier.sharedElement(
            rememberSharedContentState(PRIMARY_NAVIGATION_KEY),
            animatedVisibilityScope = animationScope,
            boundsTransform = { _, _ -> tween(PRIMARY_TRANSITION_MILLIS) },
            zIndexInOverlay = 1f
        ).then(semantics)
    }
    NavigationBar(modifier = modifier, containerColor = MaterialTheme.colorScheme.surface) {
        PrimaryDestinations.forEachIndexed { index, destination ->
            NavigationBarItem(
                selected = selected == index,
                // Keep the shared visual unchanged while both entries wait for the native transition to settle.
                onClick = { if (interactive) onSelect(index) },
                icon = { Icon(destination.icon, null) },
                label = { Text(destination.label) },
                modifier = Modifier.testTag("tab-${destination.route::class.simpleName}")
            )
        }
    }
}

private fun <T : Any> AnimatedContentTransitionScope<Scene<T>>.destinationTransition(
    primaryDistance: Int,
    pageDistance: Int,
    pop: Boolean,
    edge: Int? = null
): ContentTransform {
    val changesPrimaryDestination = initialState.metadata[PRIMARY_DESTINATION_KEY] !=
        targetState.metadata[PRIMARY_DESTINATION_KEY]
    val direction = when {
        edge == NavigationEvent.EDGE_RIGHT -> 1
        edge == NavigationEvent.EDGE_LEFT -> -1
        changesPrimaryDestination -> {
            val from = initialState.metadata[PRIMARY_DESTINATION_KEY] as Int
            val to = targetState.metadata[PRIMARY_DESTINATION_KEY] as Int
            if (to > from) 1 else -1
        }
        pop -> -1
        else -> 1
    }
    if (changesPrimaryDestination) {
        val enter = slideInHorizontally(
            tween(PRIMARY_ENTER_MILLIS, PRIMARY_EXIT_MILLIS, LinearOutSlowInEasing)
        ) { direction * primaryDistance } + fadeIn(
            tween(PRIMARY_ENTER_MILLIS, PRIMARY_EXIT_MILLIS, LinearOutSlowInEasing)
        )
        val exit = slideOutHorizontally(tween(PRIMARY_EXIT_MILLIS, easing = FastOutLinearInEasing)) {
            -direction * primaryDistance
        } + fadeOut(tween(PRIMARY_EXIT_MILLIS, easing = FastOutLinearInEasing))
        return enter togetherWith exit
    }

    val fadeOutMillis = (PAGE_TRANSITION_DURATION_MILLIS * 0.35f).toInt()
    val enter = slideInHorizontally(tween(PAGE_TRANSITION_DURATION_MILLIS, easing = FastOutSlowInEasing)) {
        direction * pageDistance
    } + fadeIn(tween(PAGE_TRANSITION_DURATION_MILLIS - fadeOutMillis, fadeOutMillis, LinearOutSlowInEasing))
    val exit = slideOutHorizontally(tween(PAGE_TRANSITION_DURATION_MILLIS, easing = FastOutSlowInEasing)) {
        -direction * pageDistance
    } + fadeOut(tween(fadeOutMillis, easing = FastOutLinearInEasing))

    return enter togetherWith exit
}
