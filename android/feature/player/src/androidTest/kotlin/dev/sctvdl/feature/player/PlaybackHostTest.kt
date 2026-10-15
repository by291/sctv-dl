package dev.sctvdl.feature.player

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
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
    @Test fun retainedFullscreenWaitsForResumeAndSurvivesTheLeaveAnimation() {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        val host = RecordingHost()
        var visible by mutableStateOf(true)
        lateinit var owner: PreviewLifecycleOwner

        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                owner = PreviewLifecycleOwner().apply { lifecycle.currentState = Lifecycle.State.RESUMED }
                activity.setContent {
                    val savedState = rememberSaveableStateHolder()
                    SctvAppTheme(AppSettings()) {
                        if (visible) {
                            savedState.SaveableStateProvider("player") {
                                CompositionLocalProvider(LocalLifecycleOwner provides owner) {
                                    PlaybackContent(
                                        PlaybackSource(
                                            "preview",
                                            "Preview fixture",
                                            localUri = "content://missing-test/fixture"
                                        ),
                                        Quality.Standard,
                                        {},
                                        {},
                                        host = host
                                    )
                                }
                            }
                        } else {
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                Text("Destination hidden")
                            }
                        }
                    }
                }
            }
            requireNotNull(device.wait(Until.findObject(By.desc("全屏播放")), 5_000)).click()
            requireNotNull(device.wait(Until.findObject(By.desc("退出全屏")), 5_000))
            scenario.onActivity {
                assertEquals(true, host.fullscreenChanges.last())
                visible = false
            }
            assertTrue(device.wait(Until.hasObject(By.text("Destination hidden")), 5_000))
            scenario.onActivity {
                owner.lifecycle.currentState = Lifecycle.State.STARTED
                host.fullscreenChanges.clear()
                visible = true
            }

            requireNotNull(device.wait(Until.findObject(By.desc("退出全屏")), 5_000))
            device.waitForIdle()
            scenario.onActivity {
                assertTrue("A preview must not change the Activity window", host.fullscreenChanges.isEmpty())
                visible = false
            }
            assertTrue(device.wait(Until.hasObject(By.text("Destination hidden")), 5_000))
            scenario.onActivity {
                assertFalse("Cancelling the preview must never enter fullscreen", true in host.fullscreenChanges)
                visible = true
                owner.lifecycle.currentState = Lifecycle.State.RESUMED
            }
            requireNotNull(device.wait(Until.findObject(By.desc("退出全屏")), 5_000))
            device.waitForIdle()
            scenario.onActivity {
                assertEquals(true, host.fullscreenChanges.last())
                host.fullscreenChanges.clear()
                owner.lifecycle.currentState = Lifecycle.State.STARTED
            }
            device.waitForIdle()
            scenario.onActivity {
                assertTrue("Leaving must retain fullscreen through the animation", host.fullscreenChanges.isEmpty())
                visible = false
            }
            assertTrue(device.wait(Until.hasObject(By.text("Destination hidden")), 5_000))
            scenario.onActivity { assertEquals(false, host.fullscreenChanges.last()) }
        }
    }

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

private class PreviewLifecycleOwner : LifecycleOwner {
    override val lifecycle = LifecycleRegistry(this)
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
