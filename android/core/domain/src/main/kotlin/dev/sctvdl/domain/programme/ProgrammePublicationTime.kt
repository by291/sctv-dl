package dev.sctvdl.domain.programme

import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.format.ResolverStyle
import java.util.Locale

private val PublicationTimeFormat = DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm:ss", Locale.ROOT)
    .withResolverStyle(ResolverStyle.STRICT)

fun ProgrammeContent.publicationTime(): LocalDateTime? = try {
    publishedAt?.trim()?.takeIf { it.isNotEmpty() }?.let { LocalDateTime.parse(it, PublicationTimeFormat) }
} catch (_: DateTimeParseException) {
    null
}

fun sortContentsByPublicationTime(contents: List<ProgrammeContent>, ascending: Boolean = true): List<ProgrammeContent> =
    contents.map {
        it to
            it.publicationTime()
    }.sortedWith { left, right ->
        val leftTime = left.second
        val rightTime = right.second
        when {
            leftTime == null && rightTime == null -> 0
            leftTime == null -> 1
            rightTime == null -> -1
            ascending -> leftTime.compareTo(rightTime)
            else -> rightTime.compareTo(leftTime)
        }
    }.map { it.first }
