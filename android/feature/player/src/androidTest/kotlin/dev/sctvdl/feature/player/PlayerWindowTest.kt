package dev.sctvdl.feature.player

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
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.player.components.PlaybackContent
import dev.sctvdl.player.model.PlaybackSource
import dev.sctvdl.ui.theme.SctvAppTheme
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
                        SctvAppTheme(AppSettings()) {
                            Box(Modifier.requiredSize(600.dp, 280.dp).clipToBounds()) {
                                PlaybackContent(
                                    PlaybackSource("fixture", "新闻片段", localUri = "content://missing-test/fixture"),
                                    Quality.Standard,
                                    {},
                                    {},
                                    host = TestPlaybackHost()
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
}
