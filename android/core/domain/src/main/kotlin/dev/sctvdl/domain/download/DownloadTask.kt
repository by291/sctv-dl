package dev.sctvdl.domain.download

import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.programme.ProgrammeSelection
import java.time.Instant
import java.time.LocalDate

data class DownloadTask(
    val id: String,
    val contentId: String,
    val title: String,
    val programmeName: String,
    val broadcastDate: LocalDate,
    val requestedQuality: Quality,
    val actualQuality: Quality,
    val url: String,
    val filename: String,
    val wifiOnly: Boolean,
    val systemId: Long? = null,
    val contentUri: String? = null,
    val bytes: Long = 0,
    val totalBytes: Long? = null,
    val state: DownloadState = DownloadState.Preparing,
    val reason: String? = null,
    val createdAt: Instant,
    val reasonCode: DownloadReason? = null,
    val owner: DownloadOwner = DownloadOwner.LegacySystem,
    val attemptId: String = id,
    val revision: Long = 0,
    val selection: ProgrammeSelection? = null,
    val cacheKey: String? = null,
    val publicationUri: String? = null,
    val publicationStarted: Boolean = false,
    val cacheComplete: Boolean = false,
    val cleanupPending: Boolean = false,
    val userPaused: Boolean = false,
    val mediaEtag: String? = null,
    val mediaLastModified: String? = null,
    val acceptsRanges: Boolean = false,
    val mediaChecked: Boolean = false
)
