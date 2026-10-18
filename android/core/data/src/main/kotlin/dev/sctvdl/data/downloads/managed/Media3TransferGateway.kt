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
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
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
    private var resources: TransferResources? = null
    private var closed = false

    override val updates =
        MutableSharedFlow<ManagedTransferSnapshot>(
            extraBufferCapacity = 64,
            onBufferOverflow = BufferOverflow.DROP_OLDEST
        )

    private suspend fun initialize(): TransferResources {
        val engine = initialization.withLock {
            check(!closed) { "Transfer engine is closed" }
            resources ?: createResources().also { resources = it }
        }
        engine.ready.await()
        return engine
    }

    private suspend fun createResources(): TransferResources {
        var acquiredCache: SimpleCache? = null
        var acquiredManager: DownloadManager? = null
        val initialized = CompletableDeferred<Unit>()

        try {
            // Assign within the dispatcher block: cancellation may discard its returned value.
            withContext(Dispatchers.IO) {
                acquiredCache = SimpleCache(cacheDirectory, NoOpCacheEvictor(), database)
            }
            val ownedCache = requireNotNull(acquiredCache)
            val ownedIndex = DefaultDownloadIndex(database, indexName)
            restoreStoppedDownloads(ownedIndex)

            withContext(Dispatchers.Main.immediate) {
                val factory = DownloaderFactory { request ->
                    ProgressiveDownloader(
                        MediaItem.Builder().setUri(request.uri).setCustomCacheKey(request.customCacheKey).build(),
                        CacheDataSource.Factory().setCache(ownedCache).setUpstreamDataSourceFactory(
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
                val manager = DownloadManager(context, ownedIndex, factory)
                acquiredManager = manager
                manager.apply {
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
            currentCoroutineContext().ensureActive()
            return TransferResources(ownedCache, ownedIndex, requireNotNull(acquiredManager), initialized)
        } catch (failure: Throwable) {
            try {
                releaseResources(acquiredManager, acquiredCache)
            } catch (cleanup: Throwable) {
                failure.addSuppressed(cleanup)
            }
            throw failure
        }
    }

    private suspend fun restoreStoppedDownloads(ownedIndex: DefaultDownloadIndex) = withContext(Dispatchers.IO) {
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

    private class TransferResources(
        val cache: SimpleCache,
        val index: DefaultDownloadIndex,
        val manager: DownloadManager,
        val ready: CompletableDeferred<Unit>
    )

    override suspend fun enqueue(task: DownloadTask) {
        tasks[task.attemptId] = task
        val engine = initialize()
        val exists = withContext(Dispatchers.IO) { engine.index.getDownload(task.attemptId) != null }
        if (!exists) {
            withContext(Dispatchers.Main.immediate) {
                engine.manager.addDownload(request(task), if (task.userPaused) USER_PAUSED else NO_EXECUTION)
            }
        }
    }

    override suspend fun allow(task: DownloadTask, permitted: Boolean) {
        tasks[task.attemptId] = task
        val engine = initialize()
        withContext(Dispatchers.Main.immediate) {
            engine.manager.setStopReason(
                task.attemptId,
                when {
                    task.userPaused -> USER_PAUSED
                    !permitted -> NO_EXECUTION
                    else -> Download.STOP_REASON_NONE
                }
            )
            // Per-task stop reasons have been queued first. Global resume is only an execution mechanism.
            engine.manager.resumeDownloads()
        }
    }

    override suspend fun pause(attemptId: String) {
        val engine = initialize()
        withContext(Dispatchers.Main.immediate) { engine.manager.setStopReason(attemptId, USER_PAUSED) }
    }

    override suspend fun resume(attemptId: String) {
        val engine = initialize()
        // User intent alone does not grant a network/host lease. The runtime will call allow after checking both.
        val failed = withContext(Dispatchers.IO) {
            engine.index.getDownload(attemptId)?.state == Download.STATE_FAILED
        }
        withContext(Dispatchers.Main.immediate) {
            if (failed) {
                // Re-add the same request/cache key so a transient failure resumes its verified spans.
                tasks[attemptId]?.let { engine.manager.addDownload(request(it), NO_EXECUTION) }
                failures.remove(attemptId)
            } else {
                engine.manager.setStopReason(attemptId, NO_EXECUTION)
            }
        }
    }

    override suspend fun remove(attemptId: String) {
        val engine = initialize()
        withContext(Dispatchers.Main.immediate) { engine.manager.removeDownload(attemptId) }
        withTimeout(30_000) {
            while (withContext(Dispatchers.IO) { engine.index.getDownload(attemptId) != null }) delay(50)
        }
        tasks.remove(attemptId)
        failures.remove(attemptId)
    }

    override suspend fun snapshots(): List<ManagedTransferSnapshot> {
        val engine = initialize()
        val current =
            withContext(Dispatchers.Main.immediate) {
                engine.manager.currentDownloads.associateBy { it.request.id }
            }
        return withContext(Dispatchers.IO) {
            engine.index.getDownloads().use { cursor ->
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
            attemptId = download.request.id,
            phase = when (download.state) {
                Download.STATE_COMPLETED -> ManagedTransferPhase.Complete
                Download.STATE_FAILED -> ManagedTransferPhase.Failed
                Download.STATE_DOWNLOADING -> ManagedTransferPhase.Running
                Download.STATE_STOPPED -> if (download.stopReason == USER_PAUSED) {
                    ManagedTransferPhase.Paused
                } else {
                    ManagedTransferPhase.Waiting
                }
                else -> ManagedTransferPhase.Pending
            },
            bytes = download.bytesDownloaded,
            total = download.contentLength.takeIf { it != C.LENGTH_UNSET.toLong() && it > 0 },
            cacheKey = key,
            resumable = task?.acceptsRanges == true && (task.mediaEtag != null || task.mediaLastModified != null),
            failure = failures[download.request.id]
        )
    }

    override suspend fun openCached(task: DownloadTask): InputStream {
        tasks[task.attemptId] = task
        val engine = initialize()
        return withContext(Dispatchers.IO) {
            // A missing cache span must fail publication; no upstream factory is configured here.
            val source = CacheDataSource.Factory().setCache(engine.cache).createDataSource()
            DataSourceInputStream(
                source,
                DataSpec.Builder().setUri(task.url).setKey(task.cacheKey ?: task.attemptId).build()
            )
                .apply { open() }
        }
    }

    override suspend fun shutdown() = withContext(NonCancellable) {
        initialization.withLock {
            if (closed) return@withLock
            closed = true
            val owned = resources
            resources = null

            try {
                releaseResources(owned?.manager, owned?.cache)
            } finally {
                executor.shutdownNow()
            }
        }
    }

    /** Cleanup owns both resources even when one release fails or the caller has been cancelled. */
    private suspend fun releaseResources(manager: DownloadManager?, cache: SimpleCache?) = withContext(NonCancellable) {
        var failure: Throwable? = null
        try {
            withContext(Dispatchers.Main.immediate) { manager?.release() }
        } catch (cause: Throwable) {
            failure = cause
        }
        try {
            withContext(Dispatchers.IO) { cache?.release() }
        } catch (cause: Throwable) {
            if (failure == null) failure = cause else failure.addSuppressed(cause)
        }
        failure?.let { throw it }
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
        listeners += transferListener
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
