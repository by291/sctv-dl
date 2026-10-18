@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package dev.sctvdl.data.downloads.managed

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.media3.database.DatabaseProvider
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.ByteArrayDataSource
import androidx.media3.datasource.DataSource
import androidx.test.core.app.ApplicationProvider
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TransferInitializationTest {
    @Test fun failedIndexRestorationReleasesTheCacheBeforeRetry() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val directory = context.noBackupFilesDir.resolve("initialization-${UUID.randomUUID()}")
        val database = FailingDatabase(StandaloneDatabaseProvider(context))
        val gateway = Media3TransferGateway(context, directory, database, directory.name.replace("-", "")) {
            DataSource.Factory { ByteArrayDataSource(byteArrayOf(1)) }
        }

        try {
            database.onRead = { throw IOException("Index temporarily unavailable") }
            assertNotNull(runCatching { gateway.snapshots() }.exceptionOrNull())

            database.onRead = {}
            assertTrue("Retry must reopen the same cache directory", gateway.snapshots().isEmpty())
        } finally {
            gateway.shutdown()
            database.close()
            directory.deleteRecursively()
        }
    }

    @Test fun cancellationDuringRestorationReleasesPartiallyAcquiredResources() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val directory = context.noBackupFilesDir.resolve("cancellation-${UUID.randomUUID()}")
        val database = FailingDatabase(StandaloneDatabaseProvider(context))
        val gateway = Media3TransferGateway(context, directory, database, directory.name.replace("-", "")) {
            DataSource.Factory { ByteArrayDataSource(byteArrayOf(1)) }
        }

        try {
            val initialization = launch(start = CoroutineStart.LAZY) { gateway.snapshots() }
            database.onRead = { initialization.cancel() }
            initialization.start()
            initialization.join()
            assertTrue(initialization.isCancelled)

            database.onRead = {}
            assertTrue("Cancellation must not leave the cache directory locked", gateway.snapshots().isEmpty())
            gateway.shutdown()
            gateway.shutdown()
        } finally {
            gateway.shutdown()
            database.close()
            directory.deleteRecursively()
        }
    }

    private class FailingDatabase(private val delegate: StandaloneDatabaseProvider) : DatabaseProvider {
        var onRead: () -> Unit = {}

        override fun getReadableDatabase(): SQLiteDatabase {
            onRead()
            return delegate.readableDatabase
        }

        override fun getWritableDatabase(): SQLiteDatabase = delegate.writableDatabase

        fun close() = delegate.close()
    }
}
