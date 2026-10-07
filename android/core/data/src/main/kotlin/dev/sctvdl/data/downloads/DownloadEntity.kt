package dev.sctvdl.data.downloads

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import dev.sctvdl.domain.DownloadReason
import dev.sctvdl.domain.DownloadState
import dev.sctvdl.domain.DownloadTask
import dev.sctvdl.domain.Quality
import dev.sctvdl.domain.isActive
import java.time.Instant
import java.time.LocalDate

@Entity(tableName = "downloads", indices = [Index(value = ["activeKey"], unique = true)])
data class DownloadEntity(
    @PrimaryKey val id: String,
    val activeKey: String?,
    val contentId: String,
    val title: String,
    val programmeName: String,
    val broadcastDate: String,
    val requestedQuality: String,
    val actualQuality: String,
    val url: String,
    val filename: String,
    val wifiOnly: Boolean,
    val systemId: Long?,
    val contentUri: String?,
    val bytes: Long,
    val totalBytes: Long?,
    val state: String,
    val reason: String?,
    val reasonCode: String?,
    val createdAt: Long
) {
    fun toTask() = DownloadTask(
        id,
        contentId,
        title,
        programmeName,
        LocalDate.parse(broadcastDate),
        Quality.valueOf(requestedQuality),
        Quality.valueOf(actualQuality),
        url,
        filename,
        wifiOnly,
        systemId,
        contentUri,
        bytes,
        totalBytes,
        DownloadState.valueOf(state),
        reason,
        Instant.ofEpochMilli(createdAt),
        reasonCode?.let(DownloadReason::valueOf)
    )
}

fun DownloadTask.toEntity() = DownloadEntity(
    id,
    if (state.isActive || reasonCode == DownloadReason.Ambiguous) activeDownloadKey(this) else null,
    contentId,
    title,
    programmeName,
    broadcastDate.toString(),
    requestedQuality.name,
    actualQuality.name,
    url,
    filename,
    wifiOnly,
    systemId,
    contentUri,
    bytes,
    totalBytes,
    state.name,
    reason,
    reasonCode?.name,
    createdAt.toEpochMilli()
)
