package dev.sctvdl.player.model

import dev.sctvdl.domain.media.VideoVariant

data class PlaybackSource(
    val id: String,
    val title: String,
    val variants: List<VideoVariant> = emptyList(),
    val localUri: String? = null,
    val startPositionMs: Long = 0
)
