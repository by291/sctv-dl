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
        id = id,
        contentId = contentId,
        title = title,
        programmeName = programmeName,
        broadcastDate = LocalDate.parse(broadcastDate),
        requestedQuality = Quality.valueOf(requestedQuality),
        actualQuality = Quality.valueOf(actualQuality),
        url = url,
        filename = filename,
        wifiOnly = wifiOnly,
        systemId = systemId,
        contentUri = contentUri,
        bytes = bytes,
        totalBytes = totalBytes,
        state = DownloadState.valueOf(state),
        reason = reason,
        createdAt = Instant.ofEpochMilli(createdAt),
        reasonCode = reasonCode?.let(DownloadReason::valueOf),
        owner = DownloadOwner.valueOf(owner),
        attemptId = attemptId,
        revision = revision,
        selection = selectionJson?.let { (ViewingTargetCodec.decode(it) as ViewingTarget.Online).selection },
        cacheKey = cacheKey,
        publicationUri = publicationUri,
        publicationStarted = publicationStarted,
        cacheComplete = cacheComplete,
        cleanupPending = cleanupPending,
        userPaused = userPaused,
        mediaEtag = mediaEtag,
        mediaLastModified = mediaLastModified,
        acceptsRanges = acceptsRanges,
        mediaChecked = mediaChecked
    )
}

internal fun DownloadTask.toEntity() = DownloadEntity(
    id = id,
    activeKey = if (reservesIdentity()) activeDownloadKey(this) else null,
    contentId = contentId,
    title = title,
    programmeName = programmeName,
    broadcastDate = broadcastDate.toString(),
    requestedQuality = requestedQuality.name,
    actualQuality = actualQuality.name,
    url = url,
    filename = filename,
    wifiOnly = wifiOnly,
    systemId = systemId,
    contentUri = contentUri,
    bytes = bytes,
    totalBytes = totalBytes,
    state = state.name,
    reason = reason,
    createdAt = createdAt.toEpochMilli(),
    reasonCode = reasonCode?.name,
    owner = owner.name,
    attemptId = attemptId,
    revision = revision,
    selectionJson = selection?.let { ViewingTargetCodec.encode(ViewingTarget.Online(it)) },
    cacheKey = cacheKey,
    publicationUri = publicationUri,
    publicationStarted = publicationStarted,
    cacheComplete = cacheComplete,
    cleanupPending = cleanupPending,
    userPaused = userPaused,
    mediaEtag = mediaEtag,
    mediaLastModified = mediaLastModified,
    acceptsRanges = acceptsRanges,
    mediaChecked = mediaChecked
)

private fun DownloadTask.reservesIdentity(): Boolean =
    state.isActive || reasonCode == DownloadReason.Ambiguous || (cacheComplete && state == DownloadState.Failed)
