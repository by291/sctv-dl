package dev.sctvdl.feature.player

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.VideoVariant
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.player.components.PlaybackContent
import dev.sctvdl.player.model.PlaybackSource
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerOverlayTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private val source = PlaybackSource(
        "overlay-fixture",
        "Fixture episode",
        listOf(
            VideoVariant(Quality.Standard, "http://127.0.0.1:9/standard.mp4"),
            VideoVariant(Quality.Smooth, "http://127.0.0.1:9/smooth.mp4")
        )
    )

    @Test fun pictureInPictureIsAboveTheTimelineAndTransportControls() {
        showPlayer { _ ->
            val pip = requireNotNull(device.wait(Until.findObject(By.desc("进入画中画")), 5_000))
            val timeline = requireNotNull(device.findObject(By.desc("播放进度")))
            val fullscreen = requireNotNull(device.findObject(By.desc("全屏播放")))
            assertTrue("PiP belongs at the top of the video", pip.visibleBounds.bottom <= timeline.visibleBounds.top)
            assertTrue(
                "Fullscreen belongs below the timeline",
                fullscreen.visibleBounds.top >= timeline.visibleBounds.bottom
            )
        }
    }

    @Test fun downloadSharesTheInformationColumnWidth() {
        showPlayer { _ ->
            val label = requireNotNull(device.wait(Until.findObject(By.text("下载节目")), 5_000))
            val download = label.parent
            val title = requireNotNull(device.findObject(By.text("Fixture episode")))
            // Text accessibility bounds represent the shared information column, not just the ink.
            assertEquals(title.visibleBounds.left, download.visibleBounds.left)
            assertEquals(title.visibleBounds.right, download.visibleBounds.right)
        }
    }

    @Test fun qualityMenuOpensAboveItsControlAndBackDismissesIt() {
        showPlayer { _ ->
            val control = requireNotNull(device.wait(Until.findObject(By.desc("清晰度")), 5_000))
            val bounds = control.visibleBounds
            control.click()
            val option = requireNotNull(device.wait(Until.findObject(By.text("流畅")), 5_000))
            assertTrue("Quality options belong above the control", option.visibleBounds.bottom <= bounds.top)

            device.pressBack()
            assertTrue(device.wait(Until.gone(By.text("流畅")), 5_000))
            assertTrue(device.hasObject(By.desc("清晰度")))
            assertTrue(device.hasObject(By.text("标清")))
        }
    }

    @Test fun speedMenuOpensAboveItsControlAndBackDismissesIt() {
        showPlayer { _ ->
            val control = requireNotNull(device.wait(Until.findObject(By.desc("播放速度")), 5_000))
            val bounds = control.visibleBounds
            control.click()
            val option = requireNotNull(device.wait(Until.findObject(By.text("0.75×")), 5_000))
            assertTrue("Speed options belong above the control", option.visibleBounds.bottom <= bounds.top)

            device.pressBack()
            assertTrue(device.wait(Until.gone(By.text("0.75×")), 5_000))
            assertTrue(device.hasObject(By.desc("播放速度")))
            assertTrue(device.hasObject(By.text("1×")))
        }
    }

    @Test fun changingSpeedKeepsTheControlAndMenuInPlace() {
        showPlayer { _ ->
            val control = requireNotNull(device.wait(Until.findObject(By.desc("播放速度")), 5_000))
            val controlBounds = control.visibleBounds
            control.click()
            val menu = requireNotNull(device.wait(Until.findObject(By.scrollable(true)), 5_000))
            val menuCenter = menu.visibleBounds.centerX()

            listOf("1.25×", "1×").forEach { label ->
                requireNotNull(
                    device.wait(Until.findObject(By.text(label).hasAncestor(By.scrollable(true))), 5_000)
                ).click()
                assertTrue(device.wait(Until.gone(By.text("0.75×")), 5_000))
                val updatedControl = requireNotNull(device.findObject(By.desc("播放速度")))
                assertEquals(
                    "Changing speed must not move or resize its control",
                    controlBounds,
                    updatedControl.visibleBounds
                )

                updatedControl.click()
                val updatedMenu = requireNotNull(device.wait(Until.findObject(By.scrollable(true)), 5_000))
                assertEquals("Changing speed must not move the menu", menuCenter, updatedMenu.visibleBounds.centerX())
            }
        }
    }

    private fun showPlayer(check: (ActivityScenario<ComponentActivity>) -> Unit) {
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        PlaybackContent(source, Quality.Standard, {}, {}, onDownload = {}, host = TestPlaybackHost())
                    }
                }
            }
            check(scenario)
        }
    }
}
