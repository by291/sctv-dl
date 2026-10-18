package dev.sctvdl.data.history.local

import dev.sctvdl.domain.history.ViewingKey
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.programme.ProgrammeSelection
import java.time.LocalDate
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

internal object ViewingTargetCodec {
    private val json = Json { ignoreUnknownKeys = true }

    fun key(key: ViewingKey): String = when (key) {
        is ViewingKey.Content -> json.encodeToString(
            listOf("content", key.ref.programmeId, key.ref.dateId, key.ref.contentId)
        )
        is ViewingKey.LegacyDownload -> "legacy:" + key.taskId
    }

    fun encode(target: ViewingTarget): String = json.encodeToString(
        when (target) {
            is ViewingTarget.Online -> target.selection.let { selection ->
                Target(
                    programmeId = selection.programme.id, programmeName = selection.programme.name,
                    programmeCover = selection.programme.coverUrl, serviceOrder = selection.programme.serviceOrder,
                    dateId = selection.broadcast.id, date = selection.broadcast.date.toString(),
                    contentId = selection.content.id, title = selection.content.title,
                    cover = selection.content.coverUrl, standard = selection.content.standardUrl,
                    smooth = selection.content.smoothUrl, publishedAt = selection.content.publishedAt
                )
            }
            is ViewingTarget.LegacyDownload -> Target(
                legacyTaskId = target.taskId,
                programmeName = target.programmeName,
                date = target.broadcastDate.toString(),
                title = target.title
            )
        }
    )

    fun decode(value: String): ViewingTarget {
        val target = json.decodeFromString<Target>(value)
        return target.legacyTaskId?.let {
            ViewingTarget.LegacyDownload(it, target.title, target.programmeName, LocalDate.parse(target.date))
        } ?: ViewingTarget.Online(
            ProgrammeSelection(
                Programme(
                    requireNotNull(target.programmeId),
                    target.programmeName,
                    target.programmeCover,
                    target.serviceOrder
                ),
                BroadcastDate(requireNotNull(target.dateId), LocalDate.parse(target.date)),
                ProgrammeContent(
                    requireNotNull(target.contentId),
                    target.title,
                    target.cover,
                    target.standard,
                    target.smooth,
                    target.publishedAt
                )
            )
        )
    }

    @Serializable
    private data class Target(
        val legacyTaskId: String? = null,
        val programmeId: String? = null,
        val programmeName: String,
        val programmeCover: String? = null,
        val serviceOrder: Int = 0,
        val dateId: String? = null,
        val date: String,
        val contentId: String? = null,
        val title: String,
        val cover: String? = null,
        val standard: String? = null,
        val smooth: String? = null,
        val publishedAt: String? = null
    )
}
