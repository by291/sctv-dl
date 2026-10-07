package dev.sctvdl.domain

import java.text.Collator
import java.time.LocalDate
import java.util.Locale

fun videoVariants(content: ProgrammeContent): List<VideoVariant> = buildList {
    content.standardUrl?.takeIf { it.isNotBlank() }?.let { add(VideoVariant(Quality.Standard, it)) }
    content.smoothUrl?.takeIf {
        it.isNotBlank() && it != content.standardUrl
    }?.let { add(VideoVariant(Quality.Smooth, it)) }
}

fun resolveVideo(content: ProgrammeContent, requested: Quality): VideoVariant? {
    val variants = videoVariants(content)
    return variants.firstOrNull { it.quality == requested } ?: variants.firstOrNull()
}

fun isFullEpisode(content: ProgrammeContent, programmeName: String, date: LocalDate): Boolean {
    val title = content.title.filterNot(Char::isWhitespace)
    val prefix = programmeName.filterNot(Char::isWhitespace)
    val stamp = date.toString().replace('-', '.')
    return title == "$prefix（$stamp）" || title == "$prefix($stamp)"
}

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

fun sortProgrammes(programmes: List<Programme>, favourites: Set<String>, byName: Boolean): List<Programme> {
    val collator = Collator.getInstance(Locale.SIMPLIFIED_CHINESE)
    return programmes.sortedWith { left, right ->
        val group = (left.id !in favourites).compareTo(right.id !in favourites)
        if (group != 0) {
            group
        } else if (byName) {
            val name = collator.compare(left.name, right.name)
            if (name != 0) name else left.serviceOrder.compareTo(right.serviceOrder)
        } else {
            left.serviceOrder.compareTo(right.serviceOrder)
        }
    }
}
