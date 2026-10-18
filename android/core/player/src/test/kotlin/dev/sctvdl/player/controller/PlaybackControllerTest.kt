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
        var externalIntent: ((Boolean) -> Unit)? = null

        override fun setExternalPlaybackListener(listener: (Boolean) -> Unit) {
            externalIntent = listener
        }

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

    @Test fun qualityCheckpointUsesSelectedSpeedInsteadOfTransientDecoderSpeed() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)
        backend.emit(ready = true)
        controller.setSpeed(1.5f)
        backend.speed = 2f

        controller.selectQuality(Quality.Smooth)

        assertEquals(1.5f, backend.speed)
        backend.emit(error = "replacement failed")
        assertEquals(1.5f, backend.speed)
        controller.retry()
        assertEquals(1.5f, backend.speed)
    }

    @Test fun unknownDurationRejectsSeekRatherThanInventingABound() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)

        controller.seekTo(30_000)

        assertEquals(0L, backend.positionMs)
    }

    @Test fun temporarySpeedRestoresSelectionOnReleaseBackgroundAndQualitySwitch() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)
        controller.setSpeed(1.25f)
        controller.beginTemporarySpeed()
        assertEquals(1.25f, backend.speed)
        controller.togglePlay()
        backend.callback?.invoke(backend.token, PlaybackBackendSnapshot(playing = true, ready = true))

        controller.beginTemporarySpeed()
        assertEquals(2f, backend.speed)
        assertEquals(1.25f, controller.state.value.speed)
        controller.endTemporarySpeed()
        assertEquals(1.25f, backend.speed)
        controller.beginTemporarySpeed()
        controller.onBackground(true)
        assertEquals(1.25f, backend.speed)
        assertTrue(backend.playWhenReady)
        controller.beginTemporarySpeed()
        controller.selectQuality(Quality.Smooth)
        assertEquals(1.25f, backend.speed)
    }

    @Test fun boundedSeekPreservesPausedIntent() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)
        backend.callback?.invoke(backend.token, PlaybackBackendSnapshot(durationMs = 10_000))

        controller.seekTo(30_000)

        assertEquals(10_000L, backend.positionMs)
        assertFalse(backend.playWhenReady)
    }

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

    private fun Backend.emit(ready: Boolean = false, error: String? = null) {
        callback?.invoke(token, PlaybackBackendSnapshot(positionMs = positionMs, ready = ready, error = error))
    }

    @Test fun failedSwitchRestoresLastUsableQualityPositionAndSpeedOnlyOnce() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)
        backend.emit(ready = true)
        backend.positionMs = 12_000
        controller.setSpeed(1.5f)
        controller.togglePlay()

        controller.selectQuality(Quality.Smooth)
        assertEquals(Quality.Standard, controller.state.value.quality)
        backend.positionMs = 0
        backend.emit(error = "replacement failed")

        assertEquals("standard.mp4", backend.uri)
        assertEquals(12_000L, backend.positionMs)
        assertEquals(1.5f, backend.speed)
        assertTrue(backend.playWhenReady)
        backend.emit(ready = true)
        assertNull(controller.state.value.error)
        assertTrue(controller.state.value.notice != null)
        assertEquals(Quality.Standard, controller.state.value.quality)
        assertEquals(3, backend.prepares)
    }

    @Test fun pauseDuringSwitchWinsOverRollbackAndLateTargetCallbacks() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)
        backend.emit(ready = true)
        controller.togglePlay()
        controller.selectQuality(Quality.Smooth)
        val replacedToken = backend.token
        controller.togglePlay()
        backend.emit(error = "replacement failed")
        backend.callback?.invoke(replacedToken, PlaybackBackendSnapshot(ready = true))
        backend.emit(ready = true)
        assertFalse(backend.playWhenReady)
        assertEquals(Quality.Standard, controller.state.value.quality)
    }

    @Test fun failedRollbackRetainsRetryContextWithoutAutomaticallyLooping() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)
        backend.emit(ready = true)
        backend.positionMs = 12_000
        controller.selectQuality(Quality.Smooth)
        backend.emit(error = "replacement failed")
        backend.positionMs = 0
        backend.emit(error = "restore failed")
        backend.emit(error = "restore failed")
        assertEquals(3, backend.prepares)
        assertEquals("restore failed", controller.state.value.error)

        controller.onBackground(false)
        controller.retry()
        assertEquals("standard.mp4", backend.uri)
        assertEquals(12_000L, backend.positionMs)
        assertFalse(backend.playWhenReady)
        assertEquals(4, backend.prepares)
    }

    @Test fun qualityIsCommittedOnlyAfterReplacementIsReady() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)
        backend.emit(ready = true)
        controller.selectQuality(Quality.Smooth)
        assertEquals(Quality.Standard, controller.state.value.quality)
        backend.emit(ready = true)
        assertEquals(Quality.Smooth, controller.state.value.quality)
    }

    @Test fun endedPlaybackRestartsOnTheFirstPlayPress() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)
        controller.togglePlay()
        backend.positionMs = 60_000
        backend.callback?.invoke(backend.token, PlaybackBackendSnapshot(positionMs = 60_000, ended = true))
        controller.togglePlay()
        assertEquals(0L, backend.positionMs)
        assertTrue(backend.playWhenReady)
    }

    @Test fun externalPlayCommandUpdatesTheNextPauseAndQualityIntent() {
        val backend = Backend()
        val controller = PlaybackController(backend)
        controller.setSource(source)
        backend.playWhenReady = true
        backend.externalIntent?.invoke(true)
        controller.selectQuality(Quality.Smooth)
        assertTrue(backend.playWhenReady)
        controller.togglePlay()
        assertFalse(backend.playWhenReady)
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
