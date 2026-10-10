package dev.sctvdl.feature.programmes.archive

import dev.sctvdl.domain.programme.ProgrammeContent
import java.time.LocalDate

data class ArchivePlaybackSelection(
    val programmeId: String,
    val dateId: String,
    val content: ProgrammeContent,
    val programmeName: String,
    val broadcastDate: LocalDate
)
