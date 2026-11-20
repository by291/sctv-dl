package dev.sctvdl.data.downloads

import androidx.room.testing.MigrationTestHelper
import androidx.test.platform.app.InstrumentationRegistry
import dev.sctvdl.data.database.SctvDatabase
import dev.sctvdl.data.database.openRuntimeDatabase
import dev.sctvdl.data.downloads.local.RoomDownloadStore
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadReason
import dev.sctvdl.domain.download.DownloadState
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class DownloadMigrationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @get:Rule val helper = MigrationTestHelper(instrumentation, SctvDatabase::class.java)

    @Test fun versionOneRetainsLegacyOwnershipIdentityAndPublicFiles(): Unit = runBlocking {
        val context = instrumentation.targetContext
        val databaseName = "migration-fixture-${UUID.randomUUID()}.db"

        try {
            helper.createDatabase(databaseName, 1).use { database ->
                database.execSQL(
                    """
                    INSERT INTO downloads (
                        id, activeKey, contentId, title, programmeName, broadcastDate,
                        requestedQuality, actualQuality, url, filename, wifiOnly, systemId,
                        contentUri, bytes, totalBytes, state, reason, reasonCode, createdAt
                    ) VALUES (
                        'old', '1|Standard', '1', 'Episode', 'Programme', '2026-10-17',
                        'Standard', 'Standard', 'https://fscgc.scgchc.com/a.mp4', 'a.mp4', 1, 42,
                        'content://downloads/42', 1024, 4096, 'Waiting', NULL, 'Ambiguous', 10
                    )
                    """.trimIndent()
                )
            }

            val database = openRuntimeDatabase(context, databaseName)
            try {
                val download = requireNotNull(RoomDownloadStore(database).get("old"))

                assertEquals(42L, download.systemId)
                assertEquals(DownloadOwner.LegacySystem, download.owner)
                assertEquals("old", download.attemptId)
                assertEquals("content://downloads/42", download.contentUri)
                assertTrue(database.downloads().activeExists("1|Standard"))
                assertEquals(1024L, download.bytes)
                assertEquals(4096L, download.totalBytes)
                assertEquals(DownloadState.Waiting, download.state)
                assertEquals(DownloadReason.Ambiguous, download.reasonCode)
            } finally {
                database.close()
            }
        } finally {
            context.deleteDatabase(databaseName)
        }
    }
}
