package dev.sctvdl.player.model

data class PlaybackBackendSnapshot(
    val positionMs: Long = 0,
    val durationMs: Long? = null,
    val playing: Boolean = false,
    val buffering: Boolean = false,
    val error: String? = null
)
