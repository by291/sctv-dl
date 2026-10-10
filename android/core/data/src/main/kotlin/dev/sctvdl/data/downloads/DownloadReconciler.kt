package dev.sctvdl.data.downloads

import dev.sctvdl.data.downloads.platform.PlatformDownloadGateway
import dev.sctvdl.data.downloads.platform.SystemDownloadSnapshot
import dev.sctvdl.domain.download.DownloadReason
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import java.net.URI

internal class DownloadReconciler(private val gateway: PlatformDownloadGateway) {
    // A source URL can be shared by several attempts; only the unique planned destination identifies this one.
    fun matching(task: DownloadTask, snapshots: List<SystemDownloadSnapshot>): List<SystemDownloadSnapshot> =
        snapshots.filter { snapshot ->
            snapshot.url == task.url &&
                runCatching {
                    URI(snapshot.destination).path ==
                        URI(gateway.destinationFor(task.filename)).path
                }.getOrDefault(false)
        }

    suspend fun resolve(task: DownloadTask, snapshots: List<SystemDownloadSnapshot>): DownloadTask {
        if (task.state == DownloadState.Cancelled) return task

        if (task.systemId == null && task.reasonCode == DownloadReason.Ambiguous) {
            return if (matching(
                    task,
                    snapshots
                ).isEmpty()
            ) {
                task.copy(
                    reasonCode = DownloadReason.Interrupted,
                    reason = "旧系统任务已移除，可以重试"
                )
            } else {
                task
            }
        }

        val snapshot = if (task.systemId != null) {
            snapshots.firstOrNull { it.id == task.systemId }
        } else {
            if (task.state != DownloadState.Preparing) return task

            val candidates = matching(task, snapshots)
            when (candidates.size) {
                1 -> candidates.single()
                0 -> return task.copy(
                    state = DownloadState.Failed,
                    reason = "提交未完成，请重试",
                    reasonCode = DownloadReason.Interrupted
                )
                else -> return task.copy(
                    state = DownloadState.Failed,
                    reason = "发现多个旧系统任务，请先在系统下载中处理后重试",
                    reasonCode = DownloadReason.Ambiguous
                )
            }
        }

        if (snapshot == null) {
            // System history may disappear while the completed file remains readable through its content URI.
            if (task.state == DownloadState.Completed &&
                task.contentUri?.let { gateway.isAvailable(it) } == true
            ) {
                return task
            }
            return if (task.state in
                listOf(DownloadState.Completed, DownloadState.Missing)
            ) {
                task.copy(
                    state = DownloadState.Missing,
                    reason = "文件已移除或无法访问",
                    reasonCode = DownloadReason.FileMissing
                )
            } else {
                task.copy(
                    state = DownloadState.Failed,
                    reason = "系统任务已移除，请重试",
                    reasonCode = DownloadReason.Removed
                )
            }
        }

        val missing =
            snapshot.state == DownloadState.Completed &&
                (snapshot.contentUri == null || !gateway.isAvailable(snapshot.contentUri))

        return task.copy(
            systemId = snapshot.id,
            state = if (missing) DownloadState.Missing else snapshot.state,
            bytes = snapshot.bytes,
            totalBytes = snapshot.total ?: task.totalBytes,
            contentUri = snapshot.contentUri,
            reason = if (missing) {
                "文件已移除或无法访问"
            } else {
                snapshot.reason.takeUnless {
                    snapshot.state == DownloadState.Completed
                }
            },
            reasonCode = if (missing) {
                DownloadReason.FileMissing
            } else {
                snapshot.reasonCode.takeUnless {
                    snapshot.state == DownloadState.Completed
                }
            }
        )
    }
}
