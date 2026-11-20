package dev.sctvdl.data.downloads

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import dev.sctvdl.data.database.SctvDatabase
import dev.sctvdl.data.di.DownloadFileConsentRegistry
import dev.sctvdl.data.downloads.local.RoomDownloadStore
import dev.sctvdl.data.downloads.managed.ManagedDownloadControl
import dev.sctvdl.data.downloads.platform.FileDeleteResult
import dev.sctvdl.data.downloads.platform.PublicDownloadFiles
import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadActionResult
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.target
import dev.sctvdl.domain.media.Quality
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private const val ORIGINAL_URI = "content://downloads/original"
private const val REPLACEMENT_URI = "content://downloads/replacement"
private const val CONSENT_TIMEOUT_MS = 10_000L

class DownloadConsentTest {
    @Test fun grantedConsentDeletesTheSameCompletedFile() = withConsent { fixture ->
        val result = fixture.complete(granted = true)

        assertEquals(DownloadActionResult.Applied, result)
        assertEquals(DownloadState.Missing, fixture.current().state)
        assertFalse(fixture.files.isReadable(ORIGINAL_URI))
        assertEquals(DownloadActionResult.Skipped, fixture.complete(granted = true))
    }

    @Test fun lateGrantCannotDeleteAReplacementAttemptAtTheSameUri() = withConsent { fixture ->
        val replacement = fixture.original.copy(attemptId = "replacement-attempt")
        fixture.store.update(replacement)

        val result = fixture.complete(granted = true)

        assertEquals(DownloadActionResult.Skipped, result)
        assertEquals(replacement, fixture.current())
        assertTrue(fixture.files.isReadable(ORIGINAL_URI))
    }

    @Test fun lateGrantCannotDeleteAChangedUriForTheSameAttempt() = withConsent { fixture ->
        val replacement = fixture.original.copy(contentUri = REPLACEMENT_URI)
        fixture.store.update(replacement)

        val result = fixture.complete(granted = true)

        assertEquals(DownloadActionResult.Skipped, result)
        assertEquals(replacement, fixture.current())
        assertTrue(fixture.files.isReadable(ORIGINAL_URI))
        assertTrue(fixture.files.isReadable(REPLACEMENT_URI))
    }

    @Test fun deniedConsentKeepsTheFileAndCannotBeReplayed() = withConsent { fixture ->
        val result = fixture.complete(granted = false)
        val replay = fixture.complete(granted = true)

        assertEquals(DownloadActionResult.Skipped, result)
        assertEquals(DownloadActionResult.Skipped, replay)
        assertEquals(fixture.original, fixture.current())
        assertTrue(fixture.files.isReadable(ORIGINAL_URI))
    }

    private fun withConsent(exercise: suspend (PendingDeletion) -> Unit): Unit = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val intent = Intent("dev.sctvdl.test.DELETE").setPackage(context.packageName)
        intent.addCategory(UUID.randomUUID().toString())
        val authorization = PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE
        )
        val registry = DownloadFileConsentRegistry()
        val files = ConsentFiles { uri -> registry.register(uri, authorization.intentSender) }
        val original = completedDownload()
        val database = Room.inMemoryDatabaseBuilder(context, SctvDatabase::class.java).build()

        try {
            withTimeout(CONSENT_TIMEOUT_MS) {
                val store = RoomDownloadStore(database)
                store.update(original)
                val repository = ManagedDownloadRepository(
                    store = store,
                    legacy = UnusedLegacyRecovery,
                    control = UnusedTransferControl,
                    files = files,
                    consents = registry,
                    transitions = DownloadTransitions(),
                    clock = Clock.systemUTC()
                )
                val result = repository.perform(original.target, DownloadAction.DeleteFile)
                val token = (result as DownloadActionResult.ConsentRequired).token
                assertNotNull(registry.intentSender(token))
                assertTrue(files.isReadable(ORIGINAL_URI))

                exercise(
                    PendingDeletion(
                        original = original,
                        store = store,
                        files = files,
                        token = token,
                        repository = repository
                    )
                )

                assertNull(registry.intentSender(token))
            }
        } finally {
            authorization.cancel()
            database.close()
        }
    }

    private fun completedDownload() = DownloadTask(
        id = "record",
        contentId = "1",
        title = "Episode",
        programmeName = "Programme",
        broadcastDate = LocalDate.of(2026, 10, 17),
        requestedQuality = Quality.Standard,
        actualQuality = Quality.Standard,
        url = "https://fscgc.scgchc.com/a.mp4",
        filename = "a.mp4",
        wifiOnly = true,
        contentUri = ORIGINAL_URI,
        state = DownloadState.Completed,
        createdAt = Instant.EPOCH,
        owner = DownloadOwner.Media3
    )

    private data class PendingDeletion(
        val original: DownloadTask,
        val store: RoomDownloadStore,
        val files: ConsentFiles,
        val token: String,
        val repository: ManagedDownloadRepository
    ) {
        suspend fun complete(granted: Boolean): DownloadActionResult {
            // A late OS verdict must be checked against the file and attempt still stored.
            files.hasAuthorization = granted
            return repository.completeFileConsent(original.target, token, granted = granted)
        }

        suspend fun current() = requireNotNull(store.get(original.id))
    }

    private class ConsentFiles(private val newToken: (String) -> String) : PublicDownloadFiles {
        var hasAuthorization = false

        private val files = mutableSetOf(ORIGINAL_URI, REPLACEMENT_URI)

        override suspend fun reserve(task: DownloadTask): String = error("Unexpected reservation")

        override suspend fun copyCached(task: DownloadTask, pendingUri: String): Long {
            error("Consent fixture cannot copy cached media")
        }

        override suspend fun finalize(pendingUri: String) = error("Unexpected file publication")

        override suspend fun isReadable(uri: String) = uri in files

        override suspend fun isPublished(task: DownloadTask, uri: String) = uri in files

        override suspend fun delete(uri: String): FileDeleteResult {
            if (!hasAuthorization) {
                return FileDeleteResult.ConsentRequired(newToken(uri))
            }
            return if (files.remove(uri)) FileDeleteResult.Deleted else FileDeleteResult.Missing
        }

        override suspend fun findPlanned(task: DownloadTask) = emptyList<String>()
    }

    private object UnusedLegacyRecovery : LegacyDownloadRecovery {
        override suspend fun reconcile() = error("Unexpected legacy reconciliation")

        override suspend fun cancel(taskId: String) = error("Unexpected legacy cancellation")
    }

    private object UnusedTransferControl : ManagedDownloadControl {
        override suspend fun reconcile() = error("Unexpected transfer reconciliation")

        override suspend fun start() = error("Unexpected transfer start")

        override suspend fun stop(task: DownloadTask) = error("Unexpected transfer stop")

        override suspend fun remove(task: DownloadTask) = error("Unexpected transfer removal")
    }
}
