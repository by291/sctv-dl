package dev.sctvdl.player.model

data class PlaybackBackendSnapshot(
    val positionMs: Long = 0,
    val durationMs: Long? = null,
    val playing: Boolean = false,
    val buffering: Boolean = false,
    val error: String? = null,
    val ready: Boolean = false,
    val ended: Boolean = false,
    val firstFrameRendered: Boolean = false
)
