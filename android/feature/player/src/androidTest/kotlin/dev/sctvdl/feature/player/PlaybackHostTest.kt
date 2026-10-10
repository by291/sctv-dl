package dev.sctvdl.feature.player

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.player.components.PlaybackContent
import dev.sctvdl.player.media3.PlayerSession
import dev.sctvdl.player.model.PlaybackSource
import dev.sctvdl.ui.theme.SctvAppTheme
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackHostTest {
    @Test fun disposalUnbindsAndReleasesTheSamePausedSession() {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        val host = RecordingHost()
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        PlaybackContent(
                            PlaybackSource("host-fixture", "Host fixture", localUri = "content://missing-test/fixture"),
                            Quality.Standard,
                            {},
                            {},
                            host = host
                        )
                    }
                }
            }
            requireNotNull(device.wait(Until.findObject(By.text("Host fixture")), 5_000))
            scenario.onActivity {
                assertEquals(1, host.bindings.size)
                assertFalse(host.bindings.single().player.playWhenReady)
                assertFalse(host.bindings.single().player.isReleased)
                it.setContent {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("Destination disposed") }
                }
            }
            requireNotNull(device.wait(Until.findObject(By.text("Destination disposed")), 5_000))
            scenario.onActivity {
                assertSame(host.bindings.single(), host.unbindings.single())
                assertTrue(host.bindings.single().player.isReleased)
                assertEquals(false, host.fullscreenChanges.last())
            }
        }
    }
}

private class RecordingHost : PlaybackHost {
    val bindings = mutableListOf<PlayerSession>()
    val unbindings = mutableListOf<PlayerSession>()
    val fullscreenChanges = mutableListOf<Boolean>()
    override val pictureInPicture = MutableStateFlow(false)
    override val supportsPictureInPicture = false

    override fun bindPlayer(session: PlayerSession) {
        bindings += session
    }

    override fun unbindPlayer(session: PlayerSession) {
        unbindings += session
    }

    override fun fullscreen(enabled: Boolean) {
        fullscreenChanges += enabled
    }

    override fun enterPictureInPicture() = false
}
