package dev.sctvdl.data.programmes.local

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.sctvdl.data.database.SctvDatabase
import dev.sctvdl.data.favourites.local.FavouriteEntity
import dev.sctvdl.data.programmes.local.SnapshotEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RoomSnapshotTest {
    @Test fun successfulEmptySnapshotAndLargeFavouriteIdPersist() = runBlocking {
        val database = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            SctvDatabase::class.java
        ).build()
        try {
            val dao = database.snapshots()
            assertNull(dao.observe("dates:1").first())
            dao.put(SnapshotEntity("dates:1", "{\"rs\":200,\"data\":[]}", 123))
            assertEquals("{\"rs\":200,\"data\":[]}", dao.observe("dates:1").first()?.payload)
            database.favourites().addFavourite(FavouriteEntity("2107420533961056258"))
            assertEquals(listOf("2107420533961056258"), database.favourites().observeFavourites().first())
        } finally {
            database.close()
        }
    }
}
