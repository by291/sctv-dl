package dev.sctvdl.data.history

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import dev.sctvdl.data.database.LegacyUserImport
import dev.sctvdl.data.database.SctvDatabase
import dev.sctvdl.data.database.SctvUserDatabase
import dev.sctvdl.data.favourites.local.FavouriteEntity
import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.programme.ProgrammeSelection
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class UserRestoreTest {
    @Test fun userOnlyRestoreKeepsExactHistoryAndDoesNotReimportDeletedFavouritesOrJobs() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val sourceName = "user-source-${UUID.randomUUID()}.db"
        val restoredName = "user-restored-${UUID.randomUUID()}.db"
        val runtime = Room.inMemoryDatabaseBuilder(context, SctvDatabase::class.java).build()
        var users = Room.databaseBuilder(context, SctvUserDatabase::class.java, sourceName).build()
        var writerScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            runtime.favourites().addFavourite(FavouriteEntity("7"))
            LegacyUserImport(runtime, users).ensureImported()
            users.favourites().removeFavourite("7")
            val history = RoomHistoryRepository(users, writerScope)
            for (dateId in listOf("10", "11")) {
                val target = ViewingTarget.Online(
                    ProgrammeSelection(
                        Programme("7", "Same programme", null, 0),
                        BroadcastDate(dateId, LocalDate.of(2026, 10, 17)),
                        ProgrammeContent("42", "Same title", standardUrl = "https://fscgc.scgchc.com/a.mp4")
                    )
                )
                history.submit(
                    history.begin(target),
                    ViewingEntry(target, 12_000, 60_000, Instant.EPOCH, false)
                ).await()
            }
            writerScope.cancel()
            users.close()
            context.getDatabasePath(sourceName).copyTo(context.getDatabasePath(restoredName))
            users = Room.databaseBuilder(context, SctvUserDatabase::class.java, restoredName).build()
            writerScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            LegacyUserImport(runtime, users).ensureImported()
            assertTrue(users.favourites().allIds().isEmpty())
            assertTrue(runtime.downloads().all().isEmpty())
            val restored = RoomHistoryRepository(users, writerScope).observeEntries().first()
            assertEquals(2, restored.size)
            assertEquals(
                setOf("10", "11"),
                restored.map {
                    (it.target as ViewingTarget.Online).selection.ref.dateId
                }.toSet()
            )
            assertTrue(restored.all { it.positionMs == 12_000L })
        } finally {
            writerScope.cancel()
            users.close()
            runtime.close()
            context.deleteDatabase(sourceName)
            context.deleteDatabase(restoredName)
        }
    }
}
