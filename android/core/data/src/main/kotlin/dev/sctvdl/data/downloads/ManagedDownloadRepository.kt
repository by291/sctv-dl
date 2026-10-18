package dev.sctvdl.data.downloads

import dev.sctvdl.data.di.DownloadFileConsentRegistry
import dev.sctvdl.data.downloads.local.DownloadStore
import dev.sctvdl.data.downloads.managed.ManagedDownloadControl
import dev.sctvdl.data.downloads.platform.FileDeleteResult
import dev.sctvdl.data.downloads.platform.PublicDownloadFiles
import dev.sctvdl.data.network.UpstreamUrlPolicy
import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.download.BatchDownloadResult
import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadActionResult
import dev.sctvdl.domain.download.DownloadFailure
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadReason
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.safeDownloadFilename
import dev.sctvdl.domain.download.supportedActions
import dev.sctvdl.domain.download.target
import dev.sctvdl.domain.media.resolveVideo
import dev.sctvdl.domain.repository.DownloadRepository
import java.time.Clock
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.withLock

/** Mutations validate attempt identity and capability inside the same boundary as reconciliation/publication. */
internal class ManagedDownloadRepository(
    private val store: DownloadStore,
    private val legacy: LegacyDownloadRecovery,
    private val control: ManagedDownloadControl,
    private val files: PublicDownloadFiles,
    private val consents: DownloadFileConsentRegistry,
    private val transitions: DownloadTransitions,
    private val clock: Clock
) : DownloadRepository {
    override fun observeTasks() = store.observe()

    override suspend fun enqueue(requests: List<DownloadRequest>): BatchDownloadResult {
        var queued = 0
        var fallbacks = 0
        val failures = mutableListOf<DownloadFailure>()
        for (request in requests) {
            val variant = resolveVideo(request.content, request.requestedQuality)
            val url = variant?.url?.let(UpstreamUrlPolicy::media)
            if (variant == null || url == null) {
                failures += DownloadFailure(request.content.id, AppError(ErrorKind.NoVideo, "该节目没有可下载的视频"))
                continue
            }
            val id = UUID.randomUUID().toString()
            val task = DownloadTask(
                id = id,
                contentId = request.content.id,
                title = request.content.title,
                programmeName = request.programmeName,
                broadcastDate = request.broadcastDate,
                requestedQuality = request.requestedQuality,
                actualQuality = variant.quality,
                url = url,
                filename = safeDownloadFilename(
                    request.broadcastDate,
                    request.content.title,
                    variant.quality,
                    id.take(12)
                ),
                wifiOnly = request.wifiOnly,
                createdAt = clock.instant(),
                owner = DownloadOwner.Media3,
                attemptId = id,
                cacheKey = id,
                selection = request.selection
            )
            try {
                if (transitions.mutex.withLock { store.reserve(task) }) {
                    queued++
                    if (variant.quality != request.requestedQuality) fallbacks++
                } else {
                    failures += DownloadFailure(task.contentId, AppError(ErrorKind.Download, "该节目已在队列中，或旧系统任务需要先处理"))
                }
            } catch (failure: CancellationException) {
                throw failure
            } catch (_: Exception) {
                failures += DownloadFailure(task.contentId, AppError(ErrorKind.Storage, "无法保存下载任务，请重试"))
            }
        }
        if (queued > 0) control.start()
        return BatchDownloadResult(queued, fallbacks, failures)
    }

    override suspend fun perform(target: DownloadTarget, action: DownloadAction): DownloadActionResult {
        val transition = transitions.mutex.withLock { applyAction(target, action) }

        // Native stop/start runs after persistence and outside the mutation lock, which stop also acquires.
        transition.stopTask?.let { control.stop(it) }
        if (transition.start) control.start()
        return transition.result
    }

    private suspend fun applyAction(target: DownloadTarget, action: DownloadAction): ActionTransition {
        var task = store.get(target.id) ?: return ActionTransition.skipped
        if (task.attemptId != target.attemptId) return ActionTransition.skipped
        if (task.owner == DownloadOwner.LegacySystem) {
            legacy.reconcile()
            task = store.get(target.id) ?: return ActionTransition.skipped
        }
        if (task.attemptId != target.attemptId || action !in supportedActions(task)) return ActionTransition.skipped

        return when (action) {
            DownloadAction.Pause -> {
                val paused = task.copy(
                    userPaused = true,
                    state = DownloadState.Paused,
                    reason = null,
                    reasonCode = null,
                    revision = task.revision + 1
                )
                store.update(paused)
                ActionTransition(stopTask = paused)
            }
            DownloadAction.Resume -> {
                store.update(task.copy(userPaused = false, state = DownloadState.Pending, revision = task.revision + 1))
                ActionTransition(start = true)
            }
            DownloadAction.Retry -> replaceAttempt(task)
            DownloadAction.Publish -> {
                store.update(task.copy(state = DownloadState.Finalizing, revision = task.revision + 1))
                ActionTransition(start = true)
            }
            DownloadAction.Cancel -> cancelAttempt(task)
            DownloadAction.DeleteFile -> ActionTransition(result = deleteFile(task))
            DownloadAction.RemoveRecord -> {
                // Keep the durable row until private-cache removal succeeds. Public files are independent.
                if (task.owner == DownloadOwner.Media3) control.remove(task)
                store.remove(task.id)
                ActionTransition()
            }
        }
    }

    private suspend fun replaceAttempt(task: DownloadTask): ActionTransition {
        if (UpstreamUrlPolicy.media(task.url) == null) return ActionTransition.skipped
        if (task.owner == DownloadOwner.Media3) control.remove(task)

        val attempt = UUID.randomUUID().toString()
        val replacement = task.copy(
            owner = DownloadOwner.Media3,
            attemptId = attempt,
            cacheKey = attempt,
            filename = safeDownloadFilename(task.broadcastDate, task.title, task.actualQuality, attempt.take(12)),
            systemId = null,
            contentUri = null,
            bytes = 0,
            totalBytes = null,
            state = DownloadState.Preparing,
            reason = null,
            reasonCode = null,
            userPaused = false,
            publicationUri = null,
            publicationStarted = false,
            cacheComplete = false,
            cleanupPending = false,
            mediaEtag = null,
            mediaLastModified = null,
            acceptsRanges = false,
            mediaChecked = false,
            revision = task.revision + 1
        )
        return if (store.reserve(replacement)) ActionTransition(start = true) else ActionTransition.skipped
    }

    private suspend fun cancelAttempt(task: DownloadTask): ActionTransition {
        if (task.owner == DownloadOwner.LegacySystem) {
            legacy.cancel(task.id)
            return ActionTransition()
        }

        val cancelled = task.copy(
            state = DownloadState.Cancelled,
            userPaused = true,
            cleanupPending = true,
            reason = "已取消下载",
            reasonCode = DownloadReason.Cancelled,
            revision = task.revision + 1
        )
        store.update(cancelled)
        return ActionTransition(stopTask = cancelled, start = true)
    }

    private data class ActionTransition(
        val result: DownloadActionResult = DownloadActionResult.Applied,
        val stopTask: DownloadTask? = null,
        val start: Boolean = false
    ) {
        companion object {
            val skipped = ActionTransition(result = DownloadActionResult.Skipped)
        }
    }

    private suspend fun deleteFile(task: DownloadTask): DownloadActionResult {
        val uri = task.contentUri ?: return DownloadActionResult.Skipped
        when (val result = files.delete(uri)) {
            is FileDeleteResult.ConsentRequired -> {
                consents.bind(result.token, task.target)
                return DownloadActionResult.ConsentRequired(result.token)
            }
            FileDeleteResult.Deleted, FileDeleteResult.Missing -> store.update(
                task.copy(
                    state = DownloadState.Missing,
                    reason = "文件已移除",
                    reasonCode = DownloadReason.FileMissing,
                    revision = task.revision + 1
                )
            )
        }
        return DownloadActionResult.Applied
    }

    override suspend fun completeFileConsent(
        target: DownloadTarget,
        token: String,
        granted: Boolean
    ): DownloadActionResult = transitions.mutex.withLock {
        val uri = consents.consume(token, target) ?: return@withLock DownloadActionResult.Skipped
        val task = store.get(target.id) ?: return@withLock DownloadActionResult.Skipped
        val matchesFile = task.contentUri == uri && task.state == DownloadState.Completed
        if (!granted || task.attemptId != target.attemptId || !matchesFile) {
            return@withLock DownloadActionResult.Skipped
        }
        deleteFile(task)
    }

    override suspend fun cancel(taskId: String) {
        store.get(taskId)?.let { perform(it.target, DownloadAction.Cancel) }
    }

    override suspend fun removeRecord(taskId: String) {
        store.get(taskId)?.let { perform(it.target, DownloadAction.RemoveRecord) }
    }

    override suspend fun retry(taskId: String): BatchDownloadResult {
        val task = store.get(taskId) ?: return BatchDownloadResult(0, 0, emptyList())
        val result = perform(task.target, DownloadAction.Retry)
        return BatchDownloadResult(if (result == DownloadActionResult.Applied) 1 else 0, 0, emptyList())
    }

    override suspend fun reconcile() {
        transitions.mutex.withLock { legacy.reconcile() }
        control.reconcile()
    }
}
