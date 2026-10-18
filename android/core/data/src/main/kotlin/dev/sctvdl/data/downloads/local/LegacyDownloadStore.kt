package dev.sctvdl.data.downloads.local

import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadTask
import kotlinx.coroutines.flow.map

/** Prevents system reconciliation from interpreting Media3 attempt IDs as missing platform jobs. */
internal class LegacyDownloadStore(private val store: DownloadStore) : DownloadStore {
    override fun observe() = store.observe().map { tasks -> tasks.filter { it.owner == DownloadOwner.LegacySystem } }

    override suspend fun all() = store.all().filter { it.owner == DownloadOwner.LegacySystem }

    override suspend fun get(id: String) = store.get(id)?.takeIf { it.owner == DownloadOwner.LegacySystem }

    override suspend fun reserve(task: DownloadTask) = store.reserve(task)

    override suspend fun update(task: DownloadTask) = store.update(task)

    override suspend fun remove(id: String) = store.remove(id)
}
