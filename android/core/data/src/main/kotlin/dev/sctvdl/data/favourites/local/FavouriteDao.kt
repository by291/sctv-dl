package dev.sctvdl.data.favourites.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
internal interface FavouriteDao {
    @Query("SELECT id FROM favourites")
    fun observeFavourites(): Flow<List<String>>

    @Query("SELECT id FROM favourites")
    suspend fun allIds(): List<String>

    @Query("SELECT EXISTS(SELECT 1 FROM favourites WHERE id = :id)")
    suspend fun isFavourite(id: String): Boolean

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun addFavourite(favourite: FavouriteEntity)

    @Query("DELETE FROM favourites WHERE id = :id")
    suspend fun removeFavourite(id: String)
}
