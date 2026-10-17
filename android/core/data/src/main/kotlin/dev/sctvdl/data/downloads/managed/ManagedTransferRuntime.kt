package dev.sctvdl.data.downloads.managed

import android.content.Context
import android.content.Intent
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.sctvdl.data.downloads.DownloadPublication
import dev.sctvdl.data.downloads.DownloadTransitions
import dev.sctvdl.data.downloads.local.DownloadStore
import dev.sctvdl.data.downloads.platform.FileDeleteResult
import dev.sctvdl.data.downloads.platform.PublicDownloadFiles
import dev.sctvdl.data.downloads.preflight.MediaPreflight
import dev.sctvdl.data.downloads.preflight.OkHttpMediaProbe
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadReason
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.isActive
import dev.sctvdl.domain.download.target
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Services lend execution permission. Polling from a visible screen never creates that permission. */
@Singleton
internal class ManagedTransferRuntime @Inject constructor(
    @ApplicationContext private val context: Context,
    private val store: DownloadStore,
    private val gateway: ManagedTransferGateway,
    private val access: DownloadNetworkAccess,
    private val publication: DownloadPublication,
    private val files: PublicDownloadFiles,
    private val transitions: DownloadTransitions,
    private val scheduler: DownloadRecoveryScheduler
) : ManagedDownloadControl {
    private val reconciliation = Mutex()
    private val deferredTransfers = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private val deferredCleanup = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    fun acquire(owner: ExecutionOwner): ExecutionLease {
        deferredCleanup.clear()
        deferredTransfers.clear()
        return access.acquire(owner)
    }

    override suspend fun start() {
        scheduler.reconcile()
        try {
            context.startForegroundService(Intent(context, ManagedDownloadService::class.java))
        } catch (_: IllegalStateException) {
            // JobScheduler owns deferred recovery when the OS refuses a background foreground-service start.
        }
    }

    override suspend fun stop(task: DownloadTask) {
        transitions.mutex.withLock {
            val current = store.get(task.id) ?: return@withLock
            if (current.attemptId != task.attemptId || !current.userPaused) return@withLock
            access.block(task.attemptId)
            if (current.mediaChecked) {
                gateway.enqueue(current)
                gateway.pause(task.attemptId)
            }
        }
        scheduler.reconcile()
    }

    override suspend fun remove(task: DownloadTask) {
        access.block(task.attemptId)
        gateway.enqueue(task)
        gateway.remove(task.attemptId)
    }

    suspend fun hasWork(owner: ExecutionOwner): Boolean = store.all().any { task ->
        val deferred = task.attemptId in deferredCleanup || task.attemptId in deferredTransfers
        if (task.owner != DownloadOwner.Media3 || deferred) return@any false
        when {
            task.cleanupPending || task.state == DownloadState.Finalizing ->
                owner == ExecutionOwner.Foreground || owner == ExecutionOwner.LocalJob
            !task.state.isActive || task.userPaused -> false
            owner == ExecutionOwner.Foreground -> DownloadNetworkPolicy.allows(task.wifiOnly, access.status())
            owner == ExecutionOwner.WifiJob -> task.wifiOnly && DownloadNetworkPolicy.allows(true, access.status())
            owner == ExecutionOwner.UnrestrictedJob -> !task.wifiOnly && access.status().connected
            else -> false
        }
    }

    suspend fun hasPending(owner: ExecutionOwner): Boolean = store.all().any { task ->
        task.owner == DownloadOwner.Media3 && when (owner) {
            ExecutionOwner.LocalJob -> task.cleanupPending || task.state == DownloadState.Finalizing
            ExecutionOwner.WifiJob -> task.wifiOnly && task.state.isActive && !task.userPaused && !task.cacheComplete
            ExecutionOwner.UnrestrictedJob ->
                !task.wifiOnly && task.state.isActive && !task.userPaused &&
                    !task.cacheComplete
            ExecutionOwner.Foreground -> task.state.isActive || task.cleanupPending
        }
    }

    override suspend fun reconcile() = reconciliation.withLock {
        val tasks = store.all().filter { it.owner == DownloadOwner.Media3 }
        if (tasks.isEmpty()) return@withLock
        val snapshots = gateway.snapshots().associateBy { it.attemptId }
        for (original in tasks) {
            var task = store.get(original.id)?.takeIf { it.attemptId == original.attemptId } ?: continue
            try {
                if (task.cleanupPending && access.hasLocalLease() && task.attemptId !in deferredCleanup) {
                    if (task.state == DownloadState.Cancelled) {
                        task.publicationUri?.let { check(files.delete(it) !is FileDeleteResult.ConsentRequired) }
                        if (task.publicationStarted && task.publicationUri == null) {
                            val candidates = files.findPlanned(task)
                            check(candidates.size <= 1)
                            candidates.forEach { check(files.delete(it) !is FileDeleteResult.ConsentRequired) }
                        }
                    }
                    remove(task)
                    update(task) { it.copy(cleanupPending = false, cacheComplete = false, cacheKey = null) }
                    continue
                }
                if (task.state == DownloadState.Completed) {
                    if (task.contentUri?.let { files.isReadable(it) } != true) {
                        update(task) {
                            it.copy(
                                state = DownloadState.Missing,
                                reason = "文件已移除或无法访问",
                                reasonCode = DownloadReason.FileMissing
                            )
                        }
                    }
                    continue
                }
                if (task.cacheComplete && task.state == DownloadState.Finalizing) {
                    if (access.hasLocalLease()) publication.publish(task.target)
                    continue
                }
                if (!task.state.isActive || task.attemptId in deferredTransfers) continue
                val allowed = transitions.mutex.withLock {
                    val latest = store.get(task.id)
                    if (latest?.attemptId != task.attemptId || latest.revision != task.revision) return@withLock false
                    if (latest.userPaused) access.block(latest.attemptId) else access.unblock(latest.attemptId)
                    access.permits(latest)
                }
                if (!allowed) {
                    if (task.mediaChecked) {
                        gateway.enqueue(task)
                        gateway.allow(task, false)
                    }
                    update(task) {
                        it.copy(
                            state = if (it.userPaused) DownloadState.Paused else DownloadState.Waiting,
                            reasonCode = when {
                                it.userPaused -> null
                                !access.status().connected -> DownloadReason.Network
                                it.wifiOnly && (!access.status().wifi || access.status().vpn) -> DownloadReason.Wifi
                                else -> DownloadReason.BackgroundLimit
                            },
                            reason = if (it.userPaused) null else "等待允许的网络或系统调度"
                        )
                    }
                    continue
                }
                if (!task.mediaChecked) {
                    val identity = MediaPreflight(OkHttpMediaProbe(access.client(task))).inspect(task.url)
                    task = update(task) {
                        it.copy(
                            mediaChecked = true,
                            totalBytes = identity.totalBytes,
                            mediaEtag = identity.etag,
                            mediaLastModified = identity.lastModified,
                            acceptsRanges = identity.acceptsRanges
                        )
                    } ?: continue
                }
                gateway.enqueue(task)
                gateway.allow(task, true)
                val snapshot = snapshots[task.attemptId]
                if (snapshot?.phase == ManagedTransferPhase.Complete) {
                    if (task.totalBytes != null && snapshot.bytes != task.totalBytes) {
                        update(task) {
                            it.copy(
                                state = DownloadState.Failed,
                                reasonCode = DownloadReason.ResumeRequired,
                                reason = "视频长度已变化，请重新下载"
                            )
                        }
                    } else {
                        update(task) {
                            it.copy(
                                state = DownloadState.Finalizing,
                                cacheComplete = true,
                                bytes = snapshot.bytes,
                                totalBytes = snapshot.total ?: snapshot.bytes,
                                reason = null,
                                reasonCode = null
                            )
                        }
                    }
                } else if (snapshot?.phase == ManagedTransferPhase.Failed) {
                    val failure = snapshot.failure ?: DownloadReason.Network
                    if (failure == DownloadReason.ResumeRequired) {
                        update(task) {
                            it.copy(
                                state = DownloadState.Failed,
                                bytes = snapshot.bytes,
                                reasonCode = failure,
                                reason = "源视频已变化或不支持安全续传，请重新下载"
                            )
                        }
                    } else {
                        // Withdraw execution until a later scheduled lease; retain the request and verified cache spans.
                        gateway.resume(task.attemptId)
                        deferredTransfers += task.attemptId
                        update(task) {
                            it.copy(
                                state = DownloadState.Waiting,
                                bytes = snapshot.bytes,
                                reasonCode = DownloadReason.Network,
                                reason = "网络中断，等待系统重试"
                            )
                        }
                    }
                } else {
                    update(task) {
                        it.copy(
                            state = if (snapshot?.phase ==
                                ManagedTransferPhase.Running
                            ) {
                                DownloadState.Running
                            } else {
                                DownloadState.Pending
                            },
                            bytes = snapshot?.bytes ?: it.bytes,
                            totalBytes = snapshot?.total ?: it.totalBytes,
                            reason = null,
                            reasonCode = null
                        )
                    }
                }
            } catch (failure: CancellationException) {
                throw failure
            } catch (failure: Exception) {
                if (task.cleanupPending) deferredCleanup += task.attemptId
                if (task.state.isActive && !task.userPaused) {
                    val transient = failure is java.io.IOException || !access.permits(task)
                    if (transient) deferredTransfers += task.attemptId
                    update(task) {
                        it.copy(
                            state = if (transient) DownloadState.Waiting else DownloadState.Failed,
                            reason = if (transient) "网络中断，等待系统重试" else "下载准备失败，请重试",
                            reasonCode = DownloadReason.Network
                        )
                    }
                }
            }
        }
        scheduler.reconcile()
    }

    private suspend fun update(task: DownloadTask, change: (DownloadTask) -> DownloadTask): DownloadTask? =
        transitions.mutex.withLock {
            val latest = store.get(task.id) ?: return@withLock null
            // Progress and probe responses may finish after pause, cancel, or a replacement attempt.
            if (latest.attemptId != task.attemptId || latest.revision != task.revision) return@withLock null
            change(latest).copy(revision = latest.revision + 1).also { store.update(it) }
        }
}
