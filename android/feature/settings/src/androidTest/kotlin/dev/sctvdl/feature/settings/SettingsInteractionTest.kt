package dev.sctvdl.feature.settings

import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.feature.settings.components.PreferenceGroup
import dev.sctvdl.feature.settings.components.SettingSwitch
import dev.sctvdl.ui.theme.SctvAppTheme
import kotlin.math.abs
import kotlin.math.roundToInt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsInteractionTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)

    @Test fun switchFeedbackIncludesCardInsetsAndStaysInsideRoundedCorners() {
        for (theme in listOf(ThemeMode.Light, ThemeMode.Dark)) {
            for (fontScale in listOf(1f, 2f)) {
                var changes = 0
                var density = 1f

                ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
                    scenario.onActivity { activity ->
                        density = activity.resources.displayMetrics.density
                        activity.setContent {
                            CompositionLocalProvider(LocalDensity provides Density(density, fontScale)) {
                                SctvAppTheme(AppSettings(theme = theme)) {
                                    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                                        Box {
                                            Column(Modifier.width(320.dp).padding(16.dp)) {
                                                PreferenceGroup("Appearance fixture") {
                                                    SettingSwitch(
                                                        "Dynamic colour fixture",
                                                        "Wallpaper colours",
                                                        false,
                                                        { changes++ }
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    val row = requireNotNull(device.wait(Until.findObject(By.checkable(true)), 5_000))
                    device.waitForIdle()
                    val bounds = row.visibleBounds
                    assertEquals("The left card inset must be clickable", (16 * density).roundToInt(), bounds.left)
                    assertEquals("The right card inset must be clickable", (304 * density).roundToInt(), bounds.right)
                    val baseline = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
                    val x = bounds.left + 2 * density
                    val y = bounds.centerY().toFloat()
                    val downTime = SystemClock.uptimeMillis()

                    try {
                        touch(MotionEvent.ACTION_DOWN, downTime, x, y)
                        val deadline = downTime + 2_000
                        var shaded = false
                        while (!shaded && SystemClock.uptimeMillis() < deadline) {
                            val pressed = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
                            try {
                                shaded = changed(baseline, pressed, x.roundToInt(), y.roundToInt(), 6)
                                if (shaded) {
                                    val inset = maxOf(1, density.roundToInt())
                                    for (cornerX in listOf(bounds.left + inset, bounds.right - inset - 1)) {
                                        for (cornerY in listOf(bounds.top + inset, bounds.bottom - inset - 1)) {
                                            assertTrue(
                                                "Feedback must preserve the card's rounded corners",
                                                !changed(baseline, pressed, cornerX, cornerY, 2)
                                            )
                                        }
                                    }
                                }
                            } finally {
                                pressed.recycle()
                            }
                            if (!shaded) SystemClock.sleep(16)
                        }
                        assertTrue("The card edge must show a visible held press", shaded)
                        scenario.onActivity { assertEquals(0, changes) }
                    } finally {
                        touch(MotionEvent.ACTION_UP, downTime, x, y)
                        baseline.recycle()
                    }

                    device.waitForIdle()
                    scenario.onActivity { assertEquals("An edge tap must toggle exactly once", 1, changes) }
                    device.pressKeyCode(KeyEvent.KEYCODE_TAB)
                    device.pressKeyCode(KeyEvent.KEYCODE_DPAD_CENTER)
                    device.waitForIdle()
                    scenario.onActivity { assertEquals("Keyboard activation must toggle exactly once", 2, changes) }
                }
            }
        }
    }

    private fun changed(before: Bitmap, after: Bitmap, x: Int, y: Int, tolerance: Int): Boolean {
        val first = before.getPixel(x, y)
        val second = after.getPixel(x, y)
        return abs(AndroidColor.red(first) - AndroidColor.red(second)) > tolerance ||
            abs(AndroidColor.green(first) - AndroidColor.green(second)) > tolerance ||
            abs(AndroidColor.blue(first) - AndroidColor.blue(second)) > tolerance
    }

    private fun touch(action: Int, downTime: Long, x: Float, y: Float) {
        val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, x, y, 0)
        event.source = InputDevice.SOURCE_TOUCHSCREEN
        try {
            assertTrue(instrumentation.uiAutomation.injectInputEvent(event, true))
        } finally {
            event.recycle()
        }
    }
}
