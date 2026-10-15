package dev.sctvdl.feature.programmes

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.feature.programmes.archive.components.EpisodeCard
import dev.sctvdl.ui.theme.SctvAppTheme
import kotlin.math.abs
import kotlin.math.roundToInt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class EpisodeCardPressTest(
    private val fullEpisode: Boolean,
    private val selectionMode: Boolean,
    private val theme: ThemeMode
) {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)

    @Test fun pressFeedbackStaysInsideTheCardAndReleaseRunsOnlyItsAction() {
        val content = ProgrammeContent("press", "Press fixture", standardUrl = "fixture.mp4")
        var selected by mutableStateOf(false)
        var plays = 0
        var selections = 0
        var density = 1f

        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                density = activity.resources.displayMetrics.density
                activity.setContent {
                    CompositionLocalProvider(LocalDensity provides Density(density, 1f)) {
                        SctvAppTheme(AppSettings(theme = theme)) {
                            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                                // Keep the held corner press below the system gesture area on edge-to-edge test hosts.
                                Box(Modifier.statusBarsPadding()) {
                                    Column(Modifier.width(320.dp).padding(16.dp)) {
                                        EpisodeCard(
                                            content,
                                            fullEpisode,
                                            selectionMode,
                                            selected,
                                            { plays++ },
                                            {
                                                selections++
                                                selected = !selected
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            val description = if (selectionMode) "选择Press fixture" else "播放节目：Press fixture"
            val target = requireNotNull(device.wait(Until.findObject(By.desc(description)), 5_000))
            device.waitForIdle()
            val bounds = target.visibleBounds
            val baseline = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
            val pressX = bounds.left + 12f * density
            val pressY = bounds.top + 12f * density
            val downTime = SystemClock.uptimeMillis()

            try {
                injectTouch(MotionEvent.ACTION_DOWN, downTime, pressX, pressY)
                val interior = Rect(
                    bounds.left + (18 * density).roundToInt(),
                    bounds.top + (3 * density).roundToInt(),
                    bounds.left + (21 * density).roundToInt(),
                    bounds.top + (6 * density).roundToInt()
                )
                val pressed = awaitVisiblePress(baseline, interior, downTime)
                try {
                    assertCornersUnchanged(baseline, pressed, bounds, density)
                    scenario.onActivity {
                        assertEquals("A held press must not open playback", 0, plays)
                        assertEquals("A held press must not change selection", 0, selections)
                    }
                } finally {
                    pressed.recycle()
                }
            } finally {
                injectTouch(MotionEvent.ACTION_UP, downTime, pressX, pressY)
                baseline.recycle()
            }

            device.waitForIdle()
            scenario.onActivity {
                assertEquals(if (selectionMode) 0 else 1, plays)
                assertEquals(if (selectionMode) 1 else 0, selections)
                assertEquals(selectionMode, selected)
            }
            if (selectionMode) {
                assertTrue(
                    "The whole card must retain its checked accessibility state",
                    device.wait(Until.hasObject(By.checkable(true).checked(true)), 5_000)
                )
            }
        }
    }

    private fun awaitVisiblePress(baseline: Bitmap, interior: Rect, downTime: Long): Bitmap {
        val deadline = downTime + 2_000
        while (SystemClock.uptimeMillis() < deadline) {
            val frame = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
            // Let the ripple reach the corners, and require visible feedback so a missing ripple cannot pass.
            if (SystemClock.uptimeMillis() - downTime >= 400 && regionChanged(baseline, frame, interior, 6)) {
                return frame
            }
            frame.recycle()
            SystemClock.sleep(16)
        }
        error("The held press must visibly shade the card interior")
    }

    private fun assertCornersUnchanged(baseline: Bitmap, pressed: Bitmap, bounds: Rect, density: Float) {
        val inset = maxOf(1, density.roundToInt())
        val size = maxOf(1, (2 * density).roundToInt())
        val corners = listOf(
            Rect(bounds.left + inset, bounds.top + inset, bounds.left + inset + size, bounds.top + inset + size),
            Rect(bounds.right - inset - size, bounds.top + inset, bounds.right - inset, bounds.top + inset + size),
            Rect(bounds.left + inset, bounds.bottom - inset - size, bounds.left + inset + size, bounds.bottom - inset),
            Rect(
                bounds.right - inset - size,
                bounds.bottom - inset - size,
                bounds.right - inset,
                bounds.bottom - inset
            )
        )
        corners.forEach { corner ->
            assertTrue(
                "Press feedback must not tint the background outside the rounded corner: $corner",
                !regionChanged(baseline, pressed, corner, 2)
            )
        }
    }

    private fun regionChanged(before: Bitmap, after: Bitmap, region: Rect, tolerance: Int): Boolean {
        for (y in region.top until region.bottom) {
            for (x in region.left until region.right) {
                val first = before.getPixel(x, y)
                val second = after.getPixel(x, y)
                if (abs(Color.red(first) - Color.red(second)) > tolerance ||
                    abs(Color.green(first) - Color.green(second)) > tolerance ||
                    abs(Color.blue(first) - Color.blue(second)) > tolerance
                ) {
                    return true
                }
            }
        }
        return false
    }

    private fun injectTouch(action: Int, downTime: Long, x: Float, y: Float) {
        val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, y, 0)
        event.source = InputDevice.SOURCE_TOUCHSCREEN
        try {
            assertTrue(
                "The fixture must receive the touch event",
                instrumentation.uiAutomation.injectInputEvent(event, true)
            )
        } finally {
            event.recycle()
        }
    }

    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "fullEpisode={0}, selectionMode={1}, theme={2}")
        fun cases(): List<Array<Any>> = listOf(ThemeMode.Light, ThemeMode.Dark).flatMap { theme ->
            listOf(false, true).flatMap { fullEpisode ->
                listOf(false, true).map { selectionMode -> arrayOf(fullEpisode, selectionMode, theme) }
            }
        }
    }
}
