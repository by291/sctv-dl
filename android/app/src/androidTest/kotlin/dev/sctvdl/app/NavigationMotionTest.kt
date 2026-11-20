package dev.sctvdl.app

import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.Density
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.app.navigation.AppNavigator
import dev.sctvdl.app.navigation.AppRoute
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

private const val CATALOGUE_VIEWPORT = "catalogue-viewport"
private const val ARCHIVE_INSET = "archive-inset"
private const val TRANSITION_SAMPLE_FRAMES = 10

class NavigationMotionTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private lateinit var navigator: AppNavigator

    @Test fun catalogueDoesNotExpandIntoTheNavigationBarDuringArchiveEntry() {
        showRoutes(ThemeMode.Light, fontScale = 1f)
        val initialHeight = requireNotNull(heightOf(CATALOGUE_VIEWPORT))
        assertTrue(initialHeight > 0)

        val frames = sampleTransition { navigator.open(AppRoute.Archive("one")) }

        assertTrue("Archive entry must retain the outgoing catalogue", frames.isNotEmpty())
        for (frame in frames) {
            assertEquals("Catalogue resized on entry", initialHeight, frame.catalogueHeight)
        }
        compose.onNodeWithTag(CATALOGUE_VIEWPORT).assertDoesNotExist()
    }

    @Test fun archiveKeepsItsGestureInsetWhileReturningToBottomNavigation() {
        showRoutes(ThemeMode.Dark, fontScale = 2f)
        compose.runOnIdle { navigator.open(AppRoute.Archive("one")) }
        val initialInset = requireNotNull(heightOf(ARCHIVE_INSET))
        assertTrue("The archive fixture needs a bottom system bar inset", initialInset > 0)

        val frames = sampleTransition { navigator.back() }

        assertTrue("Archive exit must retain the outgoing archive", frames.isNotEmpty())
        for (frame in frames) {
            assertEquals("Archive inset changed on exit", initialInset, frame.archiveInset)
        }
        compose.onNodeWithTag(ARCHIVE_INSET).assertDoesNotExist()
    }

    private fun showRoutes(theme: ThemeMode, fontScale: Float) {
        compose.activityRule.scenario.onActivity { it.enableEdgeToEdge() }
        compose.setContent {
            val density = Density(LocalDensity.current.density, fontScale)
            CompositionLocalProvider(LocalDensity provides density) {
                SctvAppTheme(AppSettings(theme = theme)) {
                    AppNavigationShell { route, navigation, bottomPadding ->
                        navigator = navigation
                        when (route) {
                            AppRoute.Catalogue -> {
                                val viewport = Modifier.fillMaxSize().testTag(CATALOGUE_VIEWPORT)
                                Box(viewport) { Text("Catalogue") }
                            }
                            is AppRoute.Archive -> Box(Modifier.fillMaxSize()) {
                                Spacer(Modifier.height(bottomPadding).testTag(ARCHIVE_INSET))
                                Text("Archive")
                            }
                            else -> Unit
                        }
                    }
                }
            }
        }
    }

    private fun sampleTransition(start: () -> Unit): List<TransitionFrame> {
        compose.mainClock.autoAdvance = false
        try {
            compose.runOnIdle(start)
            return buildList {
                repeat(TRANSITION_SAMPLE_FRAMES) {
                    compose.mainClock.advanceTimeByFrame()
                    val catalogueHeight = heightOf(CATALOGUE_VIEWPORT)
                    val archiveInset = heightOf(ARCHIVE_INSET)

                    // Both destinations must still be mounted during the sampled frame.
                    if (catalogueHeight != null && archiveInset != null) {
                        add(TransitionFrame(catalogueHeight, archiveInset))
                    }
                }
            }
        } finally {
            compose.mainClock.autoAdvance = true
        }
    }

    private fun heightOf(tag: String): Int? {
        val nodes = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes()
        return nodes.singleOrNull()?.size?.height
    }

    private data class TransitionFrame(val catalogueHeight: Int, val archiveInset: Int)
}
