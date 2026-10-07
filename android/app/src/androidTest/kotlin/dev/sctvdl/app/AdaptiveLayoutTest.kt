package dev.sctvdl.app

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.unit.Density
import dev.sctvdl.app.features.catalogue.CatalogueScreen
import dev.sctvdl.app.features.catalogue.CatalogueUiState
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.design.SctvTheme
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.Programme
import dev.sctvdl.domain.ThemeMode
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class AdaptiveLayoutTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun twoHundredPercentTextUsesOneColumnAndKeepsActionsReachable() {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                SctvTheme(AppSettings(theme = ThemeMode.Dark)) {
                    CatalogueScreen(
                        CatalogueUiState(
                            resource = CachedResource(
                                data = listOf(
                                    Programme("first", "四川新闻联播与天府大地的每一份精彩故事", null, 0),
                                    Programme("second", "今日视点", null, 1)
                                )
                            )
                        ),
                        false,
                        {},
                        {},
                        {},
                        {},
                        {},
                        {}
                    )
                }
            }
        }
        val first = compose.onNodeWithTag("programme-first").fetchSemanticsNode().boundsInRoot
        compose.onNodeWithTag("catalogue-grid").performScrollToNode(hasTestTag("programme-second"))
        val second = compose.onNodeWithTag("programme-second").fetchSemanticsNode().boundsInRoot
        assertTrue(
            "Large-text catalogue cards should use the same column",
            kotlin.math.abs(first.left - second.left) < 2
        )
        compose.onNodeWithContentDescription("收藏今日视点").assertIsDisplayed().assertHasClickAction()
    }

    @Test
    fun wideWindowPlacesPrimaryDestinationsInALeftRail() {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, 1f)) {
                SctvTheme(AppSettings()) { AppNavigationShell { _, _ -> } }
            }
        }
        val catalogue = compose.onNodeWithTag("tab-Catalogue").fetchSemanticsNode().boundsInRoot
        val downloads = compose.onNodeWithTag("tab-Downloads").fetchSemanticsNode().boundsInRoot
        assertTrue(
            "Rail destinations must share a horizontal position",
            kotlin.math.abs(catalogue.center.x - downloads.center.x) < 2
        )
        assertTrue("Rail destinations must stack vertically", downloads.top > catalogue.bottom)
        compose.onNodeWithTag("tab-Downloads").assertIsDisplayed().assertHasClickAction()
    }
}
