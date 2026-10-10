package dev.sctvdl.player.controller

import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.VideoVariant
import dev.sctvdl.player.controller.PlaybackBackend
import dev.sctvdl.player.controller.PlaybackController
import dev.sctvdl.player.model.PlaybackBackendSnapshot
import dev.sctvdl.player.model.PlaybackSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackControllerTest {
    private class Backend : PlaybackBackend {
        override var positionMs = 0L
        override var playWhenReady = false
        override var speed = 1f
        var uri: String? = null
        var token = 0L
        var releases = 0
        var prepares = 0
        var callback: ((Long, PlaybackBackendSnapshot) -> Unit)? = null

        override fun setListener(listener: (Long, PlaybackBackendSnapshot) -> Unit) {
            this.callback = listener
        }

        override fun setMedia(uri: String, token: Long, positionMs: Long) {
            this.uri = uri
            this.token = token
            this.positionMs = positionMs
        }

        override fun prepare() {
            prepares++
        }

        override fun seekTo(positionMs: Long) {
            this.positionMs = positionMs
        }

        override fun release() {
            releases++
        }
    }

    private val source =
        PlaybackSource(
            "1",
            "新闻",
            listOf(
                VideoVariant(Quality.Standard, "standard.mp4"),
                VideoVariant(Quality.Smooth, "smooth.mp4")
            )
        )

    @Test fun initialPlaybackIsPausedAndQualitySwitchKeepsPositionAndIntent() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)
        assertEquals("standard.mp4", backend.uri)
        assertFalse(backend.playWhenReady)
        backend.positionMs = 12345
        controller.togglePlay()
        controller.selectQuality(Quality.Smooth)
        assertEquals("smooth.mp4", backend.uri)
        assertEquals(12345, backend.positionMs)
        assertTrue(backend.playWhenReady)
        assertEquals(0, backend.releases)
    }

    @Test fun duplicateQualitySourcesDoNotExposeTwoChoices() {
        val controller = PlaybackController(Backend())
        controller.setSource(
            source.copy(
                variants = listOf(
                    VideoVariant(Quality.Standard, "same.mp4"),
                    VideoVariant(Quality.Smooth, "same.mp4")
                )
            )
        )
        assertEquals(1, controller.state.value.variants.size)
    }

    @Test fun staleCallbacksCannotChangeANewSourceAndRetryClearsErrors() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)
        val old = backend.token
        controller.setSource(source.copy(id = "2"))
        backend.callback?.invoke(old, PlaybackBackendSnapshot(error = "old source failed"))
        assertNull(controller.state.value.error)
        backend.callback?.invoke(backend.token, PlaybackBackendSnapshot(error = "current failed"))
        assertEquals("current failed", controller.state.value.error)
        controller.retry()
        assertNull(controller.state.value.error)
        assertEquals(3, backend.prepares)
    }

    @Test fun ordinaryBackgroundPausesButExplicitPipContinuesAndReleaseIsIdempotent() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)
        controller.togglePlay()
        controller.onBackground(true)
        assertTrue(backend.playWhenReady)
        controller.onBackground(false)
        assertFalse(backend.playWhenReady)
        controller.release()
        controller.release()
        assertEquals(1, backend.releases)
    }

    @Test fun cancelledBackPreviewDoesNotDismissUntilTheCommitAction() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)
        controller.togglePlay()
        assertTrue(backend.playWhenReady)
        assertEquals(0, backend.releases)
        controller.pauseForDismissal()
        assertFalse(backend.playWhenReady)
        assertEquals(0, backend.releases)
        controller.release()
        assertEquals(1, backend.releases)
    }
}
