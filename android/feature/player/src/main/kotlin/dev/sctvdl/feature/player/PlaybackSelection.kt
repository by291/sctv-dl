package dev.sctvdl.feature.player

import dev.sctvdl.domain.programme.ProgrammeContent
import java.time.LocalDate

data class PlaybackSelection(
    val programmeId: String,
    val dateId: String,
    val content: ProgrammeContent,
    val programmeName: String,
    val broadcastDate: LocalDate
)
