package dev.sctvdl.domain.download

import dev.sctvdl.domain.media.Quality
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
    val reasonCode: DownloadReason? = null
)
