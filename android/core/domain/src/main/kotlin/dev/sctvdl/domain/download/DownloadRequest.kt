package dev.sctvdl.domain.download

import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.programme.ProgrammeSelection
import java.time.LocalDate

data class DownloadRequest(
    val programmeName: String,
    val broadcastDate: LocalDate,
    val content: ProgrammeContent,
    val requestedQuality: Quality,
    val wifiOnly: Boolean,
    val selection: ProgrammeSelection? = null
)
