@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package dev.sctvdl.data.downloads.managed

import android.content.Context
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.database.DatabaseProvider
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSourceInputStream
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.NoOpCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.offline.DefaultDownloadIndex
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadRequest
import androidx.media3.exoplayer.offline.DownloaderFactory
import androidx.media3.exoplayer.offline.ProgressiveDownloader
import androidx.media3.exoplayer.scheduler.Requirements
import dev.sctvdl.domain.download.DownloadReason
import dev.sctvdl.domain.download.DownloadTask
import java.io.File
import java.io.InputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/** One Media3 index/cache owner; construction and restoration never grant permission to transfer. */
internal class Media3TransferGateway(
    private val context: Context,
    private val cacheDirectory: File,
    private val database: DatabaseProvider,
    private val indexName: String,
    private val sourceFactory: (DownloadTask) -> DataSource.Factory
) : ManagedTransferGateway {
    private val initialization = Mutex()
    private val tasks = ConcurrentHashMap<String, DownloadTask>()
    private val failures = ConcurrentHashMap<String, DownloadReason>()
    private val executor = Executors.newFixedThreadPool(3)
    private val initialized = CompletableDeferred<Unit>()
    private var cache: SimpleCache? = null
    private var manager: DownloadManager? = null
    private var index: DefaultDownloadIndex? = null
    private var closed = false
    override val updates =
        MutableSharedFlow<ManagedTransferSnapshot>(
            extraBufferCapacity = 64,
            onBufferOverflow = BufferOverflow.DROP_OLDEST
        )

    private suspend fun initialize() {
        initialization.withLock {
            check(!closed) { "Transfer engine is closed" }
            if (manager != null) return@withLock
            val ownedCache = withContext(Dispatchers.IO) { SimpleCache(cacheDirectory, NoOpCacheEvictor(), database) }
            cache = ownedCache
            val ownedIndex = DefaultDownloadIndex(database, indexName)
            index = ownedIndex
            withContext(Dispatchers.IO) {
                // Global resume must never start a restored entry before its policy/context has been checked.
                ownedIndex.getDownloads().use { cursor ->
                    val restored = buildList { while (cursor.moveToNext()) add(cursor.download) }
                    restored.filter { !it.isTerminalState }.forEach { download ->
                        val removing =
                            download.state == Download.STATE_REMOVING || download.state == Download.STATE_RESTARTING
                        val stop = if (download.stopReason == USER_PAUSED) USER_PAUSED else NO_EXECUTION
                        val progress = androidx.media3.exoplayer.offline.DownloadProgress().apply {
                            bytesDownloaded = download.bytesDownloaded
                            percentDownloaded = download.percentDownloaded
                        }
                        ownedIndex.putDownload(
                            Download(
                                download.request,
                                if (removing) download.state else Download.STATE_STOPPED,
                                download.startTimeMs,
                                download.updateTimeMs,
                                download.contentLength,
                                stop,
                                Download.FAILURE_REASON_NONE,
                                progress
                            )
                        )
                    }
                }
            }
            withContext(Dispatchers.Main.immediate) {
                val factory = DownloaderFactory { request ->
                    ProgressiveDownloader(
                        MediaItem.Builder().setUri(request.uri).setCustomCacheKey(request.customCacheKey).build(),
                        CacheDataSource.Factory().setCache(
                            ownedCache
                        ).setUpstreamDataSourceFactory(
                            DataSource.Factory {
                                DeferredTransferSource {
                                    val task =
                                        tasks[request.id] ?: throw java.io.IOException("Transfer context unavailable")
                                    sourceFactory(task).createDataSource()
                                }
                            }
                        ),
                        executor
                    )
                }
                manager = DownloadManager(context, ownedIndex, factory).apply {
                    setRequirements(Requirements(0))
                    maxParallelDownloads = 3
                    minRetryCount = 1
                    pauseDownloads()
                    addListener(object : DownloadManager.Listener {
                        override fun onInitialized(downloadManager: DownloadManager) {
                            initialized.complete(Unit)
                        }

                        override fun onDownloadChanged(
                            downloadManager: DownloadManager,
                            download: Download,
                            finalException: Exception?
                        ) {
                            if (finalException != null) {
                                failures[download.request.id] =
                                    if (generateSequence<Throwable>(finalException) { it.cause }
                                            .any { it is RestartRequiredException }
                                    ) {
                                        DownloadReason.ResumeRequired
                                    } else {
                                        DownloadReason.Network
                                    }
                            }
                            updates.tryEmit(snapshot(download))
                        }
                    })
                    if (isInitialized) initialized.complete(Unit)
                }
            }
        }
        initialized.await()
    }

    override suspend fun enqueue(task: DownloadTask) {
        tasks[task.attemptId] = task
        initialize()
        val exists = withContext(Dispatchers.IO) { requireNotNull(index).getDownload(task.attemptId) != null }
        if (!exists) {
            withContext(Dispatchers.Main.immediate) {
                requireNotNull(manager).addDownload(request(task), if (task.userPaused) USER_PAUSED else NO_EXECUTION)
            }
        }
    }

    override suspend fun allow(task: DownloadTask, permitted: Boolean) {
        tasks[task.attemptId] = task
        initialize()
        withContext(Dispatchers.Main.immediate) {
            requireNotNull(manager).setStopReason(
                task.attemptId,
                when {
                    task.userPaused -> USER_PAUSED
                    !permitted -> NO_EXECUTION
                    else -> Download.STOP_REASON_NONE
                }
            )
            // Per-task stop reasons have been queued first. Global resume is only an execution mechanism.
            requireNotNull(manager).resumeDownloads()
        }
    }

    override suspend fun pause(attemptId: String) {
        initialize()
        withContext(Dispatchers.Main.immediate) { requireNotNull(manager).setStopReason(attemptId, USER_PAUSED) }
    }

    override suspend fun resume(attemptId: String) {
        initialize()
        // User intent alone does not grant a network/host lease. The runtime will call allow after checking both.
        val failed = withContext(Dispatchers.IO) {
            requireNotNull(index).getDownload(attemptId)?.state ==
                Download.STATE_FAILED
        }
        withContext(Dispatchers.Main.immediate) {
            if (failed) {
                // Re-add the same request/cache key so a transient failure resumes its verified spans.
                tasks[attemptId]?.let { requireNotNull(manager).addDownload(request(it), NO_EXECUTION) }
                failures.remove(attemptId)
            } else {
                requireNotNull(manager).setStopReason(attemptId, NO_EXECUTION)
            }
        }
    }

    override suspend fun remove(attemptId: String) {
        initialize()
        withContext(Dispatchers.Main.immediate) { requireNotNull(manager).removeDownload(attemptId) }
        withTimeout(30_000) {
            while (withContext(Dispatchers.IO) { requireNotNull(index).getDownload(attemptId) != null }) delay(50)
        }
        tasks.remove(attemptId)
        failures.remove(attemptId)
    }

    override suspend fun snapshots(): List<ManagedTransferSnapshot> {
        initialize()
        val current =
            withContext(Dispatchers.Main.immediate) {
                requireNotNull(manager).currentDownloads.associateBy { it.request.id }
            }
        return withContext(Dispatchers.IO) {
            requireNotNull(index).getDownloads().use { cursor ->
                buildList {
                    while (cursor.moveToNext()) {
                        add(snapshot(current[cursor.download.request.id] ?: cursor.download))
                    }
                }
            }
        }
    }

    private fun snapshot(download: Download): ManagedTransferSnapshot {
        val key = download.request.customCacheKey ?: download.request.id
        val task = tasks[download.request.id]
        return ManagedTransferSnapshot(
            download.request.id,
            when (download.state) {
                Download.STATE_COMPLETED -> ManagedTransferPhase.Complete
                Download.STATE_FAILED -> ManagedTransferPhase.Failed
                Download.STATE_DOWNLOADING -> ManagedTransferPhase.Running
                Download.STATE_STOPPED -> if (download.stopReason ==
                    USER_PAUSED
                ) {
                    ManagedTransferPhase.Paused
                } else {
                    ManagedTransferPhase.Waiting
                }
                else -> ManagedTransferPhase.Pending
            },
            download.bytesDownloaded,
            download.contentLength.takeIf { it != C.LENGTH_UNSET.toLong() && it > 0 },
            key,
            task?.acceptsRanges == true && (task.mediaEtag != null || task.mediaLastModified != null),
            failures[download.request.id]
        )
    }

    override suspend fun openCached(task: DownloadTask): InputStream {
        tasks[task.attemptId] = task
        initialize()
        return withContext(Dispatchers.IO) {
            // A missing cache span must fail publication; no upstream factory is configured here.
            val source = CacheDataSource.Factory().setCache(requireNotNull(cache)).createDataSource()
            DataSourceInputStream(
                source,
                DataSpec.Builder().setUri(task.url).setKey(task.cacheKey ?: task.attemptId).build()
            )
                .apply { open() }
        }
    }

    override suspend fun shutdown() {
        initialization.withLock {
            if (closed) return@withLock
            closed = true
            withContext(Dispatchers.Main.immediate) { manager?.release() }
            withContext(Dispatchers.IO) { cache?.release() }
            executor.shutdownNow()
        }
    }

    private fun request(task: DownloadTask): DownloadRequest =
        DownloadRequest.Builder(task.attemptId, Uri.parse(task.url))
            .setMimeType("video/mp4").setCustomCacheKey(task.cacheKey ?: task.attemptId).build()

    private companion object {
        const val USER_PAUSED = 1
        const val NO_EXECUTION = 2
    }
}

/** Removal only touches cached spans and therefore does not require a restored network context. */
private class DeferredTransferSource(private val factory: () -> DataSource) : DataSource {
    private var delegate: DataSource? = null
    private val listeners = mutableListOf<androidx.media3.datasource.TransferListener>()

    override fun addTransferListener(transferListener: androidx.media3.datasource.TransferListener) {
        listeners +=
            transferListener
    }

    override fun open(dataSpec: DataSpec): Long {
        val source = factory()
        listeners.forEach(source::addTransferListener)
        delegate = source
        return source.open(dataSpec)
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
        requireNotNull(delegate).read(buffer, offset, length)

    override fun getUri() = delegate?.uri

    override fun getResponseHeaders(): Map<String, List<String>> = delegate?.responseHeaders.orEmpty()

    override fun close() {
        delegate?.close()
        delegate = null
    }
}
