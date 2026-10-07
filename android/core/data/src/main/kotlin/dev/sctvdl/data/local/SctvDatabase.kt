package dev.sctvdl.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import dev.sctvdl.data.downloads.DownloadDao
import dev.sctvdl.data.downloads.DownloadEntity

@Database(
    entities = [SnapshotEntity::class, FavouriteEntity::class, DownloadEntity::class],
    version = 1,
    exportSchema = true
)
abstract class SctvDatabase : RoomDatabase() {
    abstract fun programmes(): ProgrammeDao
    abstract fun downloads(): DownloadDao
}
