package dev.sctvdl.data.programmes.local

import kotlinx.coroutines.flow.Flow

internal interface SnapshotStore {
    fun observe(key: String): Flow<StoredSnapshot?>
    suspend fun put(snapshot: StoredSnapshot)
}
