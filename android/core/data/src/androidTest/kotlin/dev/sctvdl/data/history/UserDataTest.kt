package dev.sctvdl.data.history

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import dev.sctvdl.data.database.LegacyUserImport
import dev.sctvdl.data.database.SctvDatabase
import dev.sctvdl.data.database.SctvUserDatabase
import dev.sctvdl.data.favourites.RoomFavouriteRepository
import dev.sctvdl.data.favourites.local.FavouriteEntity
import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.repository.HistoryWriteResult
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UserDataTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val legacy = Room.inMemoryDatabaseBuilder(context, SctvDatabase::class.java).build()
    private val users = Room.inMemoryDatabaseBuilder(context, SctvUserDatabase::class.java).build()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val history = RoomHistoryRepository(users, scope)

    @After fun close() {
        scope.cancel()
        legacy.close()
        users.close()
    }

    @Test fun importMarkerKeepsUserDeletionsAuthoritative() = runBlocking {
        legacy.favourites().addFavourite(FavouriteEntity("7"))
        val importer = LegacyUserImport(legacy, users)
        val favourites = RoomFavouriteRepository(users, importer)
        assertEquals(setOf("7"), favourites.observeIds().first())
        favourites.toggle("7")

        LegacyUserImport(legacy, users).ensureImported()
        assertFalse(favourites.observeIds().first().contains("7"))
        assertTrue(legacy.favourites().isFavourite("7"))
    }

    @Test fun interruptedImportRollsBackBothFavouritesAndMarkerBeforeRetry() = runBlocking {
        legacy.favourites().addFavourite(FavouriteEntity("7"))
        legacy.favourites().addFavourite(FavouriteEntity("8"))
        users.openHelper.writableDatabase.execSQL(
            "CREATE TRIGGER reject_import BEFORE INSERT ON favourites WHEN NEW.id = '8' BEGIN SELECT RAISE(ABORT, 'fixture interruption'); END"
        )
        val importer = LegacyUserImport(legacy, users)
        val failed = runCatching { importer.ensureImported() }.isFailure
        assertTrue(failed)
        assertTrue(users.favourites().allIds().isEmpty())
        assertEquals(null, users.history().metadata("legacy_favourites_imported"))
        users.openHelper.writableDatabase.execSQL("DROP TRIGGER reject_import")
        importer.ensureImported()
        assertEquals(setOf("7", "8"), users.favourites().allIds().toSet())
    }

    @Test fun staleSessionsCannotResurrectClearedRemovedOrReopenedRows() = runBlocking {
        val entry = entry("7")
        val old = history.begin(entry.target)
        history.submit(old, entry).await()
        history.clear()
        assertEquals(HistoryWriteResult.Invalidated, history.submit(old, entry).await())
        val newer = history.begin(entry.target)
        history.submit(newer, entry.copy(positionMs = 20_000)).await()
        assertEquals(HistoryWriteResult.Invalidated, history.submit(old, entry).await())
        assertEquals(20_000, history.observeEntries().first().single().positionMs)
        history.remove(entry.key)
        assertEquals(HistoryWriteResult.Invalidated, history.submit(newer, entry).await())
        assertTrue(history.observeEntries().first().isEmpty())
    }

    @Test fun keepsNewestFiveHundredWithDeterministicTies() = runBlocking {
        repeat(501) { index ->
            val entry = entry(index.toString().padStart(3, '0'))
            history.submit(history.begin(entry.target), entry).await()
        }
        val entries = history.observeEntries().first()
        assertEquals(500, entries.size)
        assertEquals("500", (entries.first().target as ViewingTarget.LegacyDownload).taskId)
        assertEquals("001", (entries.last().target as ViewingTarget.LegacyDownload).taskId)
    }

    private fun entry(id: String) = ViewingEntry(
        ViewingTarget.LegacyDownload(id, "Episode", "Programme", LocalDate.of(2026, 10, 17)),
        12_000,
        100_000,
        Instant.EPOCH,
        false
    )
}
