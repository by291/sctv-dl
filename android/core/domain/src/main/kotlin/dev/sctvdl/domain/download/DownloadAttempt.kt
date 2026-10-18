package dev.sctvdl.domain.download

enum class DownloadOwner { LegacySystem, Media3 }

data class DownloadTarget(val id: String, val attemptId: String)

val DownloadTask.target: DownloadTarget get() = DownloadTarget(id, attemptId)
