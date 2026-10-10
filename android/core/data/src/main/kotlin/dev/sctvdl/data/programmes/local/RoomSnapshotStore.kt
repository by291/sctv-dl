package dev.sctvdl.data.programmes.local

import dev.sctvdl.data.database.SctvDatabase
import dev.sctvdl.data.programmes.local.SnapshotStore
import dev.sctvdl.data.programmes.local.StoredSnapshot
import javax.inject.Inject
import kotlinx.coroutines.flow.map

internal class RoomSnapshotStore @Inject constructor(private val database: SctvDatabase) : SnapshotStore {
    override fun observe(key: String) = database.snapshots().observe(key).map { row ->
        row?.let { StoredSnapshot(it.key, it.payload, it.updatedAt) }
    }

    override suspend fun put(snapshot: StoredSnapshot) = database.snapshots().put(
        SnapshotEntity(snapshot.key, snapshot.payload, snapshot.updatedAt)
    )
}
