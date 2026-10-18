package dev.sctvdl.feature.settings

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.ui.theme.SctvAppTheme
import kotlin.math.roundToInt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class SettingsToolbarColourTest {
    @get:Rule val compose = createComposeRule()

    @Test fun toolbarAndPageKeepTheSameColourDuringThemeChangesAndInterruption() {
        var settings by mutableStateOf(AppSettings(theme = ThemeMode.Light))
        compose.setContent {
            SctvAppTheme(settings) {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
                    SettingsScreen(settings, {}, {}, {}, {})
                }
            }
        }
        val light = assertMatchingSurfaces()
        compose.mainClock.autoAdvance = false

        compose.runOnIdle { settings = settings.copy(theme = ThemeMode.Dark) }
        compose.mainClock.advanceTimeByFrame()
        repeat(3) {
            compose.mainClock.advanceTimeBy(64)
            assertMatchingSurfaces()
        }
        compose.mainClock.advanceTimeBy(320)
        val dark = assertMatchingSurfaces()
        assertTrue("The screen must actually change appearance", dark.luminance() < light.luminance())

        compose.runOnIdle { settings = settings.copy(theme = ThemeMode.Light) }
        compose.mainClock.advanceTimeByFrame()
        compose.mainClock.advanceTimeBy(96)
        val interrupted = assertMatchingSurfaces()
        assertTrue("Check a rendered intermediate frame", interrupted != light && interrupted != dark)

        compose.runOnIdle { settings = settings.copy(theme = ThemeMode.Dark) }
        compose.mainClock.advanceTimeByFrame()
        repeat(3) {
            compose.mainClock.advanceTimeBy(64)
            assertMatchingSurfaces()
        }
        compose.mainClock.advanceTimeBy(320)
        assertEquals(dark, assertMatchingSurfaces())
    }

    private fun assertMatchingSurfaces(): Color {
        val title = compose.onNodeWithText("设置").fetchSemanticsNode().boundsInRoot
        val pixels = compose.onRoot().captureToImage().toPixelMap()
        // Both samples avoid text and cards: the toolbar's trailing edge and the page's side gutter.
        val toolbar = pixels[pixels.width - 2, title.center.y.roundToInt()]
        val page = pixels[2, pixels.height - 2]
        assertEquals("Toolbar red must follow the page in this frame", page.red, toolbar.red, 1f / 255f)
        assertEquals("Toolbar green must follow the page in this frame", page.green, toolbar.green, 1f / 255f)
        assertEquals("Toolbar blue must follow the page in this frame", page.blue, toolbar.blue, 1f / 255f)
        return page
    }
}
