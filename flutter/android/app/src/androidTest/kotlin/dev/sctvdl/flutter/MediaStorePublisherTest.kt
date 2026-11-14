package dev.sctvdl.flutter

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

private const val SOURCE_BYTES = 128

@RunWith(AndroidJUnit4::class)
class MediaStorePublisherTest {
    @Test
    fun replacesPartialPendingRowsWithoutAcceptingAnInvisibleFile() = recoverPending(7)

    @Test
    fun replacesFullLengthPendingRowsBeforeReportingPublished() = recoverPending(SOURCE_BYTES)

    @Test
    fun retryReusesTheVisiblePublicationAndKeepsThePrivateSource() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val resolver = context.contentResolver
        val source = createSource(context)
        val publisher = MediaStorePublisher(resolver, context.packageName, context.filesDir)
        var published: Uri? = null
        var retried: Uri? = null

        try {
            published = publisher.publish(source, source.name)
            retried = publisher.publish(source, source.name)

            assertEquals(published, retried)
            assertPublishedBytes(resolver, published, source)
            assertTrue(source.exists())
        } finally {
            if (retried != null && retried != published) {
                resolver.delete(retried, null, null)
            }
            published?.let { resolver.delete(it, null, null) }
            source.delete()
        }
    }

    private fun recoverPending(pendingBytes: Int) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val resolver = context.contentResolver
        val source = createSource(context)
        var abandoned: Uri? = null
        var published: Uri? = null

        try {
            abandoned = reservePending(resolver, source.name)
            checkNotNull(resolver.openOutputStream(abandoned)).use {
                it.write(ByteArray(pendingBytes))
            }

            val publisher = MediaStorePublisher(resolver, context.packageName, context.filesDir)
            published = publisher.publish(source, source.name)

            assertNotEquals(abandoned, published)
            val idProjection = arrayOf(MediaStore.MediaColumns._ID)
            checkNotNull(resolver.query(abandoned, idProjection, null, null, null)).use { rows ->
                assertFalse(rows.moveToFirst())
            }

            val publicationProjection =
                arrayOf(
                    MediaStore.MediaColumns.IS_PENDING,
                    MediaStore.MediaColumns.OWNER_PACKAGE_NAME,
                )
            val rows = resolver.query(published, publicationProjection, null, null, null)
            checkNotNull(rows).use { metadata ->
                assertTrue(metadata.moveToFirst())
                assertEquals(0, metadata.getInt(0))
                assertEquals(context.packageName, metadata.getString(1))
            }
            assertPublishedBytes(resolver, published, source)
            assertTrue(source.exists())
        } finally {
            published?.let { resolver.delete(it, null, null) }
            abandoned?.let { resolver.delete(it, null, null) }
            source.delete()
        }
    }

    private fun createSource(context: Context): File {
        val filename = "publication-fixture-${System.nanoTime()}.mp4"
        return File(context.filesDir, filename).apply {
            writeBytes(ByteArray(SOURCE_BYTES) { it.toByte() })
        }
    }

    private fun reservePending(
        resolver: ContentResolver,
        filename: String,
    ): Uri {
        val destination = Environment.DIRECTORY_DOWNLOADS + "/sctv-dl/"
        val values =
            ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
                put(MediaStore.MediaColumns.RELATIVE_PATH, destination)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        return checkNotNull(resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values))
    }

    private fun assertPublishedBytes(
        resolver: ContentResolver,
        published: Uri,
        source: File,
    ) {
        checkNotNull(resolver.openInputStream(published)).use {
            assertArrayEquals(source.readBytes(), it.readBytes())
        }
    }
}
