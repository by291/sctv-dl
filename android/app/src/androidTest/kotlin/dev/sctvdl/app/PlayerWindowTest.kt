package dev.sctvdl.app

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import dev.sctvdl.app.features.player.PlaybackDestination
import dev.sctvdl.design.SctvTheme
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.Quality
import dev.sctvdl.player.PlaybackSource
import org.junit.Assert.assertNotNull
import org.junit.Test

class PlayerWindowTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun landscapeControlsRemainReachableAtNormalText() = checkLandscape(1f)

    @Test fun landscapeControlsRemainReachableAtTwoHundredPercentText() = checkLandscape(2f)

    private fun checkLandscape(fontScale: Float) {
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    CompositionLocalProvider(LocalDensity provides Density(1f, fontScale)) {
                        SctvTheme(AppSettings()) {
                            Box(Modifier.requiredSize(600.dp, 280.dp).clipToBounds()) {
                                PlaybackDestination(
                                    PlaybackSource("fixture", "新闻片段", localUri = "content://missing-test/fixture"),
                                    Quality.Standard,
                                    {},
                                    {}
                                )
                            }
                        }
                    }
                }
            }
            var fullscreen: UiObject2? = null
            repeat(8) {
                if (fullscreen == null) {
                    device.waitForIdle()
                    fullscreen = device.findObject(By.desc("全屏播放"))
                    if (fullscreen == null) device.findObject(By.scrollable(true))?.scroll(Direction.DOWN, 0.7f)
                }
            }
            assertNotNull("Landscape fullscreen action must be reachable", fullscreen)
            fullscreen!!.click()
            assertNotNull(device.wait(Until.findObject(By.desc("退出全屏")), 5_000))
        }
    }

    @Test fun catalogueAndFavouriteFiltersRemainIndependentAfterRecreation() {
        val wifi = device.executeShellCommand("settings get global wifi_on").trim()
        val mobile = device.executeShellCommand("settings get global mobile_data").trim()
        try {
            device.executeShellCommand("svc wifi disable")
            device.executeShellCommand("svc data disable")
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                val editable = By.clazz("android.widget.EditText")
                requireNotNull(device.wait(Until.findObject(editable), 5_000)).text = "catalogue-filter"
                requireNotNull(device.wait(Until.findObject(By.text("收藏")), 5_000)).click()
                val favouritesSearch = device.wait(
                    Until.findObject(By.clazz("android.widget.EditText").text("")),
                    5_000
                )
                assertNotNull("Favourites must have their own empty filter", favouritesSearch)
                favouritesSearch!!.text = "favourites-filter"
                requireNotNull(device.wait(Until.findObject(By.text("栏目")), 5_000)).click()
                assertNotNull(
                    device.wait(Until.findObject(By.clazz("android.widget.EditText").text("catalogue-filter")), 5_000)
                )
                scenario.recreate()
                assertNotNull(
                    device.wait(Until.findObject(By.clazz("android.widget.EditText").text("catalogue-filter")), 5_000)
                )
            }
        } finally {
            device.executeShellCommand("svc wifi ${if (wifi == "1") "enable" else "disable"}")
            device.executeShellCommand("svc data ${if (mobile == "1") "enable" else "disable"}")
        }
    }
}
