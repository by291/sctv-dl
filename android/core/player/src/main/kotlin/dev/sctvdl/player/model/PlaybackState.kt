package dev.sctvdl.player.model

import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.VideoVariant

enum class PlaybackPhase { Normal, Switching, Recovering }

data class PlaybackState(
    val phase: PlaybackPhase = PlaybackPhase.Normal,
    val notice: String? = null,
    val sourceId: String? = null,
    val variants: List<VideoVariant> = emptyList(),
    val quality: Quality? = null,
    val positionMs: Long = 0,
    val durationMs: Long? = null,
    val playing: Boolean = false,
    val buffering: Boolean = false,
    val speed: Float = 1f,
    val error: String? = null,
    val playWhenReady: Boolean = false,
    val ready: Boolean = false,
    val ended: Boolean = false,
    val firstFrameRendered: Boolean = false
)
