package dev.sctvdl.flutter

import android.content.ContentProvider
import android.content.ContentResolver
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.BaseColumns
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import java.io.FileNotFoundException

@RunWith(AndroidJUnit4::class)
class PublishedFileInspectionTest {
    @Test
    fun anAbsentProviderRowReportsMissing() {
        val resolver = ContentResolver.wrap(UnopenableFileProvider(hasRow = false))

        assertEquals(mapOf("exists" to false), inspectPublishedFile(resolver, publishedUri))
    }

    @Test
    fun aPresentButUnreadableRowPropagatesTheFailure() {
        val resolver = ContentResolver.wrap(UnopenableFileProvider(hasRow = true))

        assertThrows(FileNotFoundException::class.java) {
            inspectPublishedFile(resolver, publishedUri)
        }
    }

    private companion object {
        val publishedUri = Uri.parse("content://fixture/downloads/42")
    }

    private class UnopenableFileProvider(
        private val hasRow: Boolean,
    ) : ContentProvider() {
        override fun onCreate() = true

        override fun openFile(
            uri: Uri,
            mode: String,
        ): ParcelFileDescriptor = throw FileNotFoundException(uri.toString())

        override fun query(
            uri: Uri,
            projection: Array<out String>?,
            selection: String?,
            selectionArgs: Array<out String>?,
            sortOrder: String?,
        ): Cursor =
            MatrixCursor(arrayOf(BaseColumns._ID)).apply {
                if (hasRow) {
                    addRow(arrayOf(42L))
                }
            }

        override fun getType(uri: Uri) = "video/mp4"

        override fun insert(
            uri: Uri,
            values: ContentValues?,
        ) = error("Unexpected insertion")

        override fun update(
            uri: Uri,
            values: ContentValues?,
            selection: String?,
            selectionArgs: Array<out String>?,
        ) = error("Unexpected update")

        override fun delete(
            uri: Uri,
            selection: String?,
            selectionArgs: Array<out String>?,
        ) = error("Unexpected deletion")
    }
}
