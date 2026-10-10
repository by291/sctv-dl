package dev.sctvdl.domain.download

import dev.sctvdl.domain.media.Quality
import java.time.LocalDate

fun safeDownloadFilename(date: LocalDate, title: String, quality: Quality, suffix: String = ""): String {
    fun clean(value: String) = value.replace(
        Regex("[\\p{Cntrl}<>:\"/\\\\|?*]"),
        "_"
    ).trim().trimEnd(
        '.',
        ' '
    )

    fun takeUtf8(value: String, budget: Int): String {
        var end = 0
        var bytes = 0
        while (end < value.length) {
            val codePoint = value.codePointAt(end)
            val width = when {
                codePoint <= 0x7f -> 1
                codePoint <= 0x7ff -> 2
                codePoint <= 0xffff -> 3
                else -> 4
            }
            if (bytes + width > budget) break
            bytes += width
            end += Character.charCount(codePoint)
        }
        return value.substring(0, end)
    }

    val tail = "_${quality.label}" +
        suffix.takeIf { it.isNotBlank() }?.let { "_${takeUtf8(clean(it), 96)}" }.orEmpty() + ".mp4"
    val prefix = "${date}_"
    // External storage limits the complete filename in bytes, not UTF-16 characters.
    val budget = 255 - prefix.toByteArray(Charsets.UTF_8).size - tail.toByteArray(Charsets.UTF_8).size
    val safeTitle = takeUtf8(clean(title).ifBlank { "节目" }, budget).trimEnd('.', ' ')
    return "$prefix$safeTitle$tail"
}
