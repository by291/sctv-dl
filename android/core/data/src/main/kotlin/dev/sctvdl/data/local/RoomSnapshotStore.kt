package dev.sctvdl.data.local

import dev.sctvdl.data.repository.SnapshotStore
import dev.sctvdl.data.repository.StoredSnapshot
import javax.inject.Inject
import kotlinx.coroutines.flow.map

class RoomSnapshotStore @Inject constructor(private val database: SctvDatabase) : SnapshotStore {
    override fun observe(key: String) = database.programmes().observe(key).map { row ->
        row?.let { StoredSnapshot(it.key, it.payload, it.updatedAt) }
    }
    override suspend fun put(snapshot: StoredSnapshot) = database.programmes().put(
        SnapshotEntity(snapshot.key, snapshot.payload, snapshot.updatedAt)
    )
}
