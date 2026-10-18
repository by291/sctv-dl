package dev.sctvdl.ui

import android.graphics.Bitmap
import android.graphics.Rect
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SharedTransitionLayout
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import dev.sctvdl.domain.programme.ContentRef
import dev.sctvdl.ui.programme.LocalProgrammeCoverAnimationScope
import dev.sctvdl.ui.programme.LocalProgrammeCoverSharedScope
import dev.sctvdl.ui.programme.PlaybackCover
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class PlaybackCoverTest {
    @get:Rule val compose = createComposeRule()

    @Test fun earlyVideoFrameWaitsForEntryAndArtworkReturnsAfterPlayback() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val cover = File(context.cacheDir, "playback-cover-test.png")
        val bitmap = Bitmap.createBitmap(160, 90, Bitmap.Config.ARGB_8888).apply {
            eraseColor(android.graphics.Color.BLUE)
        }
        cover.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
        var inPlayer by mutableStateOf(false)
        var ready by mutableStateOf(false)
        val reference = ContentRef("programme", "date", "content")

        try {
            compose.setContent {
                SharedTransitionLayout {
                    val shared = this
                    val retained = rememberSaveableStateHolder()
                    AnimatedContent(
                        inPlayer,
                        transitionSpec = { fadeIn(tween(300)) togetherWith fadeOut(tween(105)) },
                        label = "Playback destination"
                    ) { player ->
                        retained.SaveableStateProvider(player) {
                            CompositionLocalProvider(
                                LocalProgrammeCoverSharedScope provides shared,
                                LocalProgrammeCoverAnimationScope provides this
                            ) {
                                Box(Modifier.fillMaxSize().background(Color.Black)) {
                                    val bounds = if (player) {
                                        Modifier.size(320.dp, 180.dp)
                                    } else {
                                        Modifier.offset(24.dp, 220.dp).size(120.dp, 90.dp)
                                    }
                                    if (player) Box(bounds.background(Color.Green))
                                    PlaybackCover(
                                        reference,
                                        cover.toURI().toString(),
                                        bounds,
                                        cornerRadius = if (player) 0.dp else 8.dp,
                                        videoReady = if (player) ready else null
                                    )
                                }
                            }
                        }
                    }
                }
            }
            compose.waitUntil(5_000) { bluePixels() > 1_000 }
            val original = blueBounds()
            compose.mainClock.autoAdvance = false

            compose.runOnIdle { inPlayer = true }
            compose.mainClock.advanceTimeByFrame()
            compose.runOnIdle { ready = true }
            compose.mainClock.advanceTimeBy(160)
            assertTrue("A decoded frame must not remove artwork during entry", bluePixels() > 1_000)
            val entering = blueBounds()
            assertTrue(
                "Artwork must travel from the archive into the video: $entering",
                entering.top in 1 until original.top
            )
            assertTrue("Artwork grows from the archive cover", entering.width() > original.width())

            compose.mainClock.advanceTimeBy(600)
            assertEquals("The video is revealed after entry and first frame", 0, bluePixels())

            compose.runOnIdle { inPlayer = false }
            compose.mainClock.advanceTimeByFrame()
            compose.mainClock.advanceTimeBy(80)
            assertTrue(
                "Artwork must fade back over the departing video",
                bluePixels() > 1_000
            )
            val returning = blueBounds()
            assertTrue(
                "The return must reverse the shared cover flight: $returning",
                returning.top in 1 until original.top
            )
            compose.mainClock.advanceTimeBy(500)
            assertTrue("Returning must restore the archive artwork", bluePixels() > 1_000)
        } finally {
            cover.delete()
        }
    }

    private fun bluePixels(): Int {
        val pixels = compose.onRoot().captureToImage().toPixelMap()
        var count = 0
        for (y in 0 until pixels.height step 2) {
            for (x in 0 until pixels.width step 2) {
                val color = pixels[x, y]
                if (color.blue > 0.2f && color.blue > color.red * 2) count++
            }
        }
        return count
    }

    private fun blueBounds(): Rect {
        val pixels = compose.onRoot().captureToImage().toPixelMap()
        val bounds = Rect(pixels.width, pixels.height, 0, 0)
        for (y in 0 until pixels.height step 2) {
            for (x in 0 until pixels.width step 2) {
                val color = pixels[x, y]
                // Returning artwork blends with the green video fixture before it becomes opaque.
                if (color.blue > 0.2f && color.blue > color.red * 2) {
                    bounds.left = minOf(bounds.left, x)
                    bounds.top = minOf(bounds.top, y)
                    bounds.right = maxOf(bounds.right, x)
                    bounds.bottom = maxOf(bounds.bottom, y)
                }
            }
        }
        return bounds
    }
}
