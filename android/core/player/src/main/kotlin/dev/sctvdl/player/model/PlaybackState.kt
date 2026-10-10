package dev.sctvdl.player.model

import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.VideoVariant

data class PlaybackState(
    val sourceId: String? = null,
    val variants: List<VideoVariant> = emptyList(),
    val quality: Quality? = null,
    val positionMs: Long = 0,
    val durationMs: Long? = null,
    val playing: Boolean = false,
    val buffering: Boolean = false,
    val speed: Float = 1f,
    val error: String? = null,
    val playWhenReady: Boolean = false
)
