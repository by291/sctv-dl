package dev.sctvdl.data.repository

import kotlinx.coroutines.flow.Flow

data class StoredSnapshot(val key: String, val payload: String, val updatedAt: Long)
interface SnapshotStore {
    fun observe(key: String): Flow<StoredSnapshot?>
    suspend fun put(snapshot: StoredSnapshot)
}
interface ProgrammeSource {
    suspend fun programmes(): String
    suspend fun dates(programmeId: String): String
    suspend fun contents(programmeId: String, dateId: String): String
}
