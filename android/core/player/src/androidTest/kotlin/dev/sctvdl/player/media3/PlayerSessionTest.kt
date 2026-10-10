@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package dev.sctvdl.player.media3

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.VideoVariant
import dev.sctvdl.player.media3.PlayerSession
import dev.sctvdl.player.model.PlaybackSource
import dev.sctvdl.player.ui.PlayerVideo
import dev.sctvdl.player.ui.VideoSurface
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerSessionTest {
    @Test
    fun decodedVideoFadesWithThePageAndSurvivesACancelledTransition() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val fixture = encodeFixture(context)
        var session: PlayerSession? = null
        val rendered = AtomicBoolean(false)
        val samplePoint = AtomicReference<Offset?>()
        var pageAlpha by mutableFloatStateOf(1f)
        try {
            onMain {
                session = PlayerSession(context).also { current ->
                    current.player.addListener(object : Player.Listener {
                        override fun onRenderedFirstFrame() {
                            rendered.set(true)
                        }
                    })
                    current.controller.setSource(
                        PlaybackSource(
                            "transition-fixture",
                            "本地测试",
                            emptyList(),
                            android.net.Uri.fromFile(fixture).toString()
                        )
                    )
                }
            }
            ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
                scenario.onActivity { host ->
                    host.setContent {
                        Box(Modifier.fillMaxSize().background(Color.Red)) {
                            VideoSurface(
                                requireNotNull(session).player,
                                Modifier.fillMaxWidth().height(160.dp).graphicsLayer { alpha = pageAlpha }
                                    .onGloballyPositioned { samplePoint.set(it.boundsInWindow().center) }
                            )
                        }
                    }
                }
                await { rendered.get() && samplePoint.get() != null }
                val point = requireNotNull(samplePoint.get())
                awaitScreenPixel(point, "The decoded frame must be visible") {
                    android.graphics.Color.red(it) in 5..60 && android.graphics.Color.blue(it) in 5..60
                }

                // A fixed intermediate page alpha exercises the same compositor path as a return fade.
                onMain { pageAlpha = 0.25f }
                awaitScreenPixel(point, "Video must fade with the outgoing page") {
                    android.graphics.Color.red(it) > 150 && android.graphics.Color.blue(it) < 30
                }

                onMain {
                    pageAlpha = 1f
                    assertEquals(Player.STATE_READY, requireNotNull(session).player.playbackState)
                }
                awaitScreenPixel(point, "Cancelling the transition must restore the decoded frame") {
                    android.graphics.Color.red(it) in 5..60 && android.graphics.Color.blue(it) in 5..60
                }

                scenario.onActivity { host ->
                    host.setContent { Box(Modifier.fillMaxSize().background(Color.Red)) }
                }
                awaitScreenPixel(point, "Leaving the page must remove the video surface") {
                    android.graphics.Color.red(it) > 240 && android.graphics.Color.blue(it) < 20
                }
            }
        } finally {
            onMain { session?.release() }
            fixture.delete()
        }
    }

    @Test
    fun decodedVideoPreservesThePageBackgroundOutsideItsSurface() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val fixture = encodeFixture(context)
        var session: PlayerSession? = null
        val rendered = AtomicBoolean(false)
        val samplePoint = AtomicReference<Offset?>()
        var activity: ActivityScenario<ComponentActivity>? = null
        try {
            onMain {
                session = PlayerSession(context).also { current ->
                    current.player.addListener(object : Player.Listener {
                        override fun onRenderedFirstFrame() {
                            rendered.set(true)
                        }
                    })
                    current.controller.setSource(
                        PlaybackSource(
                            "surface-fixture",
                            "本地测试",
                            emptyList(),
                            android.net.Uri.fromFile(fixture).toString()
                        )
                    )
                }
            }
            activity = ActivityScenario.launch(ComponentActivity::class.java)
            activity.onActivity { host ->
                host.setContent {
                    Column(Modifier.fillMaxSize().background(Color.White)) {
                        VideoSurface(requireNotNull(session).player, Modifier.fillMaxWidth().height(160.dp))
                        Box(
                            Modifier.fillMaxWidth().weight(1f).onGloballyPositioned {
                                samplePoint.set(it.boundsInWindow().center)
                            }
                        )
                    }
                }
            }
            await { rendered.get() && samplePoint.get() != null }
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            val point = requireNotNull(samplePoint.get())
            // Capture the actual window: Compose-only captures cannot see SurfaceView compositor defects.
            val deadline = System.nanoTime() + 3_000_000_000L
            var pixel = 0
            var visible = false
            while (!visible && System.nanoTime() < deadline) {
                val screenshot =
                    requireNotNull(InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
                try {
                    pixel = screenshot.getPixel(point.x.toInt(), point.y.toInt())
                    visible = android.graphics.Color.red(pixel) > 240 && android.graphics.Color.green(pixel) > 240 &&
                        android.graphics.Color.blue(pixel) > 240
                } finally {
                    screenshot.recycle()
                }
                if (!visible) Thread.sleep(50)
            }
            assertTrue("Decoded video blacked out the page background: ${Integer.toHexString(pixel)}", visible)
        } finally {
            activity?.close()
            onMain { session?.release() }
            fixture.delete()
        }
    }

    @Test
    fun actualLocalPlaybackKeepsPlayerAcrossQualityAndObeysBackgroundPolicy() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val fixture = encodeFixture(context)
        var session: PlayerSession? = null
        try {
            onMain { session = PlayerSession(context) }
            val current = requireNotNull(session)
            val player = current.player
            val uri = android.net.Uri.fromFile(fixture).toString()
            onMain {
                current.controller.setSource(
                    PlaybackSource(
                        "fixture",
                        "本地测试",
                        listOf(
                            VideoVariant(Quality.Standard, uri),
                            VideoVariant(Quality.Smooth, "$uri?quality=smooth")
                        )
                    )
                )
                assertFalse(player.playWhenReady)
            }
            await { player.duration > 0 && current.controller.state.value.error == null }
            onMain {
                current.controller.togglePlay()
                current.controller.seekTo(600)
                current.controller.selectQuality(Quality.Smooth)
                assertSame(player, current.player)
                assertTrue(player.playWhenReady)
                assertEquals(600L, current.controller.state.value.positionMs)
                current.controller.onBackground(true)
                assertTrue(player.playWhenReady)
                current.controller.onBackground(false)
                assertFalse(player.playWhenReady)
                // A new destination may overlap the old one during its leave transition.
                val overlapping = PlayerSession(context)
                overlapping.release()
                current.release()
                current.release()
            }
        } finally {
            onMain { session?.release() }
            fixture.delete()
        }
    }

    private fun onMain(block: () -> Unit) = InstrumentationRegistry.getInstrumentation().runOnMainSync(block)

    private fun awaitScreenPixel(point: Offset, message: String, matches: (Int) -> Boolean) {
        val deadline = System.nanoTime() + 3_000_000_000L
        var pixel = 0
        while (System.nanoTime() < deadline) {
            val screenshot = requireNotNull(InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
            try {
                pixel = screenshot.getPixel(point.x.toInt(), point.y.toInt())
                if (matches(pixel)) return
            } finally {
                screenshot.recycle()
            }
            Thread.sleep(50)
        }
        throw AssertionError("$message: ${Integer.toHexString(pixel)}")
    }

    @Test
    fun composeSeekAndQualityKeepPausedIntentAndMenusPreventControlsFromHiding() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val fixture = encodeFixture(context, frameCount = 400)
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        var session: PlayerSession? = null
        try {
            onMain { session = PlayerSession(context) }
            val current = requireNotNull(session)
            val originalPlayer = current.player
            val uri = android.net.Uri.fromFile(fixture).toString()
            onMain {
                current.controller.setSource(
                    PlaybackSource(
                        "compose-fixture",
                        "本地测试",
                        listOf(VideoVariant(Quality.Standard, uri), VideoVariant(Quality.Smooth, "$uri?quality=smooth"))
                    )
                )
            }
            await { current.player.playbackState == Player.STATE_READY }
            ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
                scenario.onActivity { host ->
                    host.setContent {
                        MaterialTheme {
                            val state by current.controller.state.collectAsState()
                            PlayerVideo(
                                current.player, state, current.controller::selectQuality, current.controller::setSpeed,
                                false, {}, null, current.controller::retry,
                                Modifier.fillMaxWidth().height(240.dp)
                            )
                        }
                    }
                }
                val progress = requireNotNull(device.wait(Until.findObject(By.desc("播放进度")), 5_000)).visibleBounds
                device.click(progress.left + progress.width() / 6, progress.centerY())
                await { current.player.currentPosition in 4_000..9_000 }
                var seekPosition = 0L
                onMain {
                    assertFalse(current.player.playWhenReady)
                    seekPosition = current.player.currentPosition
                }
                requireNotNull(device.findObject(By.desc("清晰度"))).click()
                requireNotNull(device.wait(Until.findObject(By.text("流畅")), 5_000)).click()
                await {
                    current.player.playbackState == Player.STATE_READY &&
                        current.controller.state.value.quality == Quality.Smooth
                }
                onMain {
                    assertSame(originalPlayer, current.player)
                    assertFalse(current.player.playWhenReady)
                    assertEquals(seekPosition, current.player.currentPosition)
                }
                requireNotNull(device.findObject(By.desc("开始播放"))).click()
                await { current.player.isPlaying }
                requireNotNull(device.findObject(By.desc("播放速度"))).click()
                assertFalse(
                    "An open speed menu must survive the hide delay",
                    device.wait(Until.gone(By.text("1.25×")), 4_000)
                )
                requireNotNull(device.findObject(By.scrollable(true))).scroll(Direction.DOWN, 1f)
                requireNotNull(device.wait(Until.findObject(By.text("2×")), 5_000)).click()
                await { current.player.playbackParameters.speed == 2f }
                val speedControl = requireNotNull(device.findObject(By.desc("播放速度")))
                val speedControlTop = speedControl.visibleBounds.top
                speedControl.click()
                val selected = requireNotNull(
                    device.wait(Until.findObject(By.text("2×").hasAncestor(By.scrollable(true))), 5_000)
                )
                assertTrue("Reopening must reveal the selected speed", selected.visibleBounds.bottom <= speedControlTop)
                device.pressBack()
                assertTrue(
                    "Playing controls must hide after inactivity",
                    device.wait(Until.gone(By.desc("播放进度")), 5_000)
                )
                device.pressKeyCode(KeyEvent.KEYCODE_TAB)
                assertTrue(device.wait(Until.hasObject(By.desc("暂停播放")), 5_000))
                requireNotNull(device.findObject(By.desc("暂停播放"))).click()
                await { !current.player.playWhenReady }
            }
        } finally {
            onMain { session?.release() }
            fixture.delete()
        }
    }

    private fun await(condition: () -> Boolean) {
        val deadline = System.nanoTime() + 15_000_000_000L
        while (System.nanoTime() < deadline) {
            var ready = false
            onMain { ready = condition() }
            if (ready) return
            Thread.sleep(50)
        }
        throw AssertionError("Local Media3 preparation timed out")
    }

    private fun encodeFixture(context: Context, frameCount: Int = 20): File {
        val file = File(context.cacheDir, "video-${UUID.randomUUID()}.mp4")
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 64, 64).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, 32_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, 10)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        val muxer = MediaMuxer(file.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var started = false
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val info = MediaCodec.BufferInfo()
            var frame = 0
            var inputEnded = false
            var outputEnded = false
            var track = -1
            val deadline = System.nanoTime() + 20_000_000_000L
            while (!outputEnded && System.nanoTime() < deadline) {
                if (!inputEnded) {
                    val inputIndex = codec.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        if (frame == frameCount) {
                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                frameCount * 100_000L,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputEnded = true
                        } else {
                            val buffer = requireNotNull(codec.getInputBuffer(inputIndex))
                            buffer.clear()
                            buffer.put(ByteArray(64 * 64) { 32 })
                            buffer.put(ByteArray(64 * 64 / 2) { 128.toByte() })
                            codec.queueInputBuffer(inputIndex, 0, 64 * 64 * 3 / 2, frame * 100_000L, 0)
                            frame++
                        }
                    }
                }
                val outputIndex = codec.dequeueOutputBuffer(info, 10_000)
                if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                    started = true
                } else if (outputIndex >= 0) {
                    if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                        val buffer = requireNotNull(codec.getOutputBuffer(outputIndex))
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        muxer.writeSampleData(track, buffer, info)
                    }
                    outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    codec.releaseOutputBuffer(outputIndex, false)
                }
            }
            check(outputEnded) { "MP4 fixture encoding timed out" }
        } finally {
            codec.stop()
            codec.release()
            if (started) muxer.stop()
            muxer.release()
        }
        return file
    }
}
