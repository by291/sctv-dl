package dev.sctvdl.app.platform

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppStorageMaintenanceTest {
    @Test fun imageCleanupRunsEvenWhenMetadataCleanupFails() = runTest {
        var imagesCleared = false
        val maintenance = AppStorageMaintenance({ error("Database unavailable") }, { imagesCleared = true })
        val result = maintenance.clearCache()
        assertFalse(result.metadataCleared)
        assertNotNull(result.metadataFailure)
        assertTrue(result.imagesCleared)
        assertTrue(imagesCleared)
    }
}
