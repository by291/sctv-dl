package dev.sctvdl.data.downloads

import dev.sctvdl.data.downloads.local.DownloadStore
import dev.sctvdl.data.downloads.local.activeDownloadKey
import dev.sctvdl.data.downloads.platform.PlatformDownloadGateway
import dev.sctvdl.data.downloads.platform.PlatformDownloadRequest
import dev.sctvdl.data.downloads.platform.SystemDownloadSnapshot
import dev.sctvdl.domain.download.DownloadReason
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.isActive
import kotlinx.coroutines.flow.MutableStateFlow

internal class FakeDownloadStore : DownloadStore {
    val rows = MutableStateFlow(emptyList<DownloadTask>())

    override fun observe() = rows

    override suspend fun all() = rows.value

    override suspend fun get(id: String) = rows.value.firstOrNull { it.id == id }

    override suspend fun reserve(task: DownloadTask): Boolean {
        if (rows.value.any {
                (it.state.isActive || it.reasonCode == DownloadReason.Ambiguous) &&
                    activeDownloadKey(it) == activeDownloadKey(task)
            }
        ) {
            return false
        }
        update(task)
        return true
    }

    override suspend fun update(task: DownloadTask) {
        rows.value =
            rows.value.filterNot { it.id == task.id } + task
    }

    override suspend fun remove(id: String) {
        rows.value = rows.value.filterNot { it.id == id }
    }
}

internal class FakeDownloadGateway : PlatformDownloadGateway {
    val requests = mutableListOf<PlatformDownloadRequest>()
    val snapshots = mutableListOf<SystemDownloadSnapshot>()
    val removed = mutableListOf<Long>()
    var available = true
    var failEnqueue = false
    var failRemove = false

    override fun destinationFor(filename: String) = "file:///downloads/$filename"

    override suspend fun enqueue(request: PlatformDownloadRequest): Long {
        if (failEnqueue) throw IllegalStateException("system unavailable")
        requests.add(request)
        val id = requests.size.toLong()
        snapshots.add(
            SystemDownloadSnapshot(
                id,
                request.url,
                destinationFor(request.filename),
                DownloadState.Pending
            )
        )
        return id
    }

    override suspend fun query(ids: List<Long>) = snapshots.filter { it.id in ids }

    override suspend fun queryOwned() = snapshots.toList()

    override suspend fun remove(id: Long) {
        if (failRemove) throw IllegalStateException("system unavailable")
        removed.add(id)
        snapshots.removeAll {
            it.id == id
        }
    }

    override suspend fun isAvailable(uri: String) = available
}
