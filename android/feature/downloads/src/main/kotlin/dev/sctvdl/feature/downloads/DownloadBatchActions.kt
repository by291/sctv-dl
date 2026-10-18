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

internal suspend fun runDownloadBatch(
    repository: DownloadRepository,
    action: DownloadAction,
    targets: List<DownloadTarget>,
    requestConsent: suspend (String) -> Boolean
): DownloadBatchOutcome {
    val applied = mutableSetOf<String>()
    val skipped = mutableSetOf<String>()
    val failures = mutableMapOf<String, AppError>()
    for (target in targets.distinct()) {
        try {
            var result = repository.perform(target, action)
            if (result is DownloadActionResult.ConsentRequired) {
                val token = result.token
                try {
                    result = repository.completeFileConsent(target, token, requestConsent(token))
                } finally {
                    // Dismissal/cancellation must consume the Activity consent token as well.
                    withContext(NonCancellable) { repository.completeFileConsent(target, token, false) }
                }
            }
            when (result) {
                DownloadActionResult.Applied -> applied += target.id
                DownloadActionResult.Skipped -> skipped += target.id
                is DownloadActionResult.ConsentRequired -> {
                    repository.completeFileConsent(target, result.token, false)
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

internal val DownloadAction.label: String get() = when (this) {
    DownloadAction.Pause -> "暂停"
    DownloadAction.Resume -> "继续下载"
    DownloadAction.Retry -> "重新下载"
    DownloadAction.Publish -> "重试保存"
    DownloadAction.Cancel -> "取消下载"
    DownloadAction.DeleteFile -> "删除视频"
    DownloadAction.RemoveRecord -> "移除记录"
}
