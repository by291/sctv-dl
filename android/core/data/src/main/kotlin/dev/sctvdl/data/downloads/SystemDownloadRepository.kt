package dev.sctvdl.data.downloads

import dev.sctvdl.data.network.UrlPolicy
import dev.sctvdl.domain.AppError
import dev.sctvdl.domain.AppException
import dev.sctvdl.domain.BatchDownloadResult
import dev.sctvdl.domain.DownloadFailure
import dev.sctvdl.domain.DownloadReason
import dev.sctvdl.domain.DownloadRepository
import dev.sctvdl.domain.DownloadRequest
import dev.sctvdl.domain.DownloadState
import dev.sctvdl.domain.DownloadTask
import dev.sctvdl.domain.ErrorKind
import dev.sctvdl.domain.ProgrammeContent
import dev.sctvdl.domain.Quality
import dev.sctvdl.domain.isActive
import dev.sctvdl.domain.resolveVideo
import dev.sctvdl.domain.safeDownloadFilename
import java.io.IOException
import java.time.Clock
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class SystemDownloadRepository(
    private val store: DownloadStore,
    private val gateway: PlatformDownloadGateway,
    private val preflight: MediaPreflight,
    private val clock: Clock,
    private val dispatcher: CoroutineDispatcher
) : DownloadRepository {
    override fun observeTasks() = store.observe()
    private val submissions = Mutex()
    private val transitions = Mutex()
    private val reconciliation = Mutex()
    private val preparing = ConcurrentHashMap<String, Deferred<Long?>>()
    private val submitting = ConcurrentHashMap.newKeySet<String>()
    private val reconciler = DownloadReconciler(gateway)

    override suspend fun enqueue(requests: List<DownloadRequest>) = withContext(dispatcher) {
        submissions.withLock { enqueueBatch(requests) }
    }

    private suspend fun enqueueBatch(requests: List<DownloadRequest>, retryId: String? = null): BatchDownloadResult {
        var queued = 0
        var fallbacks = 0
        val failures = mutableListOf<DownloadFailure>()
        for (request in requests) {
            currentCoroutineContext().ensureActive()
            val variant = resolveVideo(request.content, request.requestedQuality)
            val url = variant?.url?.let(UrlPolicy::media)
            if (variant == null || url == null) {
                failures.add(
                    DownloadFailure(
                        request.content.id,
                        AppError(
                            if (variant == null) ErrorKind.NoVideo else ErrorKind.UnsafeUrl,
                            "该节目没有可下载的视频"
                        )
                    )
                )
                continue
            }
            val task = DownloadTask(
                retryId ?: UUID.randomUUID().toString(),
                request.content.id,
                request.content.title,
                request.programmeName,
                request.broadcastDate,
                request.requestedQuality,
                variant.quality,
                url,
                safeDownloadFilename(
                    request.broadcastDate,
                    request.content.title,
                    variant.quality,
                    UUID.randomUUID().toString().take(12)
                ),
                request.wifiOnly,
                createdAt = clock.instant()
            )
            var submittedId: Long? = null
            try {
                val reserved = transitions.withLock {
                    store.reserve(task).also { if (it) submitting.add(task.id) }
                }
                if (!reserved) {
                    failures.add(
                        DownloadFailure(
                            task.contentId,
                            AppError(
                                ErrorKind.Download,
                                "该节目已在队列中，或旧系统任务需要先处理"
                            )
                        )
                    )
                    continue
                }
                val total = coroutineScope {
                    val preparation = async { preflight.check(task.url) }
                    preparing[task.id] = preparation
                    try {
                        preparation.await()
                    } finally {
                        preparing.remove(task.id)
                    }
                }
                val submitted = withContext(NonCancellable) {
                    transitions.withLock {
                        if (store.get(task.id)?.state == DownloadState.Cancelled) {
                            false
                        } else {
                            submittedId = gateway.enqueue(
                                PlatformDownloadRequest(
                                    task.url,
                                    task.title,
                                    task.filename,
                                    task.wifiOnly
                                )
                            )
                            store.update(
                                task.copy(
                                    systemId = submittedId,
                                    state = DownloadState.Pending,
                                    totalBytes = total
                                )
                            )
                            true
                        }
                    }
                }
                if (submitted) {
                    queued++
                    if (variant.quality != request.requestedQuality) fallbacks++
                } else {
                    failures.add(
                        DownloadFailure(
                            task.contentId,
                            AppError(
                                ErrorKind.Download,
                                "已取消下载"
                            )
                        )
                    )
                }
            } catch (error: CancellationException) {
                withContext(NonCancellable) {
                    transitions.withLock {
                        store.get(task.id)?.takeIf {
                            it.state == DownloadState.Preparing
                        }?.let {
                            store.update(
                                it.copy(
                                    state = DownloadState.Cancelled,
                                    reason = "已取消下载",
                                    reasonCode = DownloadReason.Cancelled
                                )
                            )
                        }
                    }
                }
                if (!currentCoroutineContext().isActive) throw error
                failures.add(DownloadFailure(task.contentId, AppError(ErrorKind.Download, "已取消下载")))
            } catch (error: Exception) {
                val mapped = when (error) {
                    is AppException -> error.error
                    is IOException -> AppError(ErrorKind.Network, "视频连接失败，请重试")
                    else -> AppError(ErrorKind.Download, "无法创建下载任务，请重试")
                }
                if (submittedId == null) {
                    transitions.withLock {
                        store.get(task.id)?.takeUnless {
                            it.state == DownloadState.Cancelled
                        }?.let {
                            store.update(
                                it.copy(
                                    state = DownloadState.Failed,
                                    reason = mapped.message,
                                    reasonCode = if (mapped.kind == ErrorKind.Http) {
                                        DownloadReason.Http
                                    } else {
                                        DownloadReason.Storage
                                    }
                                )
                            )
                        }
                    }
                } else {
                    queued++
                    if (variant.quality != request.requestedQuality) fallbacks++
                }
                failures.add(DownloadFailure(task.contentId, mapped))
            } finally {
                submitting.remove(task.id)
            }
        }
        return BatchDownloadResult(queued, fallbacks, failures)
    }

    override suspend fun cancel(taskId: String) = withContext(dispatcher) {
        withContext(NonCancellable) {
            transitions.withLock {
                val task = store.get(taskId) ?: return@withLock
                if (!task.state.isActive) return@withLock
                task.systemId?.let { gateway.remove(it) }
                store.update(
                    task.copy(
                        state = DownloadState.Cancelled,
                        reason = "已取消下载",
                        reasonCode = DownloadReason.Cancelled
                    )
                )
            }
        }
        preparing[taskId]?.cancel()
        Unit
    }

    override suspend fun retry(taskId: String) = withContext(dispatcher) {
        submissions.withLock {
            val task = store.get(taskId) ?: return@withLock BatchDownloadResult(0, 0, emptyList())
            if (task.state !in setOf(
                    DownloadState.Failed,
                    DownloadState.Cancelled,
                    DownloadState.Missing
                )
            ) {
                return@withLock BatchDownloadResult(
                    0,
                    0,
                    listOf(
                        DownloadFailure(
                            task.contentId,
                            AppError(
                                ErrorKind.Download,
                                "该任务无需重试"
                            )
                        )
                    )
                )
            }
            if (task.reasonCode == DownloadReason.Ambiguous) {
                if (reconciler.matching(
                        task,
                        gateway.queryOwned()
                    ).isNotEmpty()
                ) {
                    return@withLock BatchDownloadResult(
                        0,
                        0,
                        listOf(
                            DownloadFailure(
                                task.contentId,
                                AppError(
                                    ErrorKind.Download,
                                    "请先在系统下载中处理旧任务，再重试"
                                )
                            )
                        )
                    )
                }
                transitions.withLock {
                    store.update(task.copy(reasonCode = DownloadReason.Interrupted))
                }
            }
            val content = ProgrammeContent(
                task.contentId,
                task.title,
                standardUrl = task.url.takeIf { task.actualQuality == Quality.Standard },
                smoothUrl = task.url.takeIf { task.actualQuality == Quality.Smooth }
            )
            enqueueBatch(
                listOf(
                    DownloadRequest(
                        task.programmeName,
                        task.broadcastDate,
                        content,
                        task.requestedQuality,
                        task.wifiOnly
                    )
                ),
                taskId
            )
        }
    }

    override suspend fun removeRecord(taskId: String) = withContext(dispatcher) {
        transitions.withLock {
            val task = store.get(taskId) ?: return@withLock
            if (task.state.isActive ||
                (
                    task.reasonCode == DownloadReason.Ambiguous && reconciler.matching(
                        task,
                        gateway.queryOwned()
                    ).isNotEmpty()
                    )
            ) {
                throw AppException(
                    AppError(
                        ErrorKind.Download,
                        "请先处理正在进行的系统下载"
                    )
                )
            }
            store.remove(taskId)
        }
    }

    override suspend fun reconcile() = withContext(dispatcher) {
        reconciliation.withLock {
            // Capture and apply system status in the same submission transition boundary.
            transitions.withLock {
                val snapshots = gateway.queryOwned()
                for (task in store.all()) {
                    if (task.id !in submitting) {
                        val updated = reconciler.resolve(task, snapshots)
                        if (updated != task) store.update(updated)
                    }
                }
            }
        }
    }
}
