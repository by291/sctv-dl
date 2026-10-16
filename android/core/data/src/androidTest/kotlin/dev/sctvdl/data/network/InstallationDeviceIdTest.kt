package dev.sctvdl.data.network

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class InstallationDeviceIdTest {
    @Test fun concurrentRequestsAndRecreatedProvidersKeepThePersistedIdentity() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "device-id-test-${UUID.randomUUID()}"
        val preferences = context.getSharedPreferences(name, Context.MODE_PRIVATE)
        val executor = Executors.newFixedThreadPool(4)
        try {
            val ids = executor.invokeAll(
                List(8) {
                    Callable { InstallationDeviceId(preferences).getOrCreate() }
                }
            ).map { it.get() }

            assertEquals(1, ids.distinct().size)
            assertEquals(ids.first(), UUID.fromString(ids.first()).toString())
            assertEquals(ids.first(), InstallationDeviceId(preferences).getOrCreate())
            assertTrue(preferences.all.values.contains(ids.first()))
        } finally {
            executor.shutdownNow()
            context.deleteSharedPreferences(name)
        }
    }

    @Test fun differentInstallationsUseDifferentDeviceIdentities() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val names = List(2) { "device-id-test-${UUID.randomUUID()}" }
        try {
            val ids = names.map { name ->
                InstallationDeviceId(context.getSharedPreferences(name, Context.MODE_PRIVATE)).getOrCreate()
            }

            assertNotEquals(ids[0], ids[1])
        } finally {
            names.forEach(context::deleteSharedPreferences)
        }
    }
}
