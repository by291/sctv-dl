package dev.sctvdl.data.downloads

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface DownloadDao {
    @Query("SELECT * FROM downloads ORDER BY createdAt DESC")
    fun observe(): Flow<List<DownloadEntity>>

    @Query("SELECT * FROM downloads ORDER BY createdAt DESC")
    suspend fun all(): List<DownloadEntity>

    @Query("SELECT * FROM downloads WHERE id = :id")
    suspend fun get(id: String): DownloadEntity?

    @Query("SELECT EXISTS(SELECT 1 FROM downloads WHERE activeKey = :key)")
    suspend fun activeExists(key: String): Boolean

    @Upsert suspend fun put(task: DownloadEntity)

    @Query("DELETE FROM downloads WHERE id = :id")
    suspend fun remove(id: String)
}
