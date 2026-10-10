package dev.sctvdl.data.programmes.local

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
internal interface ProgrammeSnapshotDao {
    @Query("SELECT * FROM snapshots WHERE `key` = :key")
    fun observe(key: String): Flow<SnapshotEntity?>

    @Upsert
    suspend fun put(snapshot: SnapshotEntity)
}
