package dev.sctvdl.feature.player

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.VideoVariant
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.player.PlayerScreen
import dev.sctvdl.feature.player.PlayerUiState
import dev.sctvdl.player.model.PlaybackSource
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerDownloadTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun downloadUnderTheTitleUsesTheCurrentProgrammeAndOnlyQueuesAfterQualitySelection() {
        val content = ProgrammeContent(
            "clip",
            "Fixture clip",
            standardUrl = "http://127.0.0.1:9/standard.mp4",
            smoothUrl = "http://127.0.0.1:9/smooth.mp4"
        )
        val requests = mutableListOf<DownloadRequest>()
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        PlayerScreen(
                            PlayerUiState(
                                loading = false,
                                source = PlaybackSource(
                                    "clip",
                                    "Fixture clip",
                                    listOf(
                                        VideoVariant(Quality.Standard, "http://127.0.0.1:9/standard.mp4"),
                                        VideoVariant(Quality.Smooth, "http://127.0.0.1:9/smooth.mp4")
                                    )
                                ),
                                content = content,
                                programmeName = "Fixture programme",
                                broadcastDate = LocalDate.of(2026, 10, 8)
                            ),
                            {},
                            {},
                            {},
                            { requests += it },
                            true,
                            host = TestPlaybackHost()
                        )
                    }
                }
            }
            val download = device.wait(Until.findObject(By.text("下载节目")), 5_000)
            assertNotNull("Downloads must have a visible labelled entry below the video", download)
            val title = requireNotNull(device.findObject(By.text("Fixture clip")))
            assertTrue(download!!.visibleBounds.top >= title.visibleBounds.bottom)
            download.click()
            requireNotNull(device.wait(Until.findObject(By.desc("关闭清晰度选择")), 5_000)).click()
            scenario.onActivity { assertTrue(requests.isEmpty()) }
            requireNotNull(device.wait(Until.findObject(By.text("下载节目")), 5_000)).click()
            requireNotNull(device.wait(Until.findObject(By.text("流畅")), 5_000)).click()
            scenario.onActivity {
                assertEquals(
                    listOf(
                        DownloadRequest(
                            "Fixture programme",
                            LocalDate.of(2026, 10, 8),
                            content,
                            Quality.Smooth,
                            true
                        )
                    ),
                    requests
                )
            }
        }
    }
}
