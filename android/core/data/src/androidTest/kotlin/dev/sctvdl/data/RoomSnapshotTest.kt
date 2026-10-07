package dev.sctvdl.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.sctvdl.data.local.FavouriteEntity
import dev.sctvdl.data.local.SctvDatabase
import dev.sctvdl.data.local.SnapshotEntity
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
            val dao = database.programmes()
            assertNull(dao.observe("dates:1").first())
            dao.put(SnapshotEntity("dates:1", "{\"rs\":200,\"data\":[]}", 123))
            assertEquals("{\"rs\":200,\"data\":[]}", dao.observe("dates:1").first()?.payload)
            dao.addFavourite(FavouriteEntity("2107420533961056258"))
            assertEquals(listOf("2107420533961056258"), dao.observeFavourites().first())
        } finally {
            database.close()
        }
    }
}
