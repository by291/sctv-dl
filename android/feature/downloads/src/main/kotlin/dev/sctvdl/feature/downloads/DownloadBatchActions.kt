package dev.sctvdl.feature.downloads

import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.AppException
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadActionResult
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.repository.DownloadRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

internal data class DownloadBatchOutcome(
    val appliedIds: Set<String>,
    val skippedIds: Set<String>,
    val failures: Map<String, AppError>
)

internal data class DownloadBatchRequest(
    val repository: DownloadRepository,
    val action: DownloadAction,
    val targets: List<DownloadTarget>,
    val requestConsent: suspend (String) -> Boolean
)

internal suspend fun runDownloadBatch(request: DownloadBatchRequest): DownloadBatchOutcome {
    val applied = mutableSetOf<String>()
    val skipped = mutableSetOf<String>()
    val failures = mutableMapOf<String, AppError>()

    for (target in request.targets.distinct()) {
        try {
            val result = request.repository.perform(target, request.action)
            val outcome = if (result is DownloadActionResult.ConsentRequired) {
                request.resolveFileConsent(target, result.token)
            } else {
                result
            }

            when (outcome) {
                DownloadActionResult.Applied -> applied += target.id
                DownloadActionResult.Skipped -> skipped += target.id
                is DownloadActionResult.ConsentRequired -> {
                    request.repository.completeFileConsent(target, outcome.token, granted = false)
                    skipped += target.id
                }
            }
        } catch (failure: CancellationException) {
            throw failure
        } catch (failure: Exception) {
            failures[target.id] = (failure as? AppException)?.error ?: AppError(ErrorKind.Download, "操作未完成，请重试")
        }
    }

    return DownloadBatchOutcome(applied, skipped, failures)
}

private suspend fun DownloadBatchRequest.resolveFileConsent(
    target: DownloadTarget,
    token: String
): DownloadActionResult {
    try {
        val granted = requestConsent(token)
        return repository.completeFileConsent(target, token, granted = granted)
    } finally {
        // A dismissed or cancelled prompt must discard the repository's one-time token.
        withContext(NonCancellable) {
            repository.completeFileConsent(target, token, granted = false)
        }
    }
}

internal val DownloadAction.label: String get() = when (this) {
    DownloadAction.Pause -> "暂停"
    DownloadAction.Resume -> "继续下载"
    DownloadAction.Retry -> "重新下载"
    DownloadAction.Publish -> "重试保存"
    DownloadAction.Cancel -> "取消下载"
    DownloadAction.DeleteFile -> "删除视频"
    DownloadAction.RemoveRecord -> "移除记录"
}
