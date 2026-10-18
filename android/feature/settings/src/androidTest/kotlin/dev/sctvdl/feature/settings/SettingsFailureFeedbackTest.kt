package dev.sctvdl.feature.settings

import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
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
import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsFailureFeedbackTest {
    @Test fun retryRemainsReadableAndKeyboardReachableAtLargeTextInBothThemes() {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        for (theme in listOf(ThemeMode.Light, ThemeMode.Dark)) {
            var retries = 0
            ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    activity.setContent {
                        val density = LocalDensity.current.density
                        CompositionLocalProvider(LocalDensity provides Density(density, 2f)) {
                            SctvAppTheme(AppSettings(theme = theme)) {
                                Surface {
                                    Box(Modifier.width(320.dp)) {
                                        SettingsScreen(
                                            AppSettings(theme = theme),
                                            {},
                                            {},
                                            {},
                                            {},
                                            error = AppError(ErrorKind.Storage, "设置未保存，请重试"),
                                            onRetry = { retries++ }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                val error = requireNotNull(device.wait(Until.findObject(By.text("设置未保存，请重试")), 5_000))
                val retry = requireNotNull(device.wait(Until.findObject(By.text("重试")), 5_000))
                assertTrue(error.visibleBounds.height() > 0)
                assertTrue(retry.visibleBounds.height() > 0)
                retry.click()
                device.waitForIdle()
                scenario.onActivity { assertEquals(1, retries) }

                // Keyboard focus starts at the page's first action, the explicit retry button.
                device.pressKeyCode(KeyEvent.KEYCODE_TAB)
                device.pressKeyCode(KeyEvent.KEYCODE_DPAD_CENTER)
                device.waitForIdle()
                scenario.onActivity { assertEquals(2, retries) }
                device.takeScreenshot(activityCache(scenario, "settings-retry-${theme.name}.png"))
            }
        }
    }

    private fun activityCache(scenario: ActivityScenario<ComponentActivity>, name: String): java.io.File {
        lateinit var result: java.io.File
        scenario.onActivity { result = it.cacheDir.resolve(name) }
        return result
    }
}
