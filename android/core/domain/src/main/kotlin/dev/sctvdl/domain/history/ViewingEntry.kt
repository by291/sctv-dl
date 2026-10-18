package dev.sctvdl.domain.history

import dev.sctvdl.domain.programme.ContentRef
import dev.sctvdl.domain.programme.ProgrammeSelection
import java.time.Instant
import java.time.LocalDate

sealed interface ViewingKey {
    data class Content(val ref: ContentRef) : ViewingKey

    data class LegacyDownload(val taskId: String) : ViewingKey
}

sealed interface ViewingTarget {
    val key: ViewingKey

    data class Online(val selection: ProgrammeSelection) : ViewingTarget {
        override val key: ViewingKey get() = ViewingKey.Content(selection.ref)
    }

    data class LegacyDownload(
        val taskId: String,
        val title: String,
        val programmeName: String,
        val broadcastDate: LocalDate
    ) : ViewingTarget {
        override val key: ViewingKey get() = ViewingKey.LegacyDownload(taskId)
    }
}

data class ViewingEntry(
    val target: ViewingTarget,
    val positionMs: Long,
    val durationMs: Long?,
    val viewedAt: Instant,
    val completed: Boolean
) {
    val key: ViewingKey get() = target.key
}

fun isViewingCompleted(positionMs: Long, durationMs: Long?, ended: Boolean): Boolean =
    ended || (durationMs != null && durationMs > 0 && positionMs.toDouble() / durationMs >= 0.95)

fun resumePositionMs(entry: ViewingEntry?): Long = if (entry == null ||
    entry.completed
) {
    0L
} else {
    entry.positionMs.coerceAtLeast(0)
}
