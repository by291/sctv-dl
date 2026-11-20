package dev.sctvdl.data.history

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import dev.sctvdl.data.database.LegacyUserImport
import dev.sctvdl.data.database.SctvDatabase
import dev.sctvdl.data.database.SctvUserDatabase
import dev.sctvdl.data.downloads.local.RoomDownloadStore
import dev.sctvdl.data.favourites.local.FavouriteEntity
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.media.Quality
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
import kotlinx.coroutines.cancelAndJoin
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
        val sourceRuntime = Room.inMemoryDatabaseBuilder(context, SctvDatabase::class.java).build()
        val destinationRuntime = Room.inMemoryDatabaseBuilder(context, SctvDatabase::class.java)
            .build()
        val sourceDownloads = RoomDownloadStore(sourceRuntime)
        val destinationDownloads = RoomDownloadStore(destinationRuntime)
        val sourceDownload = completedDownload("source", systemId = 17)
        val destinationDownload = completedDownload("destination", systemId = 25)
        var users = Room.databaseBuilder(context, SctvUserDatabase::class.java, sourceName).build()
        var writerJob = SupervisorJob()
        try {
            sourceDownloads.update(sourceDownload)
            destinationDownloads.update(destinationDownload)
            sourceRuntime.favourites().addFavourite(FavouriteEntity("7"))
            destinationRuntime.favourites().addFavourite(FavouriteEntity("8"))
            LegacyUserImport(sourceRuntime, users).ensureImported()
            assertEquals(listOf("7"), users.favourites().allIds())
            users.favourites().removeFavourite("7")
            val history = RoomHistoryRepository(users, CoroutineScope(writerJob + Dispatchers.IO))
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
                    ViewingEntry(target, 12_000, 60_000, Instant.EPOCH, completed = false)
                ).await()
            }

            writerJob.cancelAndJoin()
            users.close()
            context.getDatabasePath(sourceName).copyTo(context.getDatabasePath(restoredName))
            users = Room.databaseBuilder(context, SctvUserDatabase::class.java, restoredName).build()
            writerJob = SupervisorJob()
            LegacyUserImport(destinationRuntime, users).ensureImported()

            assertTrue(users.favourites().allIds().isEmpty())
            assertEquals(listOf(sourceDownload), sourceDownloads.all())
            assertEquals(listOf(destinationDownload), destinationDownloads.all())
            val restoredWriter = CoroutineScope(writerJob + Dispatchers.IO)
            val historyAfterRestore = RoomHistoryRepository(users, restoredWriter)
            val restored = historyAfterRestore.observeEntries().first()
            assertEquals(2, restored.size)
            assertEquals(
                setOf("10", "11"),
                restored.map {
                    (it.target as ViewingTarget.Online).selection.ref.dateId
                }.toSet()
            )
            assertTrue(restored.all { it.positionMs == 12_000L })
        } finally {
            writerJob.cancelAndJoin()
            users.close()
            sourceRuntime.close()
            destinationRuntime.close()
            context.deleteDatabase(sourceName)
            context.deleteDatabase(restoredName)
        }
    }

    private fun completedDownload(id: String, systemId: Long) = DownloadTask(
        id = id,
        contentId = systemId.toString(),
        title = "Episode $id",
        programmeName = "Programme",
        broadcastDate = LocalDate.of(2026, 10, 17),
        requestedQuality = Quality.Standard,
        actualQuality = Quality.Standard,
        url = "https://fscgc.scgchc.com/$id.mp4",
        filename = "$id.mp4",
        wifiOnly = true,
        systemId = systemId,
        contentUri = "content://downloads/$systemId",
        bytes = 4096,
        totalBytes = 4096,
        state = DownloadState.Completed,
        createdAt = Instant.EPOCH
    )
}
