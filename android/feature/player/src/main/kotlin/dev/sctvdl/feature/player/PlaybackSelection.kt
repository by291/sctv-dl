package dev.sctvdl.feature.player

import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.programme.ProgrammeSelection
import java.time.LocalDate

data class PlaybackSelection(
    val programmeId: String,
    val dateId: String,
    val content: ProgrammeContent,
    val programmeName: String,
    val broadcastDate: LocalDate,
    val programmeCoverUrl: String? = null
) {
    val accepted: ProgrammeSelection get() = ProgrammeSelection(
        Programme(programmeId, programmeName, programmeCoverUrl, 0),
        BroadcastDate(dateId, broadcastDate),
        content
    )
}
