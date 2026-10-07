@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package dev.sctvdl.player

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import dev.sctvdl.domain.Quality
import dev.sctvdl.domain.VideoVariant
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

    private fun encodeFixture(context: Context): File {
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
                        if (frame == 20) {
                            codec.queueInputBuffer(inputIndex, 0, 0, 2_000_000, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
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
