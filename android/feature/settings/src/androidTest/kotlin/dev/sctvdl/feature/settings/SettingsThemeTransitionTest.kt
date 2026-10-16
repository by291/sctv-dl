package dev.sctvdl.feature.settings

import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class SettingsThemeTransitionTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val animatorScale = Settings.Global.getFloat(
        instrumentation.targetContext.contentResolver,
        Settings.Global.ANIMATOR_DURATION_SCALE,
        1f
    )
    private val animationsEnabled = animatorScale > 0f

    @Test fun appearanceChangesInterpolateColoursWithoutRecreatingTheSettingsContent() {
        assumeTrue(Build.VERSION.SDK_INT >= 31)
        var settings by mutableStateOf(AppSettings(theme = ThemeMode.Light))
        val frames = mutableListOf<Palette>()
        var compositions = 0
        var disposals = 0

        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(settings) {
                        val palette = Palette(MaterialTheme.colorScheme)
                        SideEffect { if (frames.lastOrNull() != palette) frames.add(palette) }
                        DisposableEffect(Unit) {
                            compositions++
                            onDispose { disposals++ }
                        }
                        SettingsScreen(
                            settings,
                            { settings = settings.copy(theme = it) },
                            { settings = settings.copy(dynamicColour = it) },
                            {},
                            {}
                        )
                    }
                }
            }
            requireNotNull(device.wait(Until.findObject(By.text("深色")), 5_000))
            device.waitForIdle()
            lateinit var light: Palette
            scenario.onActivity {
                light = frames.last()
                assertTrue(light.surface.luminance() > 0.8f)
                frames.clear()
            }

            device.findObject(By.text("深色")).click()
            awaitStablePalette(scenario, frames)
            lateinit var dark: Palette
            scenario.onActivity {
                dark = frames.last()
                assertTrue(dark.surface.luminance() < 0.2f)
                assertTransition(frames, light, dark)
                frames.clear()
            }

            device.findObject(By.text("动态配色")).click()
            awaitStablePalette(scenario, frames)
            scenario.onActivity { activity ->
                val dynamic = Palette(dynamicDarkColorScheme(activity))
                assertEquals(dynamic, frames.last())
                assertTransition(frames, dark, dynamic)
                frames.clear()
            }

            device.findObject(By.text("动态配色")).click()
            awaitStablePalette(scenario, frames)
            scenario.onActivity {
                assertEquals(dark, frames.last())
                frames.clear()
            }
            device.findObject(By.text("浅色")).click()
            awaitStablePalette(scenario, frames)
            scenario.onActivity {
                assertEquals(light, frames.last())
                assertTransition(frames, dark, light)
                assertEquals("Theme updates must retain one content composition", 1, compositions)
                assertEquals("Theme updates must not dispose settings", 0, disposals)
            }
        }
    }

    private fun awaitStablePalette(scenario: ActivityScenario<ComponentActivity>, frames: List<Palette>) {
        val deadline = SystemClock.uptimeMillis() + 3_000 + (1_000 * animatorScale).toLong()
        val settlingMillis = (150 * maxOf(1f, animatorScale)).toLong()
        var lastChange = SystemClock.uptimeMillis()
        var previous: Palette? = null
        while (SystemClock.uptimeMillis() < deadline) {
            var current: Palette? = null
            scenario.onActivity { current = frames.lastOrNull() }
            if (current != previous) {
                lastChange = SystemClock.uptimeMillis()
                previous = current
            }
            // Colour frames emit no accessibility events; quantized shades may repeat during slow transitions.
            if (current != null && SystemClock.uptimeMillis() - lastChange >= settlingMillis) return
            SystemClock.sleep(16)
        }
        error("The theme must reach a stable palette")
    }

    private fun assertTransition(frames: List<Palette>, start: Palette, end: Palette) {
        if (!animationsEnabled) {
            assertTrue(
                "Disabled animations must apply final colours without intermediate shades",
                frames.all {
                    it.primary in listOf(start.primary, end.primary) &&
                        it.surface in listOf(start.surface, end.surface) &&
                        it.text in listOf(start.text, end.text)
                }
            )
            return
        }

        assertTrue(
            "The theme must emit intermediate accent colours",
            frames.any {
                it.primary != start.primary && it.primary != end.primary
            }
        )
        if (start.surface != end.surface) {
            assertTrue(
                "The theme must emit intermediate surface colours",
                frames.any {
                    it.surface != start.surface && it.surface != end.surface
                }
            )
        }
        if (start.text != end.text) {
            assertTrue(
                "Text colours must transition with the surfaces",
                frames.any {
                    it.text != start.text && it.text != end.text
                }
            )
        }
    }

    private data class Palette(val primary: Color, val surface: Color, val text: Color) {
        constructor(colours: ColorScheme) : this(colours.primary, colours.surface, colours.onSurface)
    }
}
