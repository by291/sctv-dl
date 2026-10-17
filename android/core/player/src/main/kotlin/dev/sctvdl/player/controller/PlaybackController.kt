package dev.sctvdl.player.controller

import dev.sctvdl.domain.media.Quality
import dev.sctvdl.player.model.PlaybackBackendSnapshot
import dev.sctvdl.player.model.PlaybackPhase
import dev.sctvdl.player.model.PlaybackSource
import dev.sctvdl.player.model.PlaybackState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Owns playback intent independently of decoder preparation and rolls a failed quality switch back once. */
class PlaybackController(private val backend: PlaybackBackend, private val initialQuality: Quality = Quality.Standard) {
    private data class Context(val uri: String, val quality: Quality?, val position: Long, val speed: Float)

    private data class Switch(val target: Context, val previous: Context?, val recovering: Boolean = false)

    private val mutableState = MutableStateFlow(PlaybackState())
    val state = mutableState.asStateFlow()

    private var token = 0L
    private var current: Context? = null
    private var usable: Context? = null
    private var pending: Switch? = null
    private var desiredPlaying = false
    private var released = false
    private var temporarySpeed = false

    init {
        backend.setListener { callbackToken, snapshot ->
            // Replaced media and released sessions cannot commit a pending quality or trigger recovery.
            if (callbackToken == token && !released) apply(snapshot)
        }
        backend.setExternalPlaybackListener { playing ->
            if (!playing) endTemporarySpeed()
            desiredPlaying = playing
            mutableState.update { it.copy(playWhenReady = playing) }
        }
    }

    fun setSource(source: PlaybackSource) {
        if (released) return

        endTemporarySpeed()
        val variants = source.variants.distinctBy { it.url }
        val selected = variants.firstOrNull { it.quality == initialQuality } ?: variants.firstOrNull()
        pending = null
        usable = null
        current = null
        desiredPlaying = false
        mutableState.value = PlaybackState(
            sourceId = source.id,
            variants = variants,
            quality = selected?.quality,
            positionMs = source.startPositionMs
        )

        val uri = source.localUri ?: selected?.url
        if (uri == null) {
            token++
            mutableState.update { it.copy(error = "暂无可播放的视频") }
        } else {
            load(Context(uri, selected?.quality, source.startPositionMs, 1f))
        }
    }

    fun selectQuality(quality: Quality) {
        if (released || quality == (pending?.target?.quality ?: state.value.quality)) return

        endTemporarySpeed()
        val variant = state.value.variants.firstOrNull { it.quality == quality } ?: return
        val previous = if (usable != null && pending == null && state.value.error == null) {
            current?.copy(position = backend.positionMs, speed = state.value.speed)
        } else {
            pending?.previous ?: usable
        }
        val target = Context(variant.url, quality, previous?.position ?: state.value.positionMs, state.value.speed)
        pending = Switch(target, previous)
        mutableState.update { it.copy(phase = PlaybackPhase.Switching, notice = null) }
        load(target)
    }

    private fun load(context: Context) {
        current = context
        token++
        mutableState.update {
            it.copy(
                positionMs = context.position.coerceAtLeast(0),
                error = null,
                buffering = true,
                playing = false,
                ready = false,
                ended = false,
                firstFrameRendered = false,
                playWhenReady = desiredPlaying,
                speed = context.speed
            )
        }

        backend.setMedia(context.uri, token, context.position.coerceAtLeast(0))
        backend.speed = context.speed
        backend.playWhenReady = desiredPlaying
        backend.prepare()
    }

    fun setSpeed(speed: Float) {
        if (released || speed !in 0.5f..2f) return

        temporarySpeed = false
        backend.speed = speed
        current = current?.copy(speed = speed)
        pending =
            pending?.let {
                it.copy(target = it.target.copy(speed = speed), previous = it.previous?.copy(speed = speed))
            }
        mutableState.update { it.copy(speed = speed) }
    }

    fun beginTemporarySpeed() {
        if (released || !state.value.playing) return
        temporarySpeed = true
        backend.speed = 2f
    }

    fun endTemporarySpeed() {
        if (!temporarySpeed) return
        temporarySpeed = false
        backend.speed = state.value.speed
    }

    fun togglePlay() {
        if (released) return

        endTemporarySpeed()
        desiredPlaying = state.value.ended || !desiredPlaying
        if (desiredPlaying && state.value.ended) backend.seekTo(0)
        backend.playWhenReady = desiredPlaying
        tick()
    }

    fun seekTo(positionMs: Long) {
        if (released) return

        val duration = state.value.durationMs?.takeIf { it > 0 } ?: return
        val position = positionMs.coerceIn(0, duration)
        current = current?.copy(position = position)
        pending = pending?.let {
            it.copy(target = it.target.copy(position = position), previous = it.previous?.copy(position = position))
        }
        backend.seekTo(position)
        tick()
    }

    fun retry() {
        if (released) return
        endTemporarySpeed()
        val context = current ?: return

        pending = null
        mutableState.update { it.copy(phase = PlaybackPhase.Normal, notice = null) }
        load(context)
    }

    fun tick() {
        if (!released) apply(backend.snapshot())
    }

    private fun apply(snapshot: PlaybackBackendSnapshot) {
        if (!snapshot.playing) endTemporarySpeed()
        val operation = pending
        if (snapshot.error != null && operation != null) {
            val previous = operation.previous
            if (!operation.recovering && previous != null) {
                pending = Switch(previous, previous, recovering = true)
                mutableState.update { it.copy(phase = PlaybackPhase.Recovering, notice = "清晰度切换失败，正在恢复原视频") }
                load(previous)
                return
            }
            // Retain the last load context for explicit retry; decoder failures can reset its position to zero.
            pending = null
            mutableState.update { it.copy(phase = PlaybackPhase.Normal) }
        }
        if (snapshot.ready && snapshot.error == null) {
            usable = current?.copy(position = snapshot.positionMs, speed = state.value.speed)
            current = usable
            pending = null
            mutableState.update {
                it.copy(
                    quality = usable?.quality,
                    phase = PlaybackPhase.Normal,
                    notice = if (operation?.recovering == true) "清晰度切换失败，已恢复原视频" else it.notice
                )
            }
        }
        mutableState.update {
            it.copy(
                positionMs = if (snapshot.error !=
                    null
                ) {
                    current?.position ?: snapshot.positionMs
                } else {
                    snapshot.positionMs
                },
                durationMs = snapshot.durationMs,
                playing = snapshot.playing,
                buffering = snapshot.buffering,
                error = snapshot.error,
                playWhenReady = desiredPlaying,
                ready = snapshot.ready,
                ended = snapshot.ended,
                firstFrameRendered = snapshot.firstFrameRendered
            )
        }
    }

    fun pauseForDismissal() {
        if (released) return
        endTemporarySpeed()
        desiredPlaying = false
        backend.playWhenReady = false
        tick()
    }

    fun onBackground(inPictureInPicture: Boolean) {
        endTemporarySpeed()
        if (!inPictureInPicture) pauseForDismissal()
    }

    fun release() {
        if (released) return
        pauseForDismissal()
        released = true
        pending = null
        backend.release()
    }
}
