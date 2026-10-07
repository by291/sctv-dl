package dev.sctvdl.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface ProgrammeDao {
    @Query("SELECT * FROM snapshots WHERE `key` = :key")
    fun observe(key: String): Flow<SnapshotEntity?>

    @Upsert
    suspend fun put(snapshot: SnapshotEntity)

    @Query("SELECT id FROM favourites")
    fun observeFavourites(): Flow<List<String>>

    @Query("SELECT EXISTS(SELECT 1 FROM favourites WHERE id = :id)")
    suspend fun isFavourite(id: String): Boolean

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun addFavourite(favourite: FavouriteEntity)

    @Query("DELETE FROM favourites WHERE id = :id")
    suspend fun removeFavourite(id: String)
}
