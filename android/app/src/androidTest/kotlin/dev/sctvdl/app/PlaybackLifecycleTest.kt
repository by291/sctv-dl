package dev.sctvdl.app

import android.content.pm.ActivityInfo
import android.view.Choreographer
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.app.navigation.AppRoute
import dev.sctvdl.app.platform.ActivityPlaybackHost
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.player.PlaybackHost
import dev.sctvdl.feature.player.PlaybackSelection
import dev.sctvdl.feature.player.PlayerRoute
import dev.sctvdl.player.media3.PlayerSession
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.LocalDate
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackLifecycleTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun navigationRetainsTheSessionDuringExitAndRestoresTheActivityWindowAfterward() {
        lateinit var host: ObservingActivityHost
        lateinit var pop: () -> Unit
        val duringExit = CountDownLatch(1)
        var aliveDuringExit = false
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                host = ObservingActivityHost(ActivityPlaybackHost(activity))
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                            AppNavigationShell(onBackCommitted = activity::pausePlayerForDismissal) {
                                    route,
                                    navigator,
                                    _
                                ->
                                pop = navigator.back
                                when (route) {
                                    AppRoute.Catalogue -> Box(
                                        Modifier.fillMaxSize(),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Button(onClick = {
                                            navigator.open(AppRoute.Playback("fixture", "fixture", "host"))
                                        }) {
                                            Text("Open host fixture")
                                        }
                                    }
                                    is AppRoute.Playback -> PlayerRoute(
                                        route.programmeId,
                                        route.dateId,
                                        route.contentId,
                                        PlaybackSelection(
                                            "fixture",
                                            "fixture",
                                            ProgrammeContent(
                                                "host",
                                                "Host lifecycle fixture",
                                                standardUrl = "https://fixture.invalid/host.mp4"
                                            ),
                                            "Host fixture",
                                            LocalDate.of(2026, 1, 1)
                                        ),
                                        true,
                                        host,
                                        navigator.back,
                                        {}
                                    )
                                    else -> Unit
                                }
                            }
                        }
                    }
                }
            }
            requireNotNull(device.wait(Until.findObject(By.text("Open host fixture")), 5_000)).click()
            requireNotNull(device.wait(Until.findObject(By.desc("全屏播放")), 5_000)).click()
            requireNotNull(device.wait(Until.findObject(By.desc("退出全屏")), 5_000))
            device.waitForIdle()
            scenario.onActivity { activity ->
                assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE, activity.requestedOrientation)
                assertFalse(requireNotNull(host.session).player.playWhenReady)
                assertFalse(
                    requireNotNull(
                        ViewCompat.getRootWindowInsets(activity.window.decorView)
                    ).isVisible(WindowInsetsCompat.Type.statusBars())
                )
                pop()
                // Sample after the pop has been composed, while NavDisplay still draws its outgoing entry.
                Choreographer.getInstance().postFrameCallback {
                    Choreographer.getInstance().postFrameCallback {
                        aliveDuringExit = host.unbound.count > 0 && !requireNotNull(host.session).player.isReleased
                        duringExit.countDown()
                    }
                }
            }
            assertTrue("The exit transition must produce frames", duringExit.await(3, TimeUnit.SECONDS))
            assertTrue("The outgoing player must survive the leave animation", aliveDuringExit)
            assertTrue("Navigation must eventually dispose the player", host.unbound.await(5, TimeUnit.SECONDS))
            device.waitForIdle()
            scenario.onActivity { activity ->
                assertTrue(requireNotNull(host.session).player.isReleased)
                assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, activity.requestedOrientation)
                assertTrue(
                    requireNotNull(
                        ViewCompat.getRootWindowInsets(activity.window.decorView)
                    ).isVisible(WindowInsetsCompat.Type.statusBars())
                )
            }
        }
    }
}

private class ObservingActivityHost(private val delegate: PlaybackHost) : PlaybackHost by delegate {
    var session: PlayerSession? = null
    val unbound = CountDownLatch(1)

    override fun bindPlayer(session: PlayerSession) {
        this.session = session
        delegate.bindPlayer(session)
    }

    override fun unbindPlayer(session: PlayerSession) {
        delegate.unbindPlayer(session)
        unbound.countDown()
    }
}
