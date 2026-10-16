package dev.sctvdl.flutter

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.os.Environment
import android.provider.MediaStore
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class MediaStorePublisherTest {
    @Test fun replacesPartialPendingRowsWithoutAcceptingAnInvisibleFile() = recoverPending(7)
    @Test fun replacesFullLengthPendingRowsBeforeReportingPublished() = recoverPending(128)

    private fun recoverPending(pendingBytes: Int) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val resolver = context.contentResolver
        val filename = "publication-fixture-${System.nanoTime()}.mp4"
        val source = File(context.filesDir, filename).apply { writeBytes(ByteArray(128) { it.toByte() }) }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
            put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/sctv-dl/")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val abandoned = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)!!
        resolver.openOutputStream(abandoned)!!.use { it.write(ByteArray(pendingBytes)) }
        var published: android.net.Uri? = null
        try {
            published = MediaStorePublisher(resolver, context.packageName, context.filesDir).publish(source, filename)
            assertNotEquals(abandoned, published)
            resolver.query(abandoned, arrayOf(MediaStore.MediaColumns._ID), null, null, null)!!.use { assertFalse(it.moveToFirst()) }
            resolver.query(published, arrayOf(MediaStore.MediaColumns.IS_PENDING, MediaStore.MediaColumns.OWNER_PACKAGE_NAME), null, null, null)!!.use {
                assertTrue(it.moveToFirst())
                assertEquals(0, it.getInt(0))
                assertEquals(context.packageName, it.getString(1))
            }
            resolver.openInputStream(published)!!.use { assertArrayEquals(source.readBytes(), it.readBytes()) }
            assertTrue(source.exists())
        } finally {
            published?.let { resolver.delete(it, null, null) }
            resolver.delete(abandoned, null, null)
            source.delete()
        }
    }
}
