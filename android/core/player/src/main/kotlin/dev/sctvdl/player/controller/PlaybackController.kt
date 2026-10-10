package dev.sctvdl.player.controller

import dev.sctvdl.domain.media.Quality
import dev.sctvdl.player.model.PlaybackBackendSnapshot
import dev.sctvdl.player.model.PlaybackSource
import dev.sctvdl.player.model.PlaybackState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

class PlaybackController(private val backend: PlaybackBackend, private val initialQuality: Quality = Quality.Standard) {
    private val mutableState = MutableStateFlow(PlaybackState())
    val state = mutableState.asStateFlow()
    private var token = 0L
    private var source: PlaybackSource? = null
    private var currentUri: String? = null
    private var released = false

    init {
        backend.setListener { callbackToken, snapshot ->
            if (callbackToken == token && !released) apply(snapshot)
        }
    }

    fun setSource(source: PlaybackSource) {
        if (released) return
        this.source = source
        val variants = source.variants.distinctBy { it.url }
        val selected =
            variants.firstOrNull { it.quality == initialQuality } ?: variants.firstOrNull()
        mutableState.value =
            PlaybackState(
                sourceId = source.id,
                variants = variants,
                quality = selected?.quality,
                positionMs = source.startPositionMs
            )
        val uri = source.localUri ?: selected?.url
        if (uri == null) {
            mutableState.update { it.copy(error = "暂无可播放的视频") }
        } else {
            load(uri, source.startPositionMs, false)
        }
    }

    fun selectQuality(quality: Quality) {
        if (released || quality == state.value.quality) return
        val variant = state.value.variants.firstOrNull { it.quality == quality } ?: return
        val position = backend.positionMs
        val playing = backend.playWhenReady
        mutableState.update { it.copy(quality = quality) }
        load(variant.url, position, playing)
    }

    private fun load(uri: String, position: Long, playing: Boolean) {
        currentUri = uri
        token++
        mutableState.update {
            it.copy(
                positionMs = position.coerceAtLeast(0),
                error = null,
                buffering = true,
                playWhenReady = playing
            )
        }
        backend.setMedia(uri, token, position.coerceAtLeast(0))
        backend.playWhenReady = playing
        backend.prepare()
    }

    fun setSpeed(speed: Float) {
        if (released || speed !in 0.5f..2f) return
        backend.speed = speed
        mutableState.update { it.copy(speed = speed) }
    }

    fun togglePlay() {
        if (released) return
        backend.playWhenReady = !backend.playWhenReady
        tick()
    }

    fun seekTo(positionMs: Long) {
        if (released) return
        backend.seekTo(positionMs.coerceIn(0, state.value.durationMs ?: Long.MAX_VALUE))
        tick()
    }

    fun retry() {
        if (!released) currentUri?.let { load(it, backend.positionMs, backend.playWhenReady) }
    }
    fun tick() {
        if (!released) apply(backend.snapshot())
    }
    private fun apply(snapshot: PlaybackBackendSnapshot) {
        mutableState.update {
            it.copy(
                positionMs = snapshot.positionMs,
                durationMs = snapshot.durationMs,
                playing = snapshot.playing,
                buffering = snapshot.buffering,
                error = snapshot.error,
                playWhenReady = backend.playWhenReady
            )
        }
    }

    fun pauseForDismissal() {
        if (!released) {
            backend.playWhenReady = false
            tick()
        }
    }

    fun onBackground(inPictureInPicture: Boolean) {
        if (!inPictureInPicture) pauseForDismissal()
    }

    fun release() {
        if (released) return
        pauseForDismissal()
        released = true
        backend.release()
    }
}
