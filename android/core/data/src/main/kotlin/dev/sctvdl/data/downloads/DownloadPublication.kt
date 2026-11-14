package dev.sctvdl.data.downloads

import dev.sctvdl.data.downloads.local.DownloadStore
import dev.sctvdl.data.downloads.platform.PublicDownloadFiles
import dev.sctvdl.domain.download.DownloadReason
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.download.DownloadTask
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Journals insertion before touching MediaStore; interrupted publication always reuses an owned unique row. */
internal class DownloadPublication @Inject constructor(
    private val store: DownloadStore,
    private val files: PublicDownloadFiles,
    private val transitions: DownloadTransitions
) {
    private val publications = Mutex()

    suspend fun publish(target: DownloadTarget) = publications.withLock {
        try {
            val journaled = transitions.mutex.withLock {
                val current = current(target) ?: return@withLock null
                if (!current.cacheComplete ||
                    current.state !in setOf(DownloadState.Finalizing, DownloadState.Failed)
                ) {
                    return@withLock null
                }
                // Journal intent before MediaStore insertion so restart can recover the pending row.
                current.copy(
                    state = DownloadState.Finalizing,
                    publicationStarted = true,
                    reason = null,
                    reasonCode = null,
                    revision = current.revision + 1
                ).also { store.update(it) }
            } ?: return@withLock

            val task = journalDestination(target, journaled) ?: return@withLock
            val destination = requireNotNull(task.publicationUri)
            var bytes = task.totalBytes ?: task.bytes
            if (!files.isPublished(task, destination)) {
                bytes = files.copyCached(task, destination)
                check(bytes > 0 && (task.totalBytes == null || bytes == task.totalBytes)) { "Incomplete cached media" }

                // Copying can outlast cancellation; recheck the attempt before making the file visible.
                transitions.mutex.withLock {
                    if (current(target)?.state != DownloadState.Finalizing) {
                        return@withLock
                    }
                    files.finalize(destination)
                }
            }

            // The runtime may remove private spans once it observes a completed row.
            check(files.isPublished(task.copy(totalBytes = bytes), destination)) { "Public video is not readable" }
            transitions.mutex.withLock {
                val latest = current(target) ?: return@withLock
                if (latest.state != DownloadState.Finalizing) {
                    return@withLock
                }
                store.update(
                    latest.copy(
                        state = DownloadState.Completed,
                        contentUri = destination,
                        bytes = bytes,
                        totalBytes = bytes,
                        cleanupPending = true,
                        reason = null,
                        reasonCode = null,
                        revision = latest.revision + 1
                    )
                )
            }
        } catch (failure: CancellationException) {
            throw failure
        } catch (_: Exception) {
            transitions.mutex.withLock {
                val latest = current(target) ?: return@withLock
                if (latest.state == DownloadState.Finalizing) {
                    store.update(
                        latest.copy(
                            state = DownloadState.Failed,
                            reason = "视频已下载，保存失败，请重试保存",
                            reasonCode = DownloadReason.Publication,
                            revision = latest.revision + 1
                        )
                    )
                }
            }
        }
    }

    private suspend fun journalDestination(target: DownloadTarget, task: DownloadTask): DownloadTask? {
        if (task.publicationUri != null) {
            return task
        }

        val candidates = files.findPlanned(task)
        check(candidates.size <= 1) { "Ambiguous public video destination" }
        val uri = candidates.singleOrNull() ?: files.reserve(task)

        // Persist the destination before copying so interrupted copies reuse the same row.
        return transitions.mutex.withLock {
            val latest = current(target) ?: return@withLock null
            if (latest.state != DownloadState.Finalizing) {
                return@withLock null
            }
            latest.copy(publicationUri = uri, revision = latest.revision + 1).also { store.update(it) }
        }
    }

    private suspend fun current(target: DownloadTarget): DownloadTask? = store.get(target.id)?.takeIf {
        it.attemptId == target.attemptId
    }
}
