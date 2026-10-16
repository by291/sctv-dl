package dev.sctvdl.feature.settings

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsAccessibilityTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun wifiSettingExposesItsLabelAndToggleAsOneAccessibleControl() {
        var enabled = false
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        SettingsScreen(AppSettings(), {}, {}, {}, { enabled = it })
                    }
                }
            }
            val label = requireNotNull(device.wait(Until.findObject(By.text("仅 Wi-Fi 下载")), 5_000))
            val controls = device.findObjects(By.checkable(true))
                .filter { it.visibleBounds.contains(label.visibleBounds) }
            assertEquals("The label must belong to one accessible switch", 1, controls.size)
            val control = controls.single()
            assertTrue(control.isClickable)
            assertEquals(
                "The visual switch must not create a second accessible action",
                1,
                device.findObjects(By.checkable(true)).count { control.visibleBounds.contains(it.visibleBounds) }
            )

            control.click()
            device.waitForIdle()
            scenario.onActivity { assertTrue(enabled) }
        }
    }
}
