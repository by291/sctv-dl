package dev.sctvdl.feature.player

import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.player.model.PlaybackSource
import java.time.LocalDate

internal data class PlayerUiState(
    val loading: Boolean = true,
    val source: PlaybackSource? = null,
    val content: ProgrammeContent? = null,
    val error: AppError? = null,
    val initialQuality: Quality = Quality.Standard,
    val programmeName: String = "节目",
    val broadcastDate: LocalDate? = null
)
