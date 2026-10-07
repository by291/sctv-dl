package dev.sctvdl.player

import dev.sctvdl.domain.VideoVariant

data class PlaybackSource(
    val id: String,
    val title: String,
    val variants: List<VideoVariant> = emptyList(),
    val localUri: String? = null,
    val startPositionMs: Long = 0
)
data class BackendSnapshot(
    val positionMs: Long = 0,
    val durationMs: Long? = null,
    val playing: Boolean = false,
    val buffering: Boolean = false,
    val error: String? = null
)

interface PlaybackBackend {
    val positionMs: Long
    var playWhenReady: Boolean
    var speed: Float
    fun setListener(listener: (Long, BackendSnapshot) -> Unit)
    fun setMedia(uri: String, token: Long, positionMs: Long)
    fun prepare()
    fun seekTo(positionMs: Long)
    fun snapshot(): BackendSnapshot = BackendSnapshot(
        positionMs = positionMs,
        playing = playWhenReady
    )
    fun release()
}
