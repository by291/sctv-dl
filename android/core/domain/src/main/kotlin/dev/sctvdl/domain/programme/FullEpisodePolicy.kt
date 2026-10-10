package dev.sctvdl.domain.programme

import java.time.LocalDate

fun isFullEpisode(content: ProgrammeContent, programmeName: String, date: LocalDate): Boolean {
    val title = content.title.filterNot(Char::isWhitespace)
    val prefix = programmeName.filterNot(Char::isWhitespace)
    val stamp = date.toString().replace('-', '.')
    return title == "$prefix（$stamp）" || title == "$prefix($stamp)"
}
