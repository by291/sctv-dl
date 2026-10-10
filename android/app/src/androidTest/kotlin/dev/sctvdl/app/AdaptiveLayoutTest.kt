package dev.sctvdl.app

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.Density
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class AdaptiveLayoutTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun wideWindowPlacesPrimaryDestinationsInALeftRail() {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, 1f)) {
                SctvAppTheme(AppSettings()) { AppNavigationShell { _, _, _ -> } }
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
