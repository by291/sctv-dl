package dev.sctvdl.data.downloads.local

import androidx.room.withTransaction
import dev.sctvdl.data.database.SctvDatabase
import dev.sctvdl.domain.download.DownloadTask
import javax.inject.Inject
import kotlinx.coroutines.flow.map

internal class RoomDownloadStore @Inject constructor(private val database: SctvDatabase) : DownloadStore {
    private val dao get() = database.downloads()
    override fun observe() = dao.observe().map { it.map(DownloadEntity::toTask) }
    override suspend fun all() = dao.all().map(DownloadEntity::toTask)
    override suspend fun get(id: String) = dao.get(id)?.toTask()
    override suspend fun reserve(task: DownloadTask): Boolean = database.withTransaction {
        if (dao.activeExists(activeDownloadKey(task))) {
            false
        } else {
            dao.put(task.toEntity())
            true
        }
    }
    override suspend fun update(task: DownloadTask) = dao.put(task.toEntity())
    override suspend fun remove(id: String) = dao.remove(id)
}
