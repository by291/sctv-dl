package dev.sctvdl.data.database

import androidx.room.Database
import androidx.room.RoomDatabase
import dev.sctvdl.data.downloads.local.DownloadDao
import dev.sctvdl.data.downloads.local.DownloadEntity
import dev.sctvdl.data.favourites.local.FavouriteDao
import dev.sctvdl.data.favourites.local.FavouriteEntity
import dev.sctvdl.data.programmes.local.ProgrammeSnapshotDao
import dev.sctvdl.data.programmes.local.SnapshotEntity

@Database(
    entities = [SnapshotEntity::class, FavouriteEntity::class, DownloadEntity::class],
    version = 1,
    exportSchema = true
)
internal abstract class SctvDatabase : RoomDatabase() {
    abstract fun snapshots(): ProgrammeSnapshotDao
    abstract fun favourites(): FavouriteDao
    abstract fun downloads(): DownloadDao
}
