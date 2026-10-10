package dev.sctvdl.feature.programmes.archive

import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.programme.publicationTime
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

private val ClipClockFormat = DateTimeFormatter.ofPattern("HH:mm:ss", Locale.ROOT)
private val ClipDateTimeFormat = DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm:ss", Locale.ROOT)

internal fun clipPublicationLabel(content: ProgrammeContent, broadcastDate: LocalDate?): String {
    val time = content.publicationTime() ?: return "时间未知"
    return time.format(if (time.toLocalDate() == broadcastDate) ClipClockFormat else ClipDateTimeFormat)
}
