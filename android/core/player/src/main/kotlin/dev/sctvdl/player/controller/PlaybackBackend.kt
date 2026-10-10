package dev.sctvdl.player.controller

import dev.sctvdl.player.model.PlaybackBackendSnapshot

interface PlaybackBackend {
    val positionMs: Long
    var playWhenReady: Boolean
    var speed: Float
    fun setListener(listener: (Long, PlaybackBackendSnapshot) -> Unit)
    fun setMedia(uri: String, token: Long, positionMs: Long)
    fun prepare()
    fun seekTo(positionMs: Long)
    fun snapshot(): PlaybackBackendSnapshot = PlaybackBackendSnapshot(
        positionMs = positionMs,
        playing = playWhenReady
    )
    fun release()
}
