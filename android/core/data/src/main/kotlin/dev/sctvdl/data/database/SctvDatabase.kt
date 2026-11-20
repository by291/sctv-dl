package dev.sctvdl.data.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import dev.sctvdl.data.downloads.local.DownloadDao
import dev.sctvdl.data.downloads.local.DownloadEntity
import dev.sctvdl.data.favourites.local.FavouriteDao
import dev.sctvdl.data.favourites.local.FavouriteEntity
import dev.sctvdl.data.programmes.local.ProgrammeSnapshotDao
import dev.sctvdl.data.programmes.local.SnapshotEntity

@Database(
    entities = [SnapshotEntity::class, FavouriteEntity::class, DownloadEntity::class],
    version = 2,
    exportSchema = true
)
internal abstract class SctvDatabase : RoomDatabase() {
    abstract fun snapshots(): ProgrammeSnapshotDao

    abstract fun favourites(): FavouriteDao

    abstract fun downloads(): DownloadDao
}

/** Opens the runtime database with the registered migrations for installed data. */
internal fun openRuntimeDatabase(context: Context, name: String = "sctv-metadata.db") =
    Room.databaseBuilder(context, SctvDatabase::class.java, name)
        .addMigrations(RuntimeMigrations.OneToTwo)
        .build()
