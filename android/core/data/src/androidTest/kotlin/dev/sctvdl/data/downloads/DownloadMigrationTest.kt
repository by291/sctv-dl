package dev.sctvdl.data.downloads

import androidx.room.testing.MigrationTestHelper
import androidx.test.platform.app.InstrumentationRegistry
import dev.sctvdl.data.database.RuntimeMigrations
import dev.sctvdl.data.database.SctvDatabase
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class DownloadMigrationTest {
    @get:Rule val helper = MigrationTestHelper(InstrumentationRegistry.getInstrumentation(), SctvDatabase::class.java)

    @Test fun versionOneRetainsLegacyOwnershipIdentityAndPublicFiles() {
        val name = "migration-fixture"
        helper.createDatabase(name, 1).use { db ->
            db.execSQL(
                "INSERT INTO downloads (id, activeKey, contentId, title, programmeName, broadcastDate, requestedQuality, actualQuality, url, filename, wifiOnly, systemId, contentUri, bytes, totalBytes, state, reason, reasonCode, createdAt) VALUES ('old', '1|Standard', '1', 'Episode', 'Programme', '2026-10-17', 'Standard', 'Standard', 'https://fscgc.scgchc.com/a.mp4', 'a.mp4', 1, 42, 'content://downloads/42', 1024, 4096, 'Waiting', NULL, 'Ambiguous', 10)"
            )
        }
        helper.runMigrationsAndValidate(name, 2, true, RuntimeMigrations.OneToTwo).use { db ->
            db.query("SELECT systemId, owner, attemptId, contentUri, activeKey, bytes FROM downloads").use { row ->
                row.moveToFirst()
                assertEquals(42, row.getLong(0))
                assertEquals("LegacySystem", row.getString(1))
                assertEquals("old", row.getString(2))
                assertEquals("content://downloads/42", row.getString(3))
                assertEquals("1|Standard", row.getString(4))
                assertEquals(1024, row.getLong(5))
            }
        }
        InstrumentationRegistry.getInstrumentation().targetContext.deleteDatabase(name)
    }
}
