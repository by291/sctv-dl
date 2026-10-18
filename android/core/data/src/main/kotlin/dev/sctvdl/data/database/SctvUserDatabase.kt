package dev.sctvdl.data.database

import androidx.room.Database
import androidx.room.RoomDatabase
import dev.sctvdl.data.favourites.local.FavouriteDao
import dev.sctvdl.data.favourites.local.FavouriteEntity
import dev.sctvdl.data.history.local.HistoryDao
import dev.sctvdl.data.history.local.HistoryEntity
import dev.sctvdl.data.history.local.HistorySessionEntity
import dev.sctvdl.data.history.local.UserMetadata

@Database(
    entities = [FavouriteEntity::class, HistoryEntity::class, HistorySessionEntity::class, UserMetadata::class],
    version = 1,
    exportSchema = true
)
internal abstract class SctvUserDatabase : RoomDatabase() {
    abstract fun favourites(): FavouriteDao

    abstract fun history(): HistoryDao
}
