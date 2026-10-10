package dev.sctvdl.feature.programmes

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
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.feature.programmes.catalogue.CatalogueScreen
import dev.sctvdl.feature.programmes.catalogue.CatalogueUiState
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class AdaptiveCatalogueTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun twoHundredPercentTextUsesOneColumnAndKeepsActionsReachable() {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                SctvAppTheme(AppSettings(theme = ThemeMode.Dark)) {
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
}
