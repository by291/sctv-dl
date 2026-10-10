package dev.sctvdl.domain.download

import dev.sctvdl.domain.common.AppError

data class DownloadFailure(val contentId: String, val error: AppError)

data class BatchDownloadResult(val queued: Int, val fallbacks: Int, val failures: List<DownloadFailure>)
