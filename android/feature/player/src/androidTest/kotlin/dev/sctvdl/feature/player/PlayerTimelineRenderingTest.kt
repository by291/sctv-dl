package dev.sctvdl.feature.player

import android.graphics.Bitmap
import android.graphics.Color
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
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
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.VideoVariant
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.player.media3.PlayerSession
import dev.sctvdl.player.model.PlaybackState
import dev.sctvdl.player.ui.PlayerVideo
import dev.sctvdl.ui.theme.SctvAppTheme
import java.io.File
import kotlin.math.abs
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerTimelineRenderingTest {
    @Test fun thinTrackAndThumbRemainCenteredAndBothTrackSegmentsAreVisible() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        var session: PlayerSession? = null
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                session = PlayerSession(activity)
                activity.setContent {
                    CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                        SctvAppTheme(AppSettings()) {
                            Box(Modifier.size(400.dp, 225.dp)) {
                                PlayerVideo(
                                    requireNotNull(session).player,
                                    PlaybackState(
                                        positionMs = 720_000,
                                        durationMs = 1_440_000,
                                        quality = Quality.Standard,
                                        variants = listOf(VideoVariant(Quality.Standard, "fixture.mp4"))
                                    ),
                                    {}, {}, false, {}, null, {}, {}, {}, Modifier.size(400.dp, 225.dp)
                                )
                            }
                        }
                    }
                }
            }
            try {
                val bounds = requireNotNull(device.wait(Until.findObject(By.desc("播放进度")), 5_000)).visibleBounds
                device.waitForIdle()
                val image = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
                File(instrumentation.targetContext.externalCacheDir, "player-timeline.png").outputStream().use {
                    image.compress(Bitmap.CompressFormat.PNG, 100, it)
                }

                fun coloredRows(x: Int, predicate: (Int) -> Boolean): List<Int> =
                    (bounds.top until bounds.bottom).filter { predicate(image.getPixel(x, it)) }
                val red: (Int) -> Boolean = { Color.red(it) > 100 && Color.red(it) > Color.green(it) * 1.4f }
                val active = coloredRows(bounds.left + bounds.width() / 4, red)
                val thumb = coloredRows(bounds.centerX(), red)
                val inactive = coloredRows(bounds.left + bounds.width() * 3 / 4) {
                    Color.red(it) > 40 && abs(Color.red(it) - Color.green(it)) < 4
                }
                assertTrue("The active track must be visible", active.isNotEmpty())
                assertTrue("The remaining track must be visible", inactive.isNotEmpty())
                assertTrue("The thumb extends above the track: $thumb / $active", thumb.first() < active.first())
                assertTrue("The thumb extends below the track: $thumb / $active", thumb.last() > active.last())
                assertTrue("Track segments stay level", abs(active.average() - inactive.average()) <= 1)
                assertTrue("The thumb stays centered", abs(active.average() - thumb.average()) <= 1)
                image.recycle()
            } finally {
                scenario.onActivity { session?.release() }
            }
        }
    }
}
