package dev.sctvdl.player.ui

import android.app.Dialog
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.media3.exoplayer.ExoPlayer
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.player.model.PlaybackState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerGesturesTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)

    @Test fun singleTapsRevealHiddenPlayingControlsThenHideThemAgain() {
        withPlayer({}, playing = true) {
            val controls = By.desc("播放控制栏")
            assertTrue("Playing controls hide after inactivity", device.wait(Until.gone(controls), 6_000))
            val x = device.displayWidth / 2
            val y = device.displayHeight / 2

            device.click(x, y)
            assertTrue("A single tap reveals hidden controls", device.wait(Until.hasObject(controls), 1_000))
            // Keep the next input a separate single tap rather than the second half of a double tap.
            SystemClock.sleep(400)
            device.click(x, y)
            assertTrue("The next single tap hides visible controls", device.wait(Until.gone(controls), 1_000))
        }
    }

    @Test fun horizontalDragCommitsOnceAndCancellationDoesNotSeek() {
        val seeks = mutableListOf<Long>()
        withPlayer({ seeks.add(it) }) {
            val x = device.displayWidth / 2
            val y = device.displayHeight / 2
            device.swipe(x, y, x + device.displayWidth / 4, y, 20)
            instrumentation.waitForIdleSync()
            assertEquals(1, seeks.size)
            assertTrue(seeks.single() in 60_000L..90_000L)

            val down = SystemClock.uptimeMillis()
            inject(down, MotionEvent.ACTION_DOWN, x.toFloat(), y.toFloat())
            inject(down, MotionEvent.ACTION_MOVE, x + 150f, y.toFloat())
            inject(down, MotionEvent.ACTION_CANCEL, x + 150f, y.toFloat())
            instrumentation.waitForIdleSync()
            assertEquals(1, seeks.size)
        }
    }

    @Test fun doubleTapTogglesPlayback() {
        var toggles = 0
        withPlayer({}, { toggles++ }) {
            val x = device.displayWidth / 2
            val y = device.displayHeight / 2
            device.click(x, y)
            device.click(x, y)
            instrumentation.waitForIdleSync()
            assertEquals(1, toggles)
        }
    }

    @Test fun longEpisodeDragUsesTwoMinuteWindowRatherThanEntireEpisode() {
        val seeks = mutableListOf<Long>()
        withPlayer({ seeks.add(it) }, duration = 3_600_000) {
            val x = device.displayWidth / 2
            val y = device.displayHeight / 2
            device.swipe(x, y, x + device.displayWidth / 4, y, 20)
            instrumentation.waitForIdleSync()
            assertEquals(1, seeks.size)
            assertTrue("Quarter width advances about 30 seconds", seeks.single() in 75_000L..85_000L)
        }
    }

    @Test fun longPressBoostEndsOnPointerCancellation() {
        val boost = mutableListOf<Boolean>()
        withPlayer({}, playing = true, onTemporarySpeed = { boost.add(it) }) {
            val x = device.displayWidth / 2f
            val y = device.displayHeight / 2f
            val down = SystemClock.uptimeMillis()
            inject(down, MotionEvent.ACTION_DOWN, x, y)
            SystemClock.sleep(700)
            instrumentation.waitForIdleSync()
            assertEquals(listOf(true), boost)

            inject(down, MotionEvent.ACTION_CANCEL, x, y)
            instrumentation.waitForIdleSync()
            assertEquals(listOf(true, false), boost)
        }
    }

    @Test fun sourceReplacementDiscardsAnActiveSeek() {
        val seeks = mutableListOf<Long>()
        val state = mutableStateOf(PlaybackState(sourceId = "first", positionMs = 50_000, durationMs = 100_000))
        withPlayer({ seeks.add(it) }, stateOverride = state) {
            val x = device.displayWidth / 2f
            val y = device.displayHeight / 2f
            val down = SystemClock.uptimeMillis()
            inject(down, MotionEvent.ACTION_DOWN, x, y)
            inject(down, MotionEvent.ACTION_MOVE, x + 150f, y)
            assertTrue(device.wait(Until.hasObject(By.textStartsWith("进度 ")), 2_000))
            instrumentation.runOnMainSync { state.value = state.value.copy(sourceId = "second") }
            // Accessibility idleness alone does not await a Compose state frame.
            // Observe cancellation before delivering the next input event.
            assertTrue(device.wait(Until.gone(By.textStartsWith("进度 ")), 2_000))
            inject(down, MotionEvent.ACTION_UP, x + 150f, y)
            instrumentation.waitForIdleSync()
            assertTrue(seeks.isEmpty())
        }
    }

    @Test fun longPressOnTransportControlDoesNotBoostVideo() {
        val boost = mutableListOf<Boolean>()
        withPlayer({}, playing = true, onTemporarySpeed = { boost.add(it) }) {
            val bounds = requireNotNull(device.findObject(By.desc("开始播放"))).visibleBounds
            val down = SystemClock.uptimeMillis()
            inject(down, MotionEvent.ACTION_DOWN, bounds.centerX().toFloat(), bounds.centerY().toFloat())
            SystemClock.sleep(700)
            inject(down, MotionEvent.ACTION_UP, bounds.centerX().toFloat(), bounds.centerY().toFloat())
            instrumentation.waitForIdleSync()
            assertTrue(boost.none { it })
        }
    }

    @Test fun secondPointerDiscardsActiveSeek() {
        val seeks = mutableListOf<Long>()
        withPlayer({ seeks.add(it) }) {
            val x = device.displayWidth / 2f
            val y = device.displayHeight / 2f
            val down = SystemClock.uptimeMillis()
            inject(down, MotionEvent.ACTION_DOWN, x, y)
            inject(down, MotionEvent.ACTION_MOVE, x + 150f, y)
            val properties = Array(2) { index ->
                MotionEvent.PointerProperties().apply {
                    id = index
                    toolType = MotionEvent.TOOL_TYPE_FINGER
                }
            }
            val coordinates = Array(2) { index ->
                MotionEvent.PointerCoords().apply {
                    this.x = x + 150f + index * 40f
                    this.y = y
                    pressure = 1f
                    size = 1f
                }
            }
            val event = MotionEvent.obtain(
                down, SystemClock.uptimeMillis(),
                MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
                2, properties, coordinates, 0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0
            )
            instrumentation.uiAutomation.injectInputEvent(event, true)
            event.recycle()
            inject(down, MotionEvent.ACTION_CANCEL, x + 150f, y)
            instrumentation.waitForIdleSync()
            assertTrue(seeks.isEmpty())
        }
    }

    @Test fun pointerOnRealControlCancelsBlankSeekWithoutConsumingControl() {
        val seeks = mutableListOf<Long>()
        var toggles = 0
        withPlayer({ seeks.add(it) }, { toggles++ }) {
            val button = requireNotNull(device.findObject(By.desc("开始播放"))).visibleBounds
            val x = device.displayWidth / 2f
            val y = device.displayHeight / 2f
            val down = SystemClock.uptimeMillis()
            inject(down, MotionEvent.ACTION_DOWN, x, y)
            inject(down, MotionEvent.ACTION_MOVE, x + 150f, y)
            assertTrue(device.wait(Until.hasObject(By.textStartsWith("进度 ")), 2_000))
            injectTwo(
                down,
                MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
                x + 150f,
                y,
                button.centerX().toFloat(),
                button.centerY().toFloat()
            )
            injectTwo(
                down,
                MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
                x + 150f,
                y,
                button.centerX().toFloat(),
                button.centerY().toFloat()
            )
            inject(down, MotionEvent.ACTION_UP, x + 150f, y)
            instrumentation.waitForIdleSync()
            assertTrue("The blank seek is cancelled by a pointer on the button", seeks.isEmpty())
            assertEquals("The transport button keeps its input", 1, toggles)
        }
    }

    @Test fun pointerOnSeekSliderRestoresTemporarySpeedBeforeFirstPointerRelease() {
        val boost = mutableListOf<Boolean>()
        withPlayer({}, playing = true, onTemporarySpeed = { boost.add(it) }) {
            val button = requireNotNull(device.findObject(By.desc("播放进度"))).visibleBounds
            val x = device.displayWidth / 2f
            val y = device.displayHeight / 2f
            val down = SystemClock.uptimeMillis()
            inject(down, MotionEvent.ACTION_DOWN, x, y)
            SystemClock.sleep(700)
            instrumentation.waitForIdleSync()
            assertEquals(listOf(true), boost)
            injectTwo(
                down,
                MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
                x,
                y,
                button.centerX().toFloat(),
                button.centerY().toFloat()
            )
            instrumentation.waitForIdleSync()
            assertEquals(listOf(true, false), boost)
            injectTwo(
                down,
                MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
                x,
                y,
                button.centerX().toFloat(),
                button.centerY().toFloat()
            )
            inject(down, MotionEvent.ACTION_UP, x, y)
        }
    }

    @Test fun blankSecondPointerCannotBeginBoostWhileControlPointerIsHeld() {
        val boost = mutableListOf<Boolean>()
        withPlayer({}, playing = true, onTemporarySpeed = { boost.add(it) }) {
            val button = requireNotNull(device.findObject(By.desc("开始播放"))).visibleBounds
            val x = button.centerX().toFloat()
            val y = button.centerY().toFloat()
            val blankX = device.displayWidth / 2f
            val blankY = device.displayHeight / 2f
            val down = SystemClock.uptimeMillis()
            inject(down, MotionEvent.ACTION_DOWN, x, y)
            injectTwo(
                down,
                MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
                x,
                y,
                blankX,
                blankY
            )
            SystemClock.sleep(700)
            instrumentation.waitForIdleSync()
            assertTrue("A blank pointer cannot boost while another pointer holds a control", boost.none { it })
            injectTwo(
                down,
                MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT),
                x,
                y,
                blankX,
                blankY
            )
            inject(down, MotionEvent.ACTION_UP, x, y)
        }
    }

    @Test fun hintSurvivesWindowAndLifecycleInterruptionUntilAcknowledged() {
        var seen = false
        val environment = object : PlayerGestureEnvironment {
            override fun adjustBrightness(delta: Float) = 50

            override fun adjustVolume(delta: Float) = 50

            override fun restoreBrightness() {}

            override fun needsGestureHint() = !seen

            override fun acknowledgeGestureHint() {
                seen = true
            }
        }
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            var player: ExoPlayer? = null
            var overlay: Dialog? = null
            scenario.onActivity { activity ->
                val exo = ExoPlayer.Builder(activity).build()
                player = exo
                overlay = Dialog(activity).apply { show() }
                activity.setContent {
                    MaterialTheme {
                        PlayerVideo(
                            player = exo, state = PlaybackState(durationMs = 100_000),
                            onQuality = {}, onSpeed = {}, fullscreen = true, onFullscreen = {},
                            onPip = null, onRetry = {}, onTogglePlay = {}, onSeek = {},
                            gestureEnvironment = environment, modifier = Modifier.fillMaxSize()
                        )
                    }
                }
            }
            try {
                SystemClock.sleep(4_500)
                assertTrue("An obscured hint stays eligible", !seen)
                scenario.onActivity { overlay?.dismiss() }
                assertTrue(device.wait(Until.hasObject(By.text("知道了")), 2_000))
                scenario.moveToState(Lifecycle.State.CREATED)
                assertTrue("Backgrounding does not acknowledge the hint", !seen)
                scenario.moveToState(Lifecycle.State.RESUMED)
                assertTrue(device.wait(Until.hasObject(By.text("知道了")), 2_000))
                device.findObject(By.text("知道了")).click()
                instrumentation.waitForIdleSync()
                assertTrue(seen)
                scenario.moveToState(Lifecycle.State.CREATED)
                scenario.moveToState(Lifecycle.State.RESUMED)
                assertTrue(device.wait(Until.gone(By.text("知道了")), 1_000))
            } finally {
                scenario.onActivity {
                    overlay?.dismiss()
                    player?.release()
                }
            }
        }
    }

    private fun injectTwo(down: Long, action: Int, x: Float, y: Float, secondX: Float, secondY: Float) {
        val properties = Array(2) { index ->
            MotionEvent.PointerProperties().apply {
                id = index
                toolType = MotionEvent.TOOL_TYPE_FINGER
            }
        }
        val coordinates = Array(2) { index ->
            MotionEvent.PointerCoords().apply {
                this.x = if (index == 0) x else secondX
                this.y = if (index == 0) y else secondY
                pressure = 1f
                size = 1f
            }
        }
        val event = MotionEvent.obtain(
            down, SystemClock.uptimeMillis(), action, 2, properties, coordinates,
            0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0
        )
        instrumentation.uiAutomation.injectInputEvent(event, true)
        event.recycle()
    }

    private fun inject(down: Long, action: Int, x: Float, y: Float) {
        val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, x, y, 0)
        event.source = InputDevice.SOURCE_TOUCHSCREEN
        instrumentation.uiAutomation.injectInputEvent(event, true)
        event.recycle()
    }

    private fun withPlayer(
        onSeek: (Long) -> Unit,
        onToggle: () -> Unit = {
        },
        duration: Long = 100_000,
        playing: Boolean = false,
        onTemporarySpeed: (Boolean) -> Unit = {},
        stateOverride: MutableState<PlaybackState>? = null,
        check: () -> Unit
    ) {
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            var player: ExoPlayer? = null
            scenario.onActivity { activity ->
                val exo = ExoPlayer.Builder(activity).build()
                player = exo
                activity.setContent {
                    MaterialTheme {
                        PlayerVideo(
                            player = exo,
                            state =
                            stateOverride?.value
                                ?: PlaybackState(positionMs = 50_000, durationMs = duration, playing = playing),
                            onQuality = {}, onSpeed = {}, fullscreen = false, onFullscreen = {},
                            onPip = null, onRetry = {}, onTogglePlay = onToggle, onSeek = onSeek,
                            onTemporarySpeed = onTemporarySpeed,
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                }
            }
            instrumentation.waitForIdleSync()
            assertTrue(device.wait(Until.hasObject(By.desc("播放控制栏")), 3_000))
            device.waitForIdle()
            try {
                check()
            } finally {
                scenario.onActivity { player?.release() }
            }
        }
    }
}
