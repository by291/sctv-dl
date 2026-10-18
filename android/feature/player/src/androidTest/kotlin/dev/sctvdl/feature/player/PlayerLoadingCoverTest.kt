package dev.sctvdl.feature.player

import android.graphics.Bitmap
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SharedTransitionLayout
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.videoVariants
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.programme.ProgrammeSelection
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.player.media3.PlayerSession
import dev.sctvdl.player.model.PlaybackSource
import dev.sctvdl.ui.programme.LocalProgrammeCoverAnimationScope
import dev.sctvdl.ui.programme.LocalProgrammeCoverSharedScope
import dev.sctvdl.ui.programme.PlaybackCover
import dev.sctvdl.ui.theme.SctvAppTheme
import java.io.File
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class PlayerLoadingCoverTest {
    @get:Rule val compose = createComposeRule()

    @Test fun shortLargeTextWindowCanScrollToRetryBeforePlaybackIsPrepared() {
        var retried = false
        val selection = ProgrammeSelection(
            Programme("programme", "Fixture", null, 0),
            BroadcastDate("date", LocalDate.of(2026, 10, 18)),
            ProgrammeContent("content", "Fixture episode", standardUrl = "fixture.mp4")
        )
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, 2f)) {
                SctvAppTheme(AppSettings()) {
                    Box(Modifier.size(320.dp, 240.dp)) {
                        PlayerScreen(
                            PlayerUiState(loading = false),
                            {},
                            { retried = true },
                            {},
                            {},
                            true,
                            TestPlaybackHost(),
                            selection
                        )
                    }
                }
            }
        }
        compose.onNodeWithText("重试").performScrollTo().performClick()
        compose.runOnIdle { assertTrue("Retry must remain reachable below the loading artwork", retried) }
    }

    @Test fun acceptedArtworkTravelsWhileSourceIsStillLoading() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File(context.cacheDir, "loading-cover.png")
        val bitmap = Bitmap.createBitmap(160, 90, Bitmap.Config.ARGB_8888).apply {
            eraseColor(android.graphics.Color.BLUE)
        }
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
        val url = file.toURI().toString()
        val selection = ProgrammeSelection(
            Programme("programme", "Fixture", url, 0),
            BroadcastDate("date", LocalDate.of(2026, 10, 18)),
            ProgrammeContent(
                "content",
                "Fixture episode",
                coverUrl = url,
                standardUrl = "file:///missing-standard.mp4",
                smoothUrl = "file:///missing-smooth.mp4"
            )
        )
        var boundSession: PlayerSession? = null
        var bindings = 0
        val host = object : PlaybackHost by TestPlaybackHost() {
            override fun bindPlayer(session: PlayerSession) {
                boundSession = session
                bindings++
            }
        }
        val savedPositions = mutableListOf<Long>()
        var state by mutableStateOf(PlayerUiState())
        var player by mutableStateOf(false)

        try {
            compose.setContent {
                SctvAppTheme(AppSettings()) {
                    SharedTransitionLayout {
                        val shared = this
                        AnimatedContent(
                            player,
                            transitionSpec = { fadeIn(tween(300)) togetherWith fadeOut(tween(105)) },
                            label = "Delayed player"
                        ) { destination ->
                            CompositionLocalProvider(
                                LocalProgrammeCoverSharedScope provides shared,
                                LocalProgrammeCoverAnimationScope provides this
                            ) {
                                if (destination) {
                                    PlayerScreen(state, {}, {}, { savedPositions += it }, {}, true, host, selection)
                                } else {
                                    Box(Modifier.fillMaxSize()) {
                                        PlaybackCover(
                                            selection.ref,
                                            url,
                                            Modifier.offset(24.dp, 300.dp).size(120.dp, 90.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            compose.waitUntil(5_000) { artworkPixels() > 1_000 }
            val original = artworkPixels()
            compose.mainClock.autoAdvance = false
            compose.runOnIdle { player = true }
            compose.mainClock.advanceTimeByFrame()
            compose.mainClock.advanceTimeBy(160)
            assertTrue("The cover grows into the player before a source exists", artworkPixels() > original)

            compose.mainClock.advanceTimeBy(600)
            assertTrue("Slow history restoration must keep the destination artwork mounted", artworkPixels() > original)
            compose.onNodeWithText("准备播放").assertDoesNotExist()
            compose.onNodeWithText("正在获取节目视频").assertDoesNotExist()
            compose.onNodeWithText("Fixture episode").assertExists()
            val session = requireNotNull(boundSession)
            compose.runOnIdle {
                assertNull("Media must wait for saved progress and settings", session.controller.state.value.sourceId)
                assertTrue("An unprepared player must not overwrite the resume point", savedPositions.isEmpty())
                state = PlayerUiState(
                    loading = false,
                    source = PlaybackSource(
                        selection.content.id,
                        selection.content.title,
                        videoVariants(selection.content),
                        startPositionMs = 42_000
                    ),
                    content = selection.content,
                    initialQuality = Quality.Smooth,
                    selection = selection
                )
            }
            compose.mainClock.advanceTimeByFrame()
            compose.runOnIdle {
                assertSame("Preparation must retain the same player page", session, boundSession)
                assertEquals(1, bindings)
                assertEquals(Quality.Smooth, session.controller.state.value.quality)
                assertEquals(selection.content.id, session.controller.state.value.sourceId)
                assertEquals(42_000L, session.controller.state.value.positionMs)
                assertTrue("Restored progress must reach persistence", 42_000L in savedPositions)
                assertTrue("The preparation handoff must not save zero", 0L !in savedPositions)
            }
        } finally {
            file.delete()
        }
    }

    private fun artworkPixels(): Int {
        val pixels = compose.onRoot().captureToImage().toPixelMap()
        var count = 0
        for (y in 0 until pixels.height step 2) {
            for (x in 0 until pixels.width step 2) {
                val color = pixels[x, y]
                if (color.blue > 0.5f && color.red < 0.1f && color.green < 0.1f) count++
            }
        }
        return count
    }
}
