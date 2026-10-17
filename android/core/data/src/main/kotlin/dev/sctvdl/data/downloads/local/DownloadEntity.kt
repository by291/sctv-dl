package dev.sctvdl.data.downloads.local

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import dev.sctvdl.data.history.local.ViewingTargetCodec
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadReason
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.isActive
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.media.Quality
import java.time.Instant
import java.time.LocalDate

@Entity(tableName = "downloads", indices = [Index(value = ["activeKey"], unique = true)])
internal data class DownloadEntity(
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
    val createdAt: Long,
    @ColumnInfo(defaultValue = "'LegacySystem'") val owner: String = DownloadOwner.LegacySystem.name,
    @ColumnInfo(defaultValue = "''") val attemptId: String = id,
    @ColumnInfo(defaultValue = "0") val revision: Long = 0,
    @ColumnInfo(defaultValue = "NULL") val selectionJson: String? = null,
    @ColumnInfo(defaultValue = "NULL") val cacheKey: String? = null,
    @ColumnInfo(defaultValue = "NULL") val publicationUri: String? = null,
    @ColumnInfo(defaultValue = "0") val publicationStarted: Boolean = false,
    @ColumnInfo(defaultValue = "0") val cacheComplete: Boolean = false,
    @ColumnInfo(defaultValue = "0") val cleanupPending: Boolean = false,
    @ColumnInfo(defaultValue = "0") val userPaused: Boolean = false,
    @ColumnInfo(defaultValue = "NULL") val mediaEtag: String? = null,
    @ColumnInfo(defaultValue = "NULL") val mediaLastModified: String? = null,
    @ColumnInfo(defaultValue = "0") val acceptsRanges: Boolean = false,
    @ColumnInfo(defaultValue = "0") val mediaChecked: Boolean = false
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
        reasonCode?.let(DownloadReason::valueOf),
        owner = DownloadOwner.valueOf(owner), attemptId = attemptId, revision = revision,
        selection = selectionJson?.let { (ViewingTargetCodec.decode(it) as ViewingTarget.Online).selection },
        cacheKey = cacheKey, publicationUri = publicationUri, publicationStarted = publicationStarted,
        cacheComplete = cacheComplete, cleanupPending = cleanupPending, userPaused = userPaused,
        mediaEtag = mediaEtag,
        mediaLastModified = mediaLastModified,
        acceptsRanges = acceptsRanges,
        mediaChecked = mediaChecked
    )
}

internal fun DownloadTask.toEntity() = DownloadEntity(
    id,
    if (reservesIdentity()) activeDownloadKey(this) else null,
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
    createdAt.toEpochMilli(),
    owner = owner.name, attemptId = attemptId, revision = revision,
    selectionJson = selection?.let { ViewingTargetCodec.encode(ViewingTarget.Online(it)) },
    cacheKey = cacheKey, publicationUri = publicationUri, publicationStarted = publicationStarted,
    cacheComplete = cacheComplete, cleanupPending = cleanupPending, userPaused = userPaused,
    mediaEtag = mediaEtag,
    mediaLastModified = mediaLastModified,
    acceptsRanges = acceptsRanges,
    mediaChecked = mediaChecked
)

private fun DownloadTask.reservesIdentity(): Boolean =
    state.isActive || reasonCode == DownloadReason.Ambiguous || (cacheComplete && state == DownloadState.Failed)
