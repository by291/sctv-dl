package dev.sctvdl.feature.player

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.VideoVariant
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.player.media3.PlayerSession
import dev.sctvdl.player.model.PlaybackState
import dev.sctvdl.player.ui.PlayerVideo
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerControlsAccessibilityTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)

    @Test fun hourBoundaryKeepsAnchorsAndLargeTextScrollsToEveryAction() {
        for (theme in listOf(ThemeMode.Light, ThemeMode.Dark)) {
            val state = mutableStateOf(
                PlaybackState(
                    positionMs = 3_599_000,
                    durationMs = 7_200_000,
                    quality = Quality.Standard,
                    variants = listOf(VideoVariant(Quality.Standard, "fixture.mp4"))
                )
            )
            var session: PlayerSession? = null
            var reloads = 0
            ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    session = PlayerSession(activity)
                    activity.setContent {
                        CompositionLocalProvider(LocalDensity provides Density(1f, 2f)) {
                            SctvAppTheme(AppSettings(theme = theme)) {
                                Box(Modifier.width(320.dp).height(240.dp)) {
                                    PlayerVideo(requireNotNull(session).player, state.value, {
                                        reloads++
                                    }, {}, false, {}, null, {}, {}, {}, Modifier.width(320.dp).height(240.dp))
                                }
                            }
                        }
                    }
                }
                try {
                    val before = requireNotNull(device.wait(Until.findObject(By.desc("开始播放")), 5_000)).visibleBounds
                    val time = requireNotNull(device.findObject(By.text("59:59"))).visibleBounds
                    scenario.onActivity { state.value = state.value.copy(positionMs = 3_600_000) }
                    assertTrue(device.wait(Until.hasObject(By.text("1:00:00")), 5_000))
                    assertEquals(before, requireNotNull(device.findObject(By.desc("开始播放"))).visibleBounds)
                    assertEquals(time.left, requireNotNull(device.findObject(By.text("1:00:00"))).visibleBounds.left)
                    val row = requireNotNull(device.findObject(By.desc("播放控制栏")))
                    row.scroll(Direction.RIGHT, 1f)
                    val fullscreen = requireNotNull(device.wait(Until.findObject(By.desc("全屏播放")), 5_000))
                    assertTrue(fullscreen.visibleBounds.height() >= 48)
                    val quality = requireNotNull(device.findObject(By.desc("清晰度")))
                    val qualityTop = quality.visibleBounds.top
                    quality.click()
                    device.waitForIdle()
                    val option = requireNotNull(
                        device.findObjects(By.text("标清"))
                            .firstOrNull { it.visibleBounds.bottom <= qualityTop }
                    )
                    option.click()
                    assertEquals("Inspecting the only quality must not reload media", 0, reloads)
                } finally {
                    scenario.onActivity { session?.release() }
                }
            }
        }
    }
}
