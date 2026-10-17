package dev.sctvdl.data.history.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
internal interface HistoryDao {
    @Query("SELECT * FROM viewing_history ORDER BY viewedAt DESC, `key` DESC")
    fun observe(): Flow<List<HistoryEntity>>

    @Query("SELECT * FROM viewing_history WHERE `key` = :key")
    suspend fun get(key: String): HistoryEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun put(entry: HistoryEntity)

    @Query(
        "DELETE FROM viewing_history WHERE `key` NOT IN (SELECT `key` FROM viewing_history ORDER BY viewedAt DESC, `key` DESC LIMIT 500)"
    )
    suspend fun trim()

    @Query("DELETE FROM viewing_history WHERE `key` = :key")
    suspend fun remove(key: String)

    @Query("DELETE FROM viewing_history")
    suspend fun clear()

    @Query("SELECT * FROM history_sessions WHERE `key` = :key")
    suspend fun session(key: String): HistorySessionEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun putSession(session: HistorySessionEntity)

    @Query("UPDATE history_sessions SET deletionGeneration = deletionGeneration + 1")
    suspend fun invalidateAll()

    @Query("SELECT value FROM user_metadata WHERE `key` = :key")
    suspend fun metadata(key: String): String?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun putMetadata(metadata: UserMetadata)
}
