package dev.sctvdl.feature.programmes

import androidx.compose.animation.SharedTransitionLayout
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.rememberDecoratedNavEntries
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.LocalNavAnimatedContentScope
import androidx.navigation3.ui.NavDisplay
import dev.sctvdl.ui.programme.LocalProgrammeCoverAnimationScope
import dev.sctvdl.ui.programme.LocalProgrammeCoverSharedScope
import dev.sctvdl.ui.programme.LocalProgrammeCoverTransitionState
import dev.sctvdl.ui.programme.ProgrammeCoverTransitionState

internal sealed interface ProgrammeTestRoute : NavKey {
    data object Catalogue : ProgrammeTestRoute

    data class Archive(val programmeId: String) : ProgrammeTestRoute
}

internal class ProgrammeTestNavigator(val open: (ProgrammeTestRoute) -> Unit, val back: () -> Unit)

@Composable
internal fun ProgrammeNavigationFixture(content: @Composable (ProgrammeTestRoute, ProgrammeTestNavigator) -> Unit) {
    val stack = remember { mutableStateListOf<ProgrammeTestRoute>(ProgrammeTestRoute.Catalogue) }
    val transition = remember { ProgrammeCoverTransitionState() }
    val back: () -> Unit = { if (stack.size > 1) stack.removeLastOrNull() }
    val navigator = ProgrammeTestNavigator({ stack.add(it) }, back)
    // Keep the selected cover and list state when the catalogue leaves, as the app shell does.
    val entries = rememberDecoratedNavEntries(
        backStack = stack,
        entryDecorators = listOf(rememberSaveableStateHolderNavEntryDecorator()),
        entryProvider = { route ->
            NavEntry(route, contentKey = route.toString()) {
                CompositionLocalProvider(
                    LocalProgrammeCoverAnimationScope provides LocalNavAnimatedContentScope.current
                ) { content(it, navigator) }
            }
        }
    )
    SharedTransitionLayout {
        CompositionLocalProvider(
            LocalProgrammeCoverSharedScope provides this,
            LocalProgrammeCoverTransitionState provides transition
        ) {
            NavDisplay(
                entries = entries,
                onBack = back,
                sharedTransitionScope = this@SharedTransitionLayout
            )
        }
    }
}
